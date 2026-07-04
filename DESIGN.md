# ccpoint — Design

> This document records ccpoint's architecture and key decisions, for contributors who want to understand *why* it's built this way.

## 1. Positioning

**Tagline**: `Point Claude Code at any provider endpoint. Pure shell · no proxy · exit restores default.`

The defining property — default and only semantics, not an option:
- Pure zsh function; one `source` to use; zero runtime deps
- No proxy / no `~/.claude/settings.json` edits / no parent-shell env pollution
- Claude Code launched in a subshell; exiting it restores the default endpoint
- fzf is a soft dependency (arrow keys + fuzzy search if present, number menu otherwise)

How it differs from incumbents:

| | cc-switch (mainstream GUI) | cc-switch-cli (Rust CLI) | CCM (pure Bash) | **ccpoint (this repo)** |
|---|---|---|---|---|
| Form | Desktop GUI (Tauri) | Rust binary | Pure Bash | **Pure zsh** |
| Edits `settings.json` | yes | yes (default) | no | **no** |
| Runs a proxy | no | optional daemon | no | **no** |
| Pollutes parent shell | — | — | **yes** (persistent) | **no** |
| Restores default on exit | no (persistent) | no (persistent) | no (`exec`) | **yes** |
| Complex providers (local proxy) | — | — | unsupported | **yes (hooks)** |

## 2. Directory layout

Repository:
```
ccpoint/
├── ccpoint.zsh              # main logic
├── ccpoint.plugin.zsh       # thin entry (sourced by plugin managers)
├── examples/                # community provider templates
├── ccpoint.example.zsh      # annotated "how to write a provider" template
├── README.md / README.zh-CN.md
├── DESIGN.md / CHANGELOG.md / CONTRIBUTING.md / CODE_OF_CONDUCT.md
├── LICENSE (MIT) / Makefile / .gitignore
└── tests/run.zsh
```

User runtime data (outside the repo, so `git pull` can never touch keys):
```
${XDG_CONFIG_HOME:-~/.config}/ccpoint/
└── providers/<name>.zsh     # one file per provider (user-filled, gitignored)
```

## 3. Provider API

A provider is one file: `~/.config/ccpoint/providers/<name>.zsh`. `<name>` is a valid shell identifier.

**Simple provider** (80% of cases — declare fields only):
```zsh
ccpoint_p=(
  description  "DeepSeek"
  base_url     "https://api.deepseek.com/anthropic/"
  auth         API_KEY            # or AUTH_TOKEN
  auth_var     DEEPSEEK_API_KEY   # which env var holds the key
  model        "deepseek-v4-pro[1m]"
)
```

**Complex provider** (starts a local proxy, etc. — add lifecycle hooks):
```zsh
ccpoint_p=(description "local proxy" auth API_KEY auth_var PROXY_KEY)

ccpoint_start_myproxy() {        # before launch: start process + health check
  ccpoint_p[base_url]="http://127.0.0.1:4099"
  your-proxy --port 4099 &
  CCPOINT_PROXY_PID=$!           # ⚠ not `local` — _stop reads it
  curl --retry 10 --retry-connrefused -s http://127.0.0.1:4099/health || return 1
}

ccpoint_stop_myproxy() {         # on exit: cleanup (ccpoint traps EXIT/INT/TERM/HUP)
  kill "$CCPOINT_PROXY_PID" 2>/dev/null
}
```

The launch flow (ccpoint core owns this; providers don't repeat it):
1. subshell; source the provider file
2. symmetric `unset` of all `ANTHROPIC_*` (clean slate)
3. install `trap _stop EXIT` **before** `_start` (so a half-started `_start` still cleans up)
4. call `_start` (health check; failure aborts → EXIT trap → _stop)
5. `export ANTHROPIC_*` from declared fields
6. run `claude` (not `exec` — so the EXIT trap fires after claude exits)
7. subshell exits → parent shell untouched → default endpoint

Why declarative + hooks (not pure-function, not pure-declarative):
- Simple providers get zero boilerplate (just the table)
- The shared flow (subshell / trap / clean-slate / anti-bleed) lives in one place → consistent, fewer bugs
- Complex providers escape via `_start`/`_stop` — full shell, no loss of flexibility vs pure-function
- `ccpoint_stop` runs exactly once: `EXIT` trap does cleanup; `INT`/`TERM`/`HUP` traps only `exit N`, which re-triggers `EXIT`

## 4. Security

- **Keys never in provider files** — `auth_var` points at an env var (kept in `~/.zshrc` / password manager)
- **Symmetric credential isolation** — on subshell entry, all `ANTHROPIC_*` are unset, then only this provider's values are exported (prevents a stale inherited token from making claude use the wrong account)
- **claude path locked before sourcing** — `${commands[claude]}` is resolved before the provider file runs, so a provider can't shadow `claude` via `PATH` or a same-named function
- **Provider-name validation** — `[A-Za-z0-9._-]+`, no `..` (prevents path traversal into `source`)
- **Provider files are `source`d** — they're zsh and can run arbitrary code; this happens both when launching *and* when listing/menu-rendering (to read `description`). So only put trusted provider files in the providers dir, and keep their top level free of side effects (declare `ccpoint_p` + hooks only)
- **`kill -9` / OOM** won't fire the EXIT trap — an orphaned proxy could survive; if a `_start` spawns long-running processes, a PID file + cleanup step is the provider's responsibility

## 5. Install

```sh
git clone --depth 1 https://github.com/heming-gmh/ccpoint ~/ccpoint
echo 'source ~/ccpoint/ccpoint.plugin.zsh' >> ~/.zshrc
```

Plugin-manager friendly via the `.plugin.zsh` entry (oh-my-zsh / zplug / zinit). No `curl|sh` installer (pure-shell tools don't need one) and no npm package (would negate the zero-Node-dep property). fzf is auto-detected; missing fzf degrades to a number menu rather than erroring.

## 6. README structure

badges → tagline → language switch → demo (asciinema, todo) → **Why ccpoint?** (the comparison table is the key weapon) → Installation → Usage (cheat-sheet) → How it works → Safety notes.

## 7. Language policy

Code comments and contributor-facing docs (DESIGN, CONTRIBUTING, COC, CHANGELOG) are in **English** (open-source convention; Chinese-speakers read English technical comments readily, the reverse isn't true). The README is bilingual for the user-facing surface.
