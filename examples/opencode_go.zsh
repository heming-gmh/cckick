# ccpoint provider: OpenCode Go relay (local proxy)
# "Complex provider" example: starts a local proxy + health check before launch, cleans up on exit.
# Key is read from $OPENCODE_GO_API_KEY.
ccpoint_p=(
  description "OpenCode Go relay (local proxy :4099)"
  auth        API_KEY
  auth_var    OPENCODE_GO_API_KEY
  model       "glm-5.2[1m]"
  # base_url is not hardcoded; _start injects it.
)

# Pre-launch: start proxy + wait for readiness (return non-zero → ccpoint aborts launch;
# EXIT trap will call _stop to clean up).
# ⚠ Do NOT mark CCPOINT_PROXY_PID as local — _stop reads it across functions (see README hook contract).
ccpoint_start_opencode_go() {
  local port="${CCPOINT_PROXY_PORT:-4099}"
  ccpoint_p[base_url]="http://127.0.0.1:$port"
  print -u 2 "→ starting OpenCode Go proxy (port $port)..."
  # ⚠ --api-key is visible in the process list (ps aux; readable by same-machine users). ccpoint's
  #    core deliberately uses env vars to avoid ps leakage — if oc-cc-proxy supports reading the key
  #    from an env var, prefer that (e.g. OC_CC_PROXY_API_KEY=...).
  uvx oc-cc-proxy \
    --api-key "$OPENCODE_GO_API_KEY" \
    --host 127.0.0.1 \
    --port "$port" \
    > /tmp/oc-cc-proxy.log 2>&1 &
  CCPOINT_PROXY_PID=$!

  local _
  for _ in {1..30}; do
    curl -s --connect-timeout 1 "http://127.0.0.1:$port/health" >/dev/null 2>&1 && return 0
    kill -0 "$CCPOINT_PROXY_PID" 2>/dev/null || { print -u 2 "✗ proxy exited, see /tmp/oc-cc-proxy.log"; return 1; }
    sleep 1
  done
  print -u 2 "✗ proxy not ready within 30s"
  return 1
}

# On exit: TERM → brief wait → SIGKILL fallback (prevents a hung proxy from holding the port;
# ccpoint traps EXIT/INT/TERM/HUP to call this).
ccpoint_stop_opencode_go() {
  [[ -n "${CCPOINT_PROXY_PID:-}" ]] || return 0
  kill "$CCPOINT_PROXY_PID" 2>/dev/null
  local _
  for _ in {1..20}; do
    kill -0 "$CCPOINT_PROXY_PID" 2>/dev/null || return 0
    sleep 0.1
  done
  print -u 2 "ccpoint: proxy didn't exit in 2s, SIGKILL"
  kill -9 "$CCPOINT_PROXY_PID" 2>/dev/null
}
