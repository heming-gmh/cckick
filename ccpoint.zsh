# shellcheck shell=zsh disable=SC1072,SC1073,SC1036,SC1058,SC1009
# ccpoint.zsh — point Claude Code at any provider endpoint.
# Pure shell · no proxy · exit restores default.
#
# 主逻辑文件,由 ccpoint.plugin.zsh source。
# 用户配置:${CCPOINT_CONFIG_DIR:-${XDG_CONFIG_HOME:-~/.config}/ccpoint}/providers/*.zsh

# 仅 zsh
if [[ -z "$ZSH_VERSION" ]]; then
  print -u 2 "ccpoint: 需要 zsh(当前 shell 不是 zsh)"
  return 1 2>/dev/null || exit 1
fi

# 配置目录(用户可在 source 前覆盖)
: "${CCPOINT_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/ccpoint}"
: "${CCPOINT_PROVIDERS_DIR:=$CCPOINT_CONFIG_DIR/providers}"

# fzf 软依赖(有则上下键+模糊搜索,无则数字菜单)
(( $+commands[fzf] )) && _ccpoint_fzf=1 || _ccpoint_fzf=0

# ─── 私有 ────────────────────────────────────────────────────────────

# 列出所有 provider 名(扫 providers/*.zsh,文件名去扩展名)
_ccpoint_list() {
  [[ -d "$CCPOINT_PROVIDERS_DIR" ]] || return 0
  local f
  for f in "$CCPOINT_PROVIDERS_DIR"/*.zsh(N); do
    print -- "${f:t:r}"
  done
}

# 取某 provider 的 description(子 shell 里 source,不污染当前 shell)
# ⚠ 这会执行 provider 文件的顶层代码 —— 所以 provider 文件顶层只能声明 ccpoint_p + 钩子,
#    不能写副作用(详见 README 安全约定)。
_ccpoint_description() {
  local name="$1"
  local f="$CCPOINT_PROVIDERS_DIR/$name.zsh"
  [[ -f "$f" ]] || { print "(unknown)"; return 1; }
  (
    emulate -L zsh
    typeset -A ccpoint_p=()
    source "$f" 2>/dev/null
    print -r -- "${ccpoint_p[description]:-(no description)}"
  )
}

# 启动一个 provider(子 shell: source → 对称清场 → 装 trap → _start → export → claude)
# trap 在 _start 之前装,任一失败路径(source/防串号/_start/密钥)都会触发 EXIT → _stop 清场。
# 子 shell 一退,父 shell env 没被碰 → 默认端点不受影响。
_ccpoint_launch() {
  local name="$1"

  # 校验 provider 名(防 ../ 路径穿越 + 奇怪字符 —— name 直接拼进 source 路径)
  if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "$name" == *..* ]]; then
    print -u 2 "ccpoint: 非法 provider 名 '$name'(仅允许字母/数字/._-)"
    return 1
  fi
  local f="$CCPOINT_PROVIDERS_DIR/$name.zsh"
  [[ -f "$f" ]] || { print -u 2 "ccpoint: 未找到 provider '$name'(查找:$f)"; return 1; }

  # source 前锁定 claude 绝对路径:provider 可能 export PATH 或定义 claude() 函数劫持,
  # 提前解析 ${commands[claude]} 后调用绝对路径,绕开 PATH 与同名函数。
  local claude_bin="${commands[claude]:-}"
  [[ -n "$claude_bin" ]] || { print -u 2 "ccpoint: 未在 PATH 中找到 claude"; return 1; }

  # reset 钩子间共享状态(防上一次残留的 CCPOINT_PROXY_PID 被本次 _stop 误读)
  unset CCPOINT_PROXY_PID 2>/dev/null

  (
    emulate -L zsh
    typeset -A ccpoint_p=()
    source "$f" 2>/dev/null

    # 校验必填字段(不依赖 source 返回码 —— provider 末尾非 0 语句会让 source 返回非 0)
    if [[ -z "${ccpoint_p[description]}" || -z "${ccpoint_p[auth]}" ]]; then
      print -u 2 "ccpoint: provider '$name' 缺少 description/auth 字段"
      exit 1
    fi

    # 对称清场:丢掉一切从父 shell 继承的 ANTHROPIC_*,只让本 provider 设置的值生效。
    # (旧版只清 AUTH_TOKEN 模式的 API_KEY —— 但 API_KEY 模式不清 AUTH_TOKEN,父 shell
    #  残留的 token 会让 claude 优先用 Bearer 串号。对称 unset 才完整。)
    unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL

    # 先装 trap(在 _start 拉起任何子进程之前)—— 这样 _start 半成功后失败,
    # EXIT trap 也会触发 _stop 清场,不会留孤儿代理。
    # 信号 trap 只负责 exit(转成标准退出码),清理逻辑只挂 EXIT → _stop 恰好执行一次。
    local stop_fn="ccpoint_stop_$name"
    if (( $+functions[$stop_fn] )); then
      trap "$stop_fn" EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      trap 'exit 129' HUP
    fi

    # 启动前钩子(健康检查失败 → exit 1 → EXIT trap → _stop 清场)
    local start_fn="ccpoint_start_$name"
    if (( $+functions[$start_fn] )); then
      "$start_fn" || { print -u 2 "ccpoint: $name 启动前钩子失败(_start 返回非零,代理可能未就绪)"; exit 1; }
    fi

    # 校验 auth_var 非空(否则 (P) 展开查空名变量,报错信息误导)
    local auth_var="${ccpoint_p[auth_var]}"
    if [[ -z "$auth_var" ]]; then
      print -u 2 "ccpoint: provider '$name' 缺少 auth_var 字段(应指向持有密钥的环境变量名)"
      exit 1
    fi
    local key_val="${(P)auth_var:-}"
    if [[ -z "$key_val" ]]; then
      print -u 2 "ccpoint: 环境变量 \$$auth_var 未设置(provider=$name)。请在 .zshrc 里 export 后重开终端。"
      exit 1
    fi

    # export 认证 + 端点
    case "${ccpoint_p[auth]}" in
      API_KEY)    export ANTHROPIC_API_KEY="$key_val" ;;
      AUTH_TOKEN) export ANTHROPIC_AUTH_TOKEN="$key_val" ;;
      *) print -u 2 "ccpoint: auth 应为 API_KEY 或 AUTH_TOKEN(当前:${ccpoint_p[auth]:-空})"; exit 1 ;;
    esac
    [[ -n "${ccpoint_p[base_url]}" ]] && export ANTHROPIC_BASE_URL="${ccpoint_p[base_url]}"
    [[ -n "${ccpoint_p[model]}" ]]    && export ANTHROPIC_MODEL="${ccpoint_p[model]}"

    # 不用 print -P(会把 description 里的 % 当 prompt 转义吃掉);用 ANSI 字面 + -r
    print -r -- $'\e[36m→ ccpoint:\e[0m \e[1m'"$name"$'\e[0m — '"${ccpoint_p[description]}"
    # extra_args 用 (z) shell 词法切词 + (Q) 剥引号,支持含空格的单个参数;
    # 调绝对路径 claude_bin(防 provider 改 PATH 劫持)
    "$claude_bin" ${(Q)${(z)ccpoint_p[extra_args]:-}}
  )
}

# ─── 公开 API ────────────────────────────────────────────────────────

ccpoint() {
  emulate -L zsh
  local cmd="${1:-}"

  case "$cmd" in
    "")
      # 交互选择
      [[ -d "$CCPOINT_PROVIDERS_DIR" ]] || { print -u 2 "ccpoint: 未配置 provider。运行 ccpoint init 或见 README。"; return 1; }
      local names_str=$(_ccpoint_list)
      local -a choices
      choices=()
      local n
      for n in "${(f)names_str}"; do
        [[ -z "$n" ]] && continue
        choices+=("$n|$(_ccpoint_description "$n")")
      done
      (( ${#choices[@]} == 0 )) && { print -u 2 "ccpoint: $CCPOINT_PROVIDERS_DIR 下没有 *.zsh provider 文件"; return 1; }

      local choice name
      if (( _ccpoint_fzf )); then
        choice=$(printf '%s\n' "${choices[@]}" \
          | fzf --prompt='ccpoint ❯ ' \
                --header='上下键选择 · Enter 启动 · Esc 取消' \
                --delimiter='|' --with-nth=2 \
                --height=40% --reverse --tiebreak=index) || return
      else
        # 手动单列菜单:避开 zsh select 多列对中文宽字符的对齐 bug
        local i=1 sel
        print -u 2 "ccpoint — 选一个 provider:"
        for c in "${choices[@]}"; do
          print -u 2 "  $i) ${c#*|}"
          ((i++))
        done
        while read 'sel?ccpoint ❯ # '; do
          if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#choices[@]} )); then
            choice="${choices[sel]}"
            break
          fi
          print -u 2 "  无效,重输 (1-${#choices[@]})"
        done
        [[ -n "$choice" ]] || return
      fi
      name="${choice%%|*}"
      _ccpoint_launch "$name"
      ;;
    list|--list|-l)
      local names_str=$(_ccpoint_list)
      local n
      for n in "${(f)names_str}"; do
        [[ -z "$n" ]] && continue
        print -r -- "$n	$(_ccpoint_description "$n")"
      done
      ;;
    init)
      mkdir -p "$CCPOINT_PROVIDERS_DIR" \
        && print "ccpoint: 已创建 $CCPOINT_PROVIDERS_DIR。把 provider 文件放进去(参考 ccpoint.example.zsh 或 examples/)。"
      ;;
    help|--help|-h)
      print -r -- $'\e[1mccpoint\e[0m — point Claude Code at any provider endpoint.'
      print ""
      print "用法:"
      print "  ccpoint              交互选择 provider(fzf 或数字菜单)"
      print "  ccpoint <name>       直接启动指定 provider"
      print "  ccpoint list         列出所有已配置 provider"
      print "  ccpoint init         创建配置目录 $CCPOINT_PROVIDERS_DIR"
      print "  ccpoint help         显示本帮助"
      print ""
      print "provider 配置:$CCPOINT_PROVIDERS_DIR/*.zsh(见 ccpoint.example.zsh / examples/)"
      ;;
    *)
      _ccpoint_launch "$cmd"
      ;;
  esac
}
