# ccpoint

[![license: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)
[![pure shell](https://img.shields.io/badge/pure%20shell-zsh-green)](https://www.zsh.org/)
[![no proxy](https://img.shields.io/badge/no%20proxy-no%20daemon-success)](#why-ccpoint)
[![fzf optional](https://img.shields.io/badge/fzf-optional-orange)](#interactive-selection)

**Point Claude Code at any provider endpoint. Pure shell · no proxy · exit restores default.**

[English](./README.md) | [中文](./README.zh-CN.md)

<!-- TODO: 录一段 asciinema demo(ccpoint → fzf 选 provider → 启动 → exit 恢复默认)放这里 -->

---

## Why ccpoint?

Most Claude Code provider switchers (cc-switch, cc-switch-cli, …) work by **rewriting `~/.claude/settings.json`**, running a **local proxy daemon**, or **polluting your shell env**. They're powerful, but they leave state behind: stale endpoints, leaked tokens, orphan processes, history/compaction breakage on mid-session switches.

ccpoint takes the opposite stance — it's a **pure shell function** that launches Claude Code in a **subshell** with the provider's env. When you `exit`, the subshell closes, your parent shell is untouched, and you're back on the default endpoint. No proxy. No settings.json edits. No env pollution. Exit restores default.

| | cc-switch (113K★) | cc-switch-cli (4K★) | CCM (640★) | **ccpoint** |
|---|---|---|---|---|
| Form | Desktop GUI (Tauri) | Rust binary | Pure Bash | **Pure zsh** |
| Edits `settings.json` | ✓ | ✓ (default) | ✗ | **✗** |
| Runs a proxy | ✗ | optional daemon | ✗ | **✗** |
| Pollutes parent shell env | — | — | **✓** (persistent) | **✗** |
| Restores default on exit | ✗ (persistent) | ✗ (persistent) | ✗ (`exec`) | **✓** |
| Complex providers (local proxy, health check) | — | — | unsupported | **✓ (hooks)** |

The trade-off: ccpoint is **session-scoped** — each `ccpoint <name>` launches one Claude Code session on that provider. It's not a global "switch and forget" toggle. If you want a persistent global switch, use cc-switch. If you want a clean, geek-friendly, one-`source`-and-go tool that never leaves a trace, use ccpoint.

## Installation

```sh
git clone --depth 1 https://github.com/heming-gmh/ccpoint ~/ccpoint
echo 'source ~/ccpoint/ccpoint.plugin.zsh' >> ~/.zshrc
```

Restart your shell, then put your provider config under `~/.config/ccpoint/providers/` (see [Provider configuration](#provider-configuration)).

**Plugin managers** (zero extra config — the `.plugin.zsh` entry is the convention):
```sh
# oh-my-zsh
git clone https://github.com/heming-gmh/ccpoint $ZSH_CUSTOM/plugins/ccpoint
# then in ~/.zshrc: plugins+=(ccpoint)
# zplug / zinit / antigen: just load the repo
```

> ccpoint is **zsh-only**. It will refuse to load under bash. That's intentional — the whole point is a clean zsh function set, not a lowest-common-denominator polyglot.

## Usage

```sh
ccpoint              # interactive select (fzf if available, else number menu)
ccpoint glm          # launch a specific provider directly
ccpoint list         # list configured providers
ccpoint init         # create the config dir
ccpoint help         # show help
```

Inside a session, just `exit` to leave Claude Code — the subshell closes and you're back on the default endpoint. No cleanup step.

## Provider configuration

Each provider is one file: `~/.config/ccpoint/providers/<name>.zsh`. `<name>` must be a valid shell identifier (`[a-z_][a-z0-9_]*`); it's the name you pass to `ccpoint <name>` and the suffix of the `_start`/`_stop` hooks.

**Simple provider** (80% of cases — just declare fields):
```zsh
ccpoint_p=(
  description  "DeepSeek (Anthropic-compatible)"
  base_url     "https://api.deepseek.com/anthropic/"
  auth         API_KEY            # or AUTH_TOKEN
  auth_var     DEEPSEEK_API_KEY   # which env var holds the key (export it in ~/.zshrc)
  model        "deepseek-v4-pro[1m]"
)
```

Keys are **never in the provider file** — `auth_var` points at an environment variable you export in `~/.zshrc` (or pull from your password manager). In `AUTH_TOKEN` mode, ccpoint additionally clears `ANTHROPIC_API_KEY` to prevent credential bleed-through.

**Complex provider** (needs to start a local proxy, pre-warm, etc. — add hooks):
```zsh
ccpoint_p=(description "local proxy" auth API_KEY auth_var PROXY_KEY)

ccpoint_start_myproxy() {        # before launch: start process + health check
  ccpoint_p[base_url]="http://127.0.0.1:4099"   # can rewrite fields dynamically
  your-proxy --port 4099 &
  CCPOINT_PROXY_PID=$!           # ⚠ do NOT mark this `local` — _stop reads it
  curl --retry 10 --retry-connrefused -s http://127.0.0.1:4099/health || return 1
}

ccpoint_stop_myproxy() {         # on exit: cleanup (ccpoint traps EXIT/INT/TERM/HUP)
  kill "$CCPOINT_PROXY_PID" 2>/dev/null
}
```

ccpoint installs the `EXIT` trap **before** calling `_start`, so even if `_start` starts a process and then fails its health check, `_stop` still runs and cleans up. Recommended `_stop` pattern: `TERM` → wait briefly → `SIGKILL` fallback (see [`examples/opencode_go.zsh`](./examples/opencode_go.zsh)).

See [`ccpoint.example.zsh`](./ccpoint.example.zsh) and [`examples/`](./examples/) for more.

## Interactive selection

ccpoint auto-detects [fzf](https://github.com/junegunn/fzf). With it: arrow keys + fuzzy search. Without it: a number menu (ccpoint deliberately avoids zsh's built-in `select`, which mangles CJK characters in its multi-column layout). Install fzf for the best experience:
```sh
brew install fzf   # or apt/pacman/dnf/scoop…
```

## How it works

`ccpoint <name>` is essentially:
```zsh
(                                          # subshell — everything below stays inside
  source ~/.config/ccpoint/providers/$name.zsh
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL   # symmetric clean slate
  trap ccpoint_stop_<name> EXIT            # before _start, so failures still clean up
  ccpoint_start_<name>                     # health check etc. (optional)
  export ANTHROPIC_* …                     # from the declared fields
  claude …                                 # NOT exec — so the EXIT trap fires after claude exits
)
# subshell exits → trap runs → processes cleaned → parent shell untouched → default endpoint
```

No proxy process. No `settings.json` mutation. No env leak to the parent shell.

## Safety notes

- **Provider files are `source`d** — they're zsh, so they can run arbitrary code. ccpoint `source`s a provider both when launching **and** when listing/menu-rendering (to read its `description`). So only put provider files you trust in `~/.config/ccpoint/providers/`, and keep their top level free of side effects (declare `ccpoint_p` + hooks only).
- ccpoint resolves `claude`'s absolute path **before** sourcing the provider, so a malicious provider can't shadow `claude` via `PATH` or a same-named function.
- Provider names are validated (`[A-Za-z0-9._-]+`, no `..`) to prevent path traversal into `source`.
- `kill -9` / OOM won't trigger the `EXIT` trap — an orphaned proxy could survive. If your `_start` spawns long-running processes, consider a PID file + a `ccpoint cleanup` step (not built in; kept minimal by design).

## License

[MIT](./LICENSE)
