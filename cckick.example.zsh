# cckick provider example template
#
# Usage: copy to ~/.config/cckick/providers/<name>.zsh and edit.
# <name> must be a valid shell identifier ([a-z_][a-z0-9_]*); the filename (minus .zsh) is the
# provider name — used by `cckick <name>` and as the suffix of the _start/_stop hook functions.
#
# The key is NEVER in this file — use auth_var to point at an env var you export in ~/.zshrc.

# ─── Simple provider (80% of cases — just fill this table) ─────────────
typeset -A cckick_p
cckick_p=(
  description  "your provider display name"
  base_url     "https://provider.example.com/anthropic"
  auth         API_KEY            # or AUTH_TOKEN; in AUTH_TOKEN mode cckick clears ANTHROPIC_API_KEY to prevent credential bleed
  auth_var     YOUR_PROVIDER_KEY  # which env var holds the key (export YOUR_PROVIDER_KEY=... in ~/.zshrc)
  model        "model-name"       # optional; if unset, claude's default / use /model
  opus_model   "opus-model-id"    # optional per-tier override → ANTHROPIC_DEFAULT_OPUS_MODEL
  sonnet_model "sonnet-model-id"  # optional per-tier override → ANTHROPIC_DEFAULT_SONNET_MODEL
  haiku_model  "haiku-model-id"   # optional per-tier override → ANTHROPIC_DEFAULT_HAIKU_MODEL
  extra_env    "API_TIMEOUT_MS=3000000 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"  # optional: space-separated KEY=VAL tokens exported before claude (non-secret config only; split on first '=', values may be quoted)
  # extra_args  "--dangerously-skip-permissions"  # optional: extra args passed to claude
)

# ─── Complex provider (needs to start a local proxy / prewarm / dynamic port — add hooks) ──
# Uncomment and edit. <name> must match the filename.
#
# cckick_start_<name>() {
#   # Pre-launch logic: start process, health check, rewrite base_url dynamically
#   cckick_p[base_url]="http://127.0.0.1:4099"
#   your-proxy --port 4099 &
#   CCKICK_PROXY_PID=$!
#   # Health check: return non-zero → cckick aborts launch, calls _stop, exits
#   curl --retry 10 --retry-connrefused -s http://127.0.0.1:4099/health || return 1
# }
#
# cckick_stop_<name>() {
#   # Cleanup on exit: cckick traps EXIT/INT/TERM/HUP to call this
#   [[ -n "${CCKICK_PROXY_PID:-}" ]] && kill "$CCKICK_PROXY_PID" 2>/dev/null
# }
