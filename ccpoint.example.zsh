# ccpoint provider example template
#
# Usage: copy to ~/.config/ccpoint/providers/<name>.zsh and edit.
# <name> must be a valid shell identifier ([a-z_][a-z0-9_]*); the filename (minus .zsh) is the
# provider name — used by `ccpoint <name>` and as the suffix of the _start/_stop hook functions.
#
# The key is NEVER in this file — use auth_var to point at an env var you export in ~/.zshrc.

# ─── Simple provider (80% of cases — just fill this table) ─────────────
typeset -A ccpoint_p
ccpoint_p=(
  description  "your provider display name"
  base_url     "https://provider.example.com/anthropic"
  auth         API_KEY            # or AUTH_TOKEN; in AUTH_TOKEN mode ccpoint clears ANTHROPIC_API_KEY to prevent credential bleed
  auth_var     YOUR_PROVIDER_KEY  # which env var holds the key (export YOUR_PROVIDER_KEY=... in ~/.zshrc)
  model        "model-name"       # optional; if unset, claude's default / use /model
  # extra_args  "--dangerously-skip-permissions"  # optional: extra args passed to claude
)

# ─── Complex provider (needs to start a local proxy / prewarm / dynamic port — add hooks) ──
# Uncomment and edit. <name> must match the filename.
#
# ccpoint_start_<name>() {
#   # Pre-launch logic: start process, health check, rewrite base_url dynamically
#   ccpoint_p[base_url]="http://127.0.0.1:4099"
#   your-proxy --port 4099 &
#   CCPOINT_PROXY_PID=$!
#   # Health check: return non-zero → ccpoint aborts launch, calls _stop, exits
#   curl --retry 10 --retry-connrefused -s http://127.0.0.1:4099/health || return 1
# }
#
# ccpoint_stop_<name>() {
#   # Cleanup on exit: ccpoint traps EXIT/INT/TERM/HUP to call this
#   [[ -n "${CCPOINT_PROXY_PID:-}" ]] && kill "$CCPOINT_PROXY_PID" 2>/dev/null
# }
