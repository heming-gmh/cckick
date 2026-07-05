# Changelog

This project follows [Semantic Versioning](https://semver.org/). Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased] — v0.2.0 (in development)

### Added
- Per-tier model overrides: `opus_model` / `sonnet_model` / `haiku_model` fields → `ANTHROPIC_DEFAULT_OPUS/SONNET/HAIKU_MODEL` (a provider may set `model`, per-tier, both, or neither)
- `extra_env` field: space-separated `KEY=VAL` tokens exported before claude starts (e.g. `API_TIMEOUT_MS=3000000`); split on the first `=`, values may be quoted; non-secret config only — secrets still go through `auth_var`
- Symmetric clean slate now also clears `ANTHROPIC_DEFAULT_OPUS/SONNET/HAIKU_MODEL` on subshell entry, so a parent-shell per-tier default can't leak into a provider that pins none

### Changed
- `examples/opencode_go.zsh` `_start` now reuses an already-running proxy via a `/health` probe instead of always spawning a fresh one; `_stop` is a no-op in the reuse path
- `examples/opencode_go.zsh` cold-start readiness timeout bumped 30s → 60s (uvx download + litellm init can exceed 30s on a first run)

## [Unreleased] — v0.1.0 (in development)

### Added
- Core `cckick.zsh`: provider loading, fzf/select dispatch, subshell launch, symmetric credential isolation, exit-restores-default
- Declarative provider API (associative array `cckick_p`) + optional `cckick_start_<name>` / `cckick_stop_<name>` lifecycle hooks (handles complex providers that start a local proxy + health check + trap cleanup)
- 4 example providers: `deepseek` / `glm` (Z.ai) / `opencode_go` (local proxy example) / `yescode`
- fzf soft-dependency (`(( $+commands[fzf] ))`) + number-menu fallback (avoids zsh `select`'s multi-column CJK width alignment bug)
- Subcommands: `cckick` (interactive) / `cckick <name>` (direct) / `cckick list` / `cckick init` / `cckick help`
- Security: keys never in provider files (read via `auth_var` from env); symmetric `ANTHROPIC_*` clean slate to prevent credential bleed; `claude` path locked before sourcing the provider; provider-name validation against path traversal
