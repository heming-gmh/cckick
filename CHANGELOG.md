# Changelog

This project follows [Semantic Versioning](https://semver.org/). Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased] — v0.1.0 (in development)

### Added
- Core `ccpoint.zsh`: provider loading, fzf/select dispatch, subshell launch, symmetric credential isolation, exit-restores-default
- Declarative provider API (associative array `ccpoint_p`) + optional `ccpoint_start_<name>` / `ccpoint_stop_<name>` lifecycle hooks (handles complex providers that start a local proxy + health check + trap cleanup)
- 4 example providers: `deepseek` / `glm` (Z.ai) / `opencode_go` (local proxy example) / `yescode`
- fzf soft-dependency (`(( $+commands[fzf] ))`) + number-menu fallback (avoids zsh `select`'s multi-column CJK width alignment bug)
- Subcommands: `ccpoint` (interactive) / `ccpoint <name>` (direct) / `ccpoint list` / `ccpoint init` / `ccpoint help`
- Security: keys never in provider files (read via `auth_var` from env); symmetric `ANTHROPIC_*` clean slate to prevent credential bleed; `claude` path locked before sourcing the provider; provider-name validation against path traversal
