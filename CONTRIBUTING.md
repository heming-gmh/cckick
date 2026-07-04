# Contributing

Thanks for your interest in contributing to ccpoint! It's a deliberately small pure-zsh tool, and we want to keep it that way — one `source` to use, no proxy, no `settings.json` edits, exit leaves nothing behind.

## Before submitting a PR

1. **Syntax**: `zsh -n ccpoint.zsh` passes
2. **shellcheck**: `shellcheck ccpoint.zsh examples/*.zsh` (zsh-specific constructs — glob qualifiers `(N)`, `typeset -A`, the source-consumed `ccpoint_p` — produce false positives; see the `# shellcheck` directive at the top of `ccpoint.zsh`)
3. **Tests**: `make test` (or `zsh tests/run.zsh`) all green
4. **Provider files never contain real keys**: use `auth_var` to read from an env var

## Adding a provider template

New provider templates under `examples/` are welcome. Each file:
- declares only the `ccpoint_p` associative array + optional `ccpoint_start_<name>` / `ccpoint_stop_<name>` hooks
- **contains no real key** — uses `auth_var` to point at an env var
- has a filename that's a valid shell identifier (`[a-z_][a-z0-9_]*`), i.e. the provider name

## Commit messages

Concise and clear. Examples: `add provider: openrouter` / `fix: AUTH_TOKEN mode didn't clear API_KEY, causing credential bleed`.

## Design constraints (read before touching the core)

ccpoint's defining property is the default-and-only semantics: **subshell launch + exit-restores-default + no proxy + no settings.json + no parent-shell env pollution**. Changes that weaken these (adding a daemon, writing settings.json, exporting to the parent shell) should be discussed in an issue first.

## Language

Code comments and contributor-facing docs (DESIGN, CONTRIBUTING, COC, CHANGELOG) are in **English**. The README is bilingual (`README.md` / `README.zh-CN.md`) — keep both in sync when changing user-facing content.

## Code of conduct

See [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md). Participating means agreeing to abide by it.
