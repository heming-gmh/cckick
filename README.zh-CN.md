# cckick

[![license: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)
[![pure shell](https://img.shields.io/badge/pure%20shell-zsh-green)](https://www.zsh.org/)
[![no proxy](https://img.shields.io/badge/no%20proxy-no%20daemon-success)](#为什么用-cckick)
[![fzf optional](https://img.shields.io/badge/fzf-可选-orange)](#交互选择)

**把 Claude Code 指向任意 provider 端点。纯 shell · 不跑 proxy · 退出即回退默认。**

[English](./README.md) | [中文](./README.zh-CN.md)

<!-- TODO: 录一段 asciinema demo(cckick → fzf 选 provider → 启动 → exit 恢复默认)放这里 -->

---

## 为什么用 cckick?

市面上的 Claude Code provider 切换器(cc-switch、cc-switch-cli 等)大多靠**改写 `~/.claude/settings.json`**、**跑本地 proxy 守护进程**、或**污染你的 shell 环境变量**来工作。它们很强,但会留下状态:

> [!WARNING]
> 残留的端点、泄漏的 token、孤儿进程、会话中切换导致的历史/compaction 出错。

cckick 反其道而行——它是一个**纯 shell 函数**,在一个**子 shell** 里用 provider 的环境变量启动 Claude Code。你 `exit` 退出后,子 shell 关闭,父 shell 毫发无损,默认端点自动恢复。不跑 proxy,不改 settings.json,不污染 env,退出即净。

| | cc-switch(主流 GUI) | cc-switch-cli(Rust CLI) | CCM(纯 Bash) | **cckick(本仓库)** |
|---|---|---|---|---|
| 形态 | 桌面 GUI(Tauri) | Rust 二进制 | 纯 Bash | **纯 zsh** |
| 改 `settings.json` | ✓ | ✓(默认) | ✗ | **✗** |
| 跑 proxy | ✗ | 可选 daemon | ✗ | **✗** |
| 污染父 shell env | — | — | **✓**(持久) | **✗** |
| 退出恢复默认 | ✗(持久) | ✗(持久) | ✗(`exec`) | **✓** |
| 复杂 provider(本地代理/健康检查) | — | — | 不支持 | **✓(钩子)** |

取舍:cckick 是**会话级**的——每次 `cckick <name>` 在该 provider 上启动一次 Claude Code 会话。它不是"切一次就全局生效"的开关。想要持久全局切换,用 cc-switch;想要一个干净、极客、一个 `source` 就能用、不留痕迹的工具,用 cckick。

## 安装

```sh
git clone --depth 1 https://github.com/heming-gmh/cckick ~/cckick
echo 'source ~/cckick/cckick.plugin.zsh' >> ~/.zshrc
```

重开终端,然后把 provider 配置放到 `~/.config/cckick/providers/`(见[provider 配置](#provider-配置))。

**插件管理器**(零额外配置——`.plugin.zsh` 是约定入口):
```sh
# oh-my-zsh
git clone https://github.com/heming-gmh/cckick $ZSH_CUSTOM/plugins/cckick
# 然后在 ~/.zshrc:plugins+=(cckick)
# zplug / zinit / antigen:直接 load 本仓库
```

> cckick **只支持 zsh**,在 bash 下会拒绝加载。这是**刻意为之**——cckick 就是要做一个干净的 zsh 函数集合,不是向下兼容的混合体。

## 用法

```sh
cckick              # 交互选择(有 fzf 用 fzf,否则数字菜单)
cckick glm          # 直接启动指定 provider
cckick list         # 列出已配置 provider
cckick init         # 创建配置目录
cckick help         # 显示帮助
```

会话里 `exit` 退出 Claude Code 即可——子 shell 关闭,回到默认端点,无需手动清理。

## provider 配置

每个 provider 是一个文件:`~/.config/cckick/providers/<name>.zsh`。`<name>` 必须是合法 shell 标识符(`[a-z_][a-z0-9_]*`),它既是 `cckick <name>` 的名字,也是 `_start`/`_stop` 钩子函数名的后缀。

**简单 provider**(80% 场景,只填表):
```zsh
cckick_p=(
  description  "DeepSeek(Anthropic 兼容)"
  base_url     "https://api.deepseek.com/anthropic/"
  auth         API_KEY            # 或 AUTH_TOKEN
  auth_var     DEEPSEEK_API_KEY   # 从哪个环境变量取密钥(在 ~/.zshrc 里 export)
  model        "deepseek-v4-pro[1m]"
)
```

**密钥永远不在 provider 文件里**——`auth_var` 指向一个环境变量,你在 `~/.zshrc` 里 export(或从密码管理器取)。AUTH_TOKEN 模式下,cckick 还会清掉 `ANTHROPIC_API_KEY` 防串号。

**复杂 provider**(需要起本地代理、预热等,加钩子):
```zsh
cckick_p=(description "本地代理" auth API_KEY auth_var PROXY_KEY)

cckick_start_myproxy() {        # 启动前:起进程 + 健康检查
  cckick_p[base_url]="http://127.0.0.1:4099"   # 可动态改写字段
  your-proxy --port 4099 &
  CCKICK_PROXY_PID=$!           # ⚠ 不要加 local —— _stop 要读到它
  curl --retry 10 --retry-connrefused -s http://127.0.0.1:4099/health || return 1
}

cckick_stop_myproxy() {         # 退出:清场(cckick 自动 trap EXIT/INT/TERM/HUP)
  kill "$CCKICK_PROXY_PID" 2>/dev/null
}
```

cckick 在调用 `_start` **之前**就装好 `EXIT` trap,所以即使 `_start` 起了进程再健康检查失败,`_stop` 也会被触发清场。推荐的 `_stop` 写法:TERM → 短暂等待 → SIGKILL 兜底(见 [`examples/opencode_go.zsh`](./examples/opencode_go.zsh))。

更多见 [`cckick.example.zsh`](./cckick.example.zsh) 和 [`examples/`](./examples/)。

## 交互选择

cckick 自动检测 [fzf](https://github.com/junegunn/fzf)。有 fzf:上下键 + 模糊搜索;没 fzf:数字菜单(cckick 刻意没用 zsh 内建的 `select`,因为它的多列布局对中文宽字符对齐有 bug)。装 fzf 体验最佳:
```sh
brew install fzf   # 或 apt/pacman/dnf/scoop…
```

## 工作原理

`cckick <name>` 本质上是:
```zsh
(                                          # 子 shell —— 下面所有改动都隔离在这里
  source ~/.config/cckick/providers/$name.zsh
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL   # 对称清场
  trap cckick_stop_<name> EXIT            # 在 _start 之前装,失败路径也能清场
  cckick_start_<name>                     # 健康检查等(可选)
  export ANTHROPIC_* …                     # 按声明字段
  claude …                                 # 不用 exec —— 这样 claude 退出后 EXIT trap 才会触发
)
# 子 shell 退出 → trap 执行 → 进程清干净 → 父 shell 没被碰 → 默认端点
```

不跑 proxy 进程,不改 settings.json,不往父 shell 泄漏 env。

## 安全约定

- **provider 文件会被 `source`** —— 它是 zsh,能执行任意代码。cckick 在**启动**和**列出/渲染菜单**(为了读 `description`)时都会 source provider。所以只把可信的 provider 放进 `~/.config/cckick/providers/`,且顶层不要写副作用(只声明 `cckick_p` + 钩子)。
- cckick 在 source provider **之前**就解析好 `claude` 的绝对路径,所以恶意 provider 无法通过 `PATH` 或同名函数劫持 `claude`。
- provider 名做了校验(`[A-Za-z0-9._-]+`、禁 `..`),防路径穿越到 `source`。
- `kill -9` / OOM 不会触发 `EXIT` trap —— 孤儿代理可能残留。如果你的 `_start` 起了长驻进程,考虑落 PID 文件 + `cckick cleanup` 步骤(框架刻意没做,保持精简)。

## License

[MIT](./LICENSE)
