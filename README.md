# cckick

[![license: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)
[![pure shell](https://img.shields.io/badge/pure%20shell-zsh-green)](https://www.zsh.org/)
[![no proxy](https://img.shields.io/badge/no%20proxy-no%20daemon-success)](#why-cckick)
[![fzf optional](https://img.shields.io/badge/fzf-optional-orange)](#interactive-selection)

**Kick Claude Code onto any endpoint. Pure shell · no proxy · exit restores default.**

[English](./README.md) | [中文](./README.zh-CN.md)

<!-- TODO: record an asciinema demo (cckick → fzf select → launch → exit restores default) -->

---

## Why cckick?

Most Claude Code provider switchers (cc-switch, cc-switch-cli, …) work by **rewriting `~/.claude/settings.json`**, running a **local proxy daemon**, or **polluting your shell env**. They're powerful, but they leave state behind:

> [!WARNING]
> stale endpoints, leaked tokens, orphan processes, history/compaction breakage on mid-session switches.

cckick takes the opposite stance — it's a **pure shell function** that launches Claude Code in a **subshell** with the provider's env. When you `exit`, the subshell closes, your parent shell is untouched, and you're back on the default endpoint. No proxy. No settings.json edits. No env pollution. Exit restores default.

| | cc-switch (mainstream GUI) | cc-switch-cli (Rust CLI) | CCM (pure Bash) | **cckick (this repo)** |
|---|---|---|---|---|
| Form | Desktop GUI (Tauri) | Rust binary | Pure Bash | **Pure zsh** |
| Edits `settings.json` | ✓ | ✓ (default) | ✗ | **✗** |
| Runs a proxy | ✗ | optional daemon | ✗ | **✗** |
| Pollutes parent shell env | — | — | **✓** (persistent) | **✗** |
| Restores default on exit | ✗ (persistent) | ✗ (persistent) | ✗ (`exec`) | **✓** |
| Complex providers (local proxy, health check) | — | — | unsupported | **✓ (hooks)** |

The trade-off: cckick is **session-scoped** — each `cckick <name>` launches one Claude Code session on that provider. It's not a global "switch and forget" toggle. If you want a persistent global switch, use cc-switch. If you want a clean, geek-friendly, one-`source`-and-go tool that never leaves a trace, use cckick.

## Installation

```sh
git clone --depth 1 https://github.com/heming-gmh/cckick ~/cckick
echo 'source ~/cckick/cckick.plugin.zsh' >> ~/.zshrc
```

Restart your shell, then put your provider config under `~/.config/cckick/providers/` (see [Provider configuration](#provider-configuration)).

**Plugin managers** (zero extra config — the `.plugin.zsh` entry is the convention):
```sh
# oh-my-zsh
git clone https://github.com/heming-gmh/cckick $ZSH_CUSTOM/plugins/cckick
# then in ~/.zshrc: plugins+=(cckick)
# zplug / zinit / antigen: just load the repo
```

> cckick is **zsh-only**. It will refuse to load under bash. That's **intentional** — cckick aims to be a clean zsh function set, not a lowest-common-denominator polyglot.

## Usage

```sh
cckick              # interactive select (fzf if available, else number menu)
cckick glm          # launch a specific provider directly
cckick list         # list configured providers
cckick init         # create the config dir
cckick help         # show help
```

Inside a session, just `exit` to leave Claude Code — the subshell closes and you're back on the default endpoint. No cleanup step.

## Provider configuration

Each provider is one file: `~/.config/cckick/providers/<name>.zsh`. `<name>` must be a valid shell identifier (`[a-z_][a-z0-9_]*`); it's the name you pass to `cckick <name>` and the suffix of the `_start`/`_stop` hooks.

**Simple provider** (80% of cases — just declare fields):
```zsh
cckick_p=(
  description  "DeepSeek (Anthropic-compatible)"
  base_url     "https://api.deepseek.com/anthropic/"
  auth         API_KEY            # or AUTH_TOKEN
  auth_var     DEEPSEEK_API_KEY   # which env var holds the key (export it in ~/.zshrc)
  model        "deepseek-v4-pro[1m]"
)
```

**Optional fields**: `opus_model` / `sonnet_model` / `haiku_model` set per-tier overrides (→ `ANTHROPIC_DEFAULT_OPUS/SONNET/HAIKU_MODEL`); `extra_env` is a space-separated list of `KEY=VAL` tokens exported before claude starts (e.g. `"API_TIMEOUT_MS=3000000 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"` — split on the first `=`, values may be quoted; non-secret config only, secrets still go through `auth_var`); `extra_args` passes extra CLI args to claude. All are optional and only take effect when set. See [`cckick.example.zsh`](./cckick.example.zsh) for the full annotated schema.

Keys are **never in the provider file** — `auth_var` points at an environment variable you export in `~/.zshrc` (or pull from your password manager). In `AUTH_TOKEN` mode, cckick additionally clears `ANTHROPIC_API_KEY` to prevent credential bleed-through.

**Complex provider** (needs to start a local proxy, pre-warm, etc. — add hooks):
```zsh
cckick_p=(description "local proxy" auth API_KEY auth_var PROXY_KEY)

cckick_start_myproxy() {        # before launch: start process + health check
  cckick_p[base_url]="http://127.0.0.1:4099"   # can rewrite fields dynamically
  your-proxy --port 4099 &
  CCKICK_PROXY_PID=$!           # ⚠ do NOT mark this `local` — _stop reads it
  curl --retry 10 --retry-connrefused -s http://127.0.0.1:4099/health || return 1
}

cckick_stop_myproxy() {         # on exit: cleanup (cckick traps EXIT/INT/TERM/HUP)
  kill "$CCKICK_PROXY_PID" 2>/dev/null
}
```

cckick installs the `EXIT` trap **before** calling `_start`, so even if `_start` starts a process and then fails its health check, `_stop` still runs and cleans up. Recommended `_stop` pattern: `TERM` → wait briefly → `SIGKILL` fallback (see [`examples/opencode_go.zsh`](./examples/opencode_go.zsh)).

See [`cckick.example.zsh`](./cckick.example.zsh) and [`examples/`](./examples/) for more.

## Cost-optimized planner/coder workflows

cckick v0.2's `extra_env` makes the "premium planner + cheap coder" pattern — popularized by Mitchell Hashimoto's Fable-planner / GPT-coder / Fable-judge pipeline — declarative:

```zsh
cckick_p=(
  ...
  model     "premium-planner-model"                          # main loop = planner / judge
  extra_env "CLAUDE_CODE_SUBAGENT_MODEL=cheap-coder-model"   # every subagent = cheap coder
)
```

`CLAUDE_CODE_SUBAGENT_MODEL` overrides the model for **all** subagents (Task / Agent / Workflow). The main session reasons on the premium model; the token-heavy coding runs on a cheap fast one; you act as the judge in the main loop.

**The big constraint** — Claude Code sends an experimental `context_management` beta that only **Anthropic** models accept. Routing any leg (main *or* subagent) to a non-Anthropic model (GLM / Qwen / DeepSeek) via a plain Anthropic-compatible endpoint returns a 400 on the first turn. So:

- **Same-provider, Anthropic-only** (e.g. OpenRouter with `anthropic/claude-fable-5` + `anthropic/claude-haiku-latest`): works natively, no proxy. See [`examples/openrouter.zsh`](./examples/openrouter.zsh).
- **Non-Anthropic cheap coder** (GLM / Qwen / DeepSeek): needs a **stripping / role-routing proxy** (`claude-code-router`, `agentgateway`, LiteLLM, or `oc-cc-proxy`) that drops the beta. cckick launches it via `_start` — see [`examples/opencode_go.zsh`](./examples/opencode_go.zsh) for the pattern.

**Honest limits:**
- One provider per session — all subagents inherit it; cckick can't give different subagents different providers.
- Claude Code does **not** auto-dispatch by task difficulty; `CLAUDE_CODE_SUBAGENT_MODEL` is the lever that forces subagents onto the coder model (all of them, uniformly).
- Mitchell's "few-dollar" figure also relies on running the coder on a flat-rate subscription (ChatGPT) — cckick can't replicate that; cckick's version meters the coder too (cheaply).

## Interactive selection

cckick auto-detects [fzf](https://github.com/junegunn/fzf). With it: arrow keys + fuzzy search. Without it: a number menu (cckick deliberately avoids zsh's built-in `select`, which mangles CJK characters in its multi-column layout). Install fzf for the best experience:
```sh
brew install fzf   # or apt/pacman/dnf/scoop…
```

## How it works

`cckick <name>` is essentially:
```zsh
(                                          # subshell — everything below stays inside
  source ~/.config/cckick/providers/$name.zsh
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL \
        ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL   # symmetric clean slate
  trap cckick_stop_<name> EXIT            # before _start, so failures still clean up
  cckick_start_<name>                     # health check etc. (optional)
  export ANTHROPIC_* …                     # from the declared fields
  claude …                                 # NOT exec — so the EXIT trap fires after claude exits
)
# subshell exits → trap runs → processes cleaned → parent shell untouched → default endpoint
```

No proxy process. No `settings.json` mutation. No env leak to the parent shell.

## Safety notes

- **Provider files are `source`d** — they're zsh, so they can run arbitrary code. cckick `source`s a provider both when launching **and** when listing/menu-rendering (to read its `description`). So only put provider files you trust in `~/.config/cckick/providers/`, and keep their top level free of side effects (declare `cckick_p` + hooks only).
- cckick resolves `claude`'s absolute path **before** sourcing the provider, so a malicious provider can't shadow `claude` via `PATH` or a same-named function.
- Provider names are validated (`[A-Za-z0-9._-]+`, no `..`) to prevent path traversal into `source`.
- `kill -9` / OOM won't trigger the `EXIT` trap — an orphaned proxy could survive. If your `_start` spawns long-running processes, consider a PID file + a `cckick cleanup` step (not built in; kept minimal by design).

## License

[MIT](./LICENSE)
