# ccpoint — 设计文档

> 状态:**设计阶段,待 review 拍板**。基于 4 份社区惯例核实报告(目录/install、provider API、key 脱敏、README/项目文件)+ 前期定位调研。
>
> 仓库里的报告原文与出处见 conversation;本文件是综合后的设计决策。

---

## 1. 定位

**Tagline**: `Point Claude Code at any provider endpoint. Pure shell · no proxy · exit restores default.`

**护城河**(做成默认且唯一的语义,不是可选项):
- 纯 zsh 函数,一个 `source` 就能用,零运行时依赖
- 不跑 proxy / 不改 `~/.claude/settings.json` / 不污染父 shell env
- 子 shell 启动 claude,退出即自动回退默认端点
- 软依赖 fzf(有则上下键 + 模糊搜索,无则降级数字菜单)

**对手与差异化**(README 对比表的核心素材):

| | cc-switch (113K★) | cc-switch-cli (4K★) | CCM (640★) | **ccpoint** |
|---|---|---|---|---|
| 形态 | 桌面 GUI(Tauri) | Rust 二进制 | 纯 Bash | **纯 zsh** |
| 改 settings.json | 是 | 是(默认) | 否 | **否** |
| 跑 proxy | 否 | 可选 daemon | 否 | **否** |
| 污染父 shell env | — | — | **是**(持久) | **否** |
| 退出恢复默认 | 否(持久) | 否(持久) | 否(exec 替换) | **是** |
| 复杂 provider(起代理) | — | — | 不支持 | **支持(钩子)** |

---

## 2. 目录结构

依据 enhancd / zsh-autosuggestions / forgit 的纯 shell 工具惯例。

### 仓库内

```
ccpoint/
├── ccpoint.zsh              # 主逻辑:provider 加载 + fzf/select 调度 + 子 shell 启动
├── ccpoint.plugin.zsh       # 一行薄入口:source ${0:A:h}/ccpoint.zsh(插件管理器零配置识别)
├── completions/_ccpoint     # zsh 补全(进 $fpath)
├── ccpoint.example.zsh      # provider 示例模板(用户拷贝参考,不含真 key)
├── README.md / README.zh-CN.md
├── LICENSE (MIT)
├── CHANGELOG.md
├── CONTRIBUTING.md / CODE_OF_CONDUCT.md
├── Makefile                 # make install / uninstall
└── tests/                   # bats 测试骨架
```

### 用户运行时数据(仓库外,git pull 碰不到 key)

```
${XDG_CONFIG_HOME:-~/.config}/ccpoint/
├── providers/               # 每个 provider 一个 .zsh 文件(用户自己填,gitignore)
│   ├── deepseek.zsh
│   ├── glm.zsh
│   ├── opencode_go.zsh
│   └── yescode.zsh
└── current                  # (可选)当前激活的 provider 名,用于状态提示
```

**关键**:安装目录和用户数据目录分离(pyenv/nvm/enhancd 全这么做)——`git pull` 永远不会冲掉或泄漏用户的 key。

---

## 3. Provider 声明 API(🔴 核心设计决策)

### 推荐:声明式关联数组(底座)+ 按命名约定的可选生命周期钩子(direnv 式)

这是这份设计的核心,也是和 CCM(把所有 provider 写死在 2434 行 case 里)最大的区别。

**provider 文件名 = provider 名,必须是合法 shell 标识符**(`[a-z_][a-z0-9_]*`,带横线的用下划线);显示名走 `description` 字段。

### 简单 provider(80% 场景,零样板)

`~/.config/ccpoint/providers/glm.zsh`:
```zsh
typeset -A ccpoint_provider_glm
ccpoint_provider_glm=(
  description "智谱 Z.ai 国际版 (GLM-5.2)"
  base_url    "https://api.z.ai/api/anthropic"
  auth        AUTH_TOKEN          # API_KEY | AUTH_TOKEN
  auth_var    ZAI_API_KEY         # 从 $ZAI_API_KEY 取密钥
  model       "glm-5.2[1m]"
)
```
ccpoint 核心自动:`AUTH_TOKEN` 模式下清空 `ANTHROPIC_API_KEY`(防串号,抄 oh-my-ccenv)→ export 字段 → 子 shell → exec claude。**用户只声明,不写任何启动逻辑。**

### 复杂 provider(起本地代理,用钩子)

`~/.config/ccpoint/providers/opencode_go.zsh`:
```zsh
typeset -A ccpoint_provider_opencode_go
ccpoint_provider_opencode_go=(
  description "OpenCode Go 中转 (本地代理 :4099)"
  auth        API_KEY
  auth_var    OPENCODE_GO_API_KEY
  model       "glm-5.2[1m]"
  # base_url 不声明,由 _start 动态注入
)

# 启动前钩子(可选):起代理 + 健康检查,可改写声明字段
ccpoint_start_opencode_go() {
  local port=4099
  ccpoint_provider_opencode_go[base_url]="http://127.0.0.1:$port"
  uvx oc-cc-proxy --api-key "$OPENCODE_GO_API_KEY" --host 127.0.0.1 --port $port \
    > /tmp/oc-cc-proxy.log 2>&1 &
  CCPOINT_PROXY_PID=$!
  ccpoint_wait_health "http://127.0.0.1:$port/health" 30 || return 1
}

# 退出钩子(可选):清场
ccpoint_stop_opencode_go() {
  [[ -n "${CCPOINT_PROXY_PID:-}" ]] && kill "$CCPOINT_PROXY_PID" 2>/dev/null
}
```

### 启动主流程(ccpoint 核心负责,provider 不用写)

`ccpoint <name>` 等价于:
```zsh
(
  source ~/.config/ccpoint/providers/$name.zsh
  # AUTH_TOKEN 模式 → 清空 ANTHROPIC_API_KEY(防串号)
  # 有 ccpoint_start_<name> 就调;返回非零(健康检查失败)→ 调 _stop → 退出
  trap ccpoint_stop_<name> EXIT INT TERM HUP   # _stop 不存在就忽略
  export ANTHROPIC_BASE_URL / ANTHROPIC_*_KEY / ANTHROPIC_MODEL
  exec claude
)
# 子 shell 退出 → trap fire → 代理进程清干净 → 父 shell env 没动 → 默认端点
```

### 为什么不是纯函数式(你当前 `.zshrc` 里 cc-flow/cc-zai 那种)?

| | 纯函数式(当前) | **声明式+钩子(推荐)** |
|---|---|---|
| 简单 provider | 重复写子 shell 模板 | **零样板,只声明字段** |
| 通用流程(子shell/trap/exec/防串号) | 每个 provider 各写一遍,易不一致 | **集中在核心,一致 + 少 bug** |
| 复杂 provider(起代理) | 函数里自由写 | **_start/_stop 钩子,同等灵活** |
| 开源后陌生人加 provider | 要看懂模式,手写完整函数 | **简单情况填表,复杂情况查钩子文档** |
| 你现有 4 个 provider 迁移 | — | ✅ 全部可迁(flow/zai/yescode→纯声明;go→声明+_start/_stop) |

> **决策点 ①(最关键)**:采用"声明式+钩子"还是保持"纯函数式"?推荐前者。

---

## 4. Key 脱敏

**默认层(MVP)**:
- provider 文件用 `auth_var` 声明从哪个 env 取 key → key 留在用户的 `.zshrc` / 密码管理器,**provider 文件不落明文**(oh-my-ccenv 的 `No Plaintext Keys` 卖点)
- 仓库提供 `ccpoint.example.zsh` 占位模板;`.gitignore` 兜底忽略 `providers/` 真配置
- 日志 / 错误信息**永不打印 key**(只打 `…xxxx` 后 4 位)

**进阶层(opt-in,以后加)**:
- `ccpoint key set/get <provider>` 子命令:macOS Keychain(`security`)/ Linux Secret Service(`secret-tool`)/ pass·gopass
- provider 声明 `key_source = "env" | "keychain" | "cmd"`,支持 `key_cmd = "pass show ccpoint/anthropic"`

**硬性禁令**:真 key 永不入仓库 / 不入示例 / 不入测试(CI 用 mock)。

> **决策点 ②**:key 默认来源用 env var(`auth_var`,推荐)还是默认就走 keychain?推荐 env var(MVP),keychain 作 opt-in 进阶层。

---

## 5. install 方式

**主推(纯 zsh 惯例,enhancd / zsh-autosuggestions 同款)**:
```sh
git clone --depth 1 https://github.com/<you>/ccpoint ~/somewhere/ccpoint
echo 'source ~/somewhere/ccpoint/ccpoint.plugin.zsh' >> ~/.zshrc
```
+ `make install`(提示 source 行,或 symlink 补全脚本到 `$fpath`)。

**插件管理器**(零额外配置,因为 `.plugin.zsh` 入口已存在):
- oh-my-zsh:`git clone` 到 `$ZSH_CUSTOM/plugins/ccpoint`,`plugins+=(ccpoint)`
- zplug / zinit / antigen:直接 load,默认找 `ccpoint.plugin.zsh`

**明确不做**:
- `curl | sh` 安装器——纯 zsh 工具不需要(enhancd / forgit / zsh-autosuggestions 没一个用),且 `curl|sh` 要用户信任脚本
- npm 全局包——自废"零 Node 依赖"核心卖点

**fzf 软依赖处理**(抄 zoxide.plugin.zsh):
```zsh
if (( $+commands[fzf] )); then
  _ccpoint_fzf=1
else
  _ccpoint_fzf=0
  print -P '%F{yellow}ccpoint: fzf 未检测到,将使用数字菜单(装 fzf 体验更佳: https://github.com/junegunn/fzf)%f'
fi
```

---

## 6. README + LICENSE + 必备文件

### README 结构(基于 zoxide / bat / fzf 实证)
1. **badge 行**(license / pure shell · no proxy / fzf optional)
2. **tagline**(`Point Claude Code at any provider endpoint…`)
3. **语言切换**(`English | 中文`)
4. **Demo**(asciinema 终端录屏,**不是 GIF**——体积小、可选文字、极客审美)
5. **Why ccpoint?** ← 核心武器:叙事 + 第 1 节那张对比矩阵
6. **Installation**(按 §5)
7. **Usage**(cheat sheet 风格:`ccpoint` / `ccpoint glm` 直选 / `ccpoint --list`)
8. **How it works**(解释 no proxy + exit restores default 的实现,1-2 段)

### LICENSE:**MIT**
纯 shell / 通用 CLI 工具的事实标准(zoxide / fzf / bat 都是 MIT)。不用 Apache-2.0(专利条款对 shell 脚本无意义,且与 GPL 不兼容)、不用 GPLv3(强 copyleft 会阻止用户嵌进 dotfiles,降低采用率)。

### 必备文件清单
`LICENSE` / `README.md` / `README.zh-CN.md` / `.gitignore`(`*.zwc` `*.zwc.old` `.DS_Store` `*.log`)/ `CHANGELOG.md`(Keep a Changelog + SemVer)/ `CONTRIBUTING.md`(shellcheck 必过、bats 测试)/ `CODE_OF_CONDUCT.md`(Contributor Covenant)/ `Makefile` / `tests/`

---

## 7. 待你拍板的决策清单

| # | 决策 | 推荐 | 备选 |
|---|---|---|---|
| **①** | **Provider API 形态** | **声明式关联数组 + 钩子** | 纯函数式(当前 .zshrc 模式) |
| ② | 用户数据目录 | `~/.config/ccpoint/`(XDG 标准) | `~/.ccpoint/`(pyenv 风格) |
| ③ | key 默认来源 | env var(`auth_var`) | keychain(作 opt-in 进阶层) |
| ④ | install 主推 | git clone + source + `make install` | curl\|sh / npm(不推荐) |
| ⑤ | LICENSE | MIT | Apache-2.0 / GPLv3(不推荐) |
| ⑥ | README 双语 | 英文 canonical + 中文 | 单英文 |
| ⑦ | MVP 范围 | 核心 + 4 个示例 provider + README + LICENSE + 测试骨架 | + keychain + brew tap(留到 v0.2) |

---

## 8. 实施顺序(设计定稿后)

1. `ccpoint.zsh` 核心:provider 文件加载 + 关联数组解析 + `_start`/`_stop` 钩子 dispatch + fzf/select 调度 + 子 shell 启动 + 防串号
2. 4 个示例 provider 迁移成声明格式(deepseek / glm / opencode_go / yescode)
3. `ccpoint.example.zsh` 模板 + `.gitignore`
4. `Makefile`(install / uninstall)
5. `README.md` + `README.zh-CN.md`(含对比表)
6. `LICENSE` + `CHANGELOG.md` + `CONTRIBUTING.md` + `CODE_OF_CONDUCT.md`
7. `tests/` 骨架(bats:provider 解析、钩子 dispatch、防串号、子 shell 隔离)
8. 你的真实 key 继续留在 `.zshrc` 的 env 里,provider 文件只 `auth_var` 引用——彻底脱敏
