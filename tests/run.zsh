#!/usr/bin/env zsh
# cckick test suite. Usage: zsh tests/run.zsh or `make test`.
# Self-contained: builds a temp providers dir + a fake claude, asserts core behavior.
# Exit code 0 = all pass, 1 = at least one failure.

emulate -L zsh
set -u

CCKICK_ROOT=${0:A:h:h}
PASS=0; FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/bin" "$TMP/providers"
cat > "$TMP/bin/claude" <<'EOF'
#!/bin/zsh
echo "API_KEY=${ANTHROPIC_API_KEY:-} TOKEN=${ANTHROPIC_AUTH_TOKEN:-} BASE=${ANTHROPIC_BASE_URL:-} MODEL=${ANTHROPIC_MODEL:-}"
echo "OPUS=${ANTHROPIC_DEFAULT_OPUS_MODEL:-} SONNET=${ANTHROPIC_DEFAULT_SONNET_MODEL:-} HAIKU=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-} TIMEOUT=${API_TIMEOUT_MS:-} TRAFFIC=${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"
echo "ARGC=$#"
EOF
chmod +x "$TMP/bin/claude"

export CCKICK_CONFIG_DIR="$TMP" CCKICK_PROVIDERS_DIR="$TMP/providers"
export PATH="$TMP/bin:$PATH"
source "$CCKICK_ROOT/cckick.zsh"

ok() { print "  ✓ $1"; PASS=$((PASS+1)); }
no() { print "  ✗ $1"; print "    $2"; FAIL=$((FAIL+1)); }

print "cckick test suite"
print ""

# T1 list
print "T1  cckick list"
cat > "$TMP/providers/deepseek.zsh" <<'EOF'
cckick_p=(description "DeepSeek" base_url "https://x" auth API_KEY auth_var K1 model "m")
EOF
out=$(cckick list)
[[ "$out" == *deepseek* ]] && [[ "$out" == *DeepSeek* ]] && ok "list shows provider + description" || no "list" "$out"

# T2 symmetric credential isolation (API_KEY mode also clears inherited AUTH_TOKEN)
print "T2  symmetric isolation: API_KEY mode clears inherited AUTH_TOKEN"
export K1=sk-fresh ANTHROPIC_AUTH_TOKEN=STALE
cat > "$TMP/providers/api.zsh" <<'EOF'
cckick_p=(description "api" base_url "https://x" auth API_KEY auth_var K1 model "m")
EOF
out=$(cckick api 2>/dev/null)
[[ "$out" == *"API_KEY=sk-fresh"* ]] && ok "API_KEY set" || no "API_KEY" "$out"
[[ "$out" == *"TOKEN="* && "$out" != *"TOKEN=STALE"* ]] && ok "AUTH_TOKEN cleared (no bleed)" || no "AUTH_TOKEN" "$out"
unset ANTHROPIC_AUTH_TOKEN

# T3 extra_args quote-aware splitting
print "T3  extra_args quote-aware splitting (spaces inside one arg preserved)"
cat > "$TMP/providers/args.zsh" <<'EOF'
cckick_p=(description "args" base_url "https://x" auth API_KEY auth_var K1 model "m" extra_args '--header "a b c" --flag')
EOF
out=$(cckick args 2>/dev/null)
[[ "$out" == *"ARGC=3"* ]] && ok "split into 3 args (quotes stripped)" || no "extra_args" "$out"

# T4 _start failure → EXIT trap cleanup (no orphan)
print "T4  _start failure → EXIT trap cleanup (no orphan process)"
cat > "$TMP/providers/leak.zsh" <<'EOF'
cckick_p=(description "leak" auth API_KEY auth_var K1 model "m")
cckick_start_leak() {
  sleep 30 &
  CCKICK_PROXY_PID=$!
  return 1
}
cckick_stop_leak() {
  kill "$CCKICK_PROXY_PID" 2>/dev/null
}
EOF
cckick leak >/dev/null 2>&1
sleep 0.3
if pgrep -f 'sleep 30' >/dev/null; then
  no "orphan leaked" "sleep 30 still alive"; pkill -f 'sleep 30' 2>/dev/null
else
  ok "process cleaned up (no orphan)"
fi

# T5 name validation (path traversal prevention)
print "T5  name validation (../ path traversal rejected)"
cckick '../evil' >/dev/null 2>&1 && no "../ not rejected" "" || ok "../ rejected"
cckick 'a;b'      >/dev/null 2>&1 && no "semicolon not rejected" "" || ok "semicolon rejected"

# T6 print doesn't eat %
print "T6  print doesn't treat % in description as a prompt escape"
cat > "$TMP/providers/pct.zsh" <<'EOF'
cckick_p=(description "50%off sale" auth API_KEY auth_var K1 model "m")
EOF
out=$(cckick pct 2>&1)
[[ "$out" == *"50%off"* ]] && ok "50%off shown verbatim" || no "print %" "$out"

# T7 per-tier model overrides → ANTHROPIC_DEFAULT_<TIER>_MODEL
print "T7  per-tier model overrides map to ANTHROPIC_DEFAULT_<TIER>_MODEL"
cat > "$TMP/providers/tier.zsh" <<'EOF'
cckick_p=(description "tier" base_url "https://x" auth API_KEY auth_var K1 model "m" opus_model "opus-m" sonnet_model "sonnet-m" haiku_model "haiku-m")
EOF
out=$(cckick tier 2>/dev/null)
[[ "$out" == *"OPUS=opus-m"* ]]   && ok "opus_model → ANTHROPIC_DEFAULT_OPUS_MODEL"   || no "opus_model"   "$out"
[[ "$out" == *"SONNET=sonnet-m"* ]] && ok "sonnet_model → ANTHROPIC_DEFAULT_SONNET_MODEL" || no "sonnet_model" "$out"
[[ "$out" == *"HAIKU=haiku-m"* ]]  && ok "haiku_model → ANTHROPIC_DEFAULT_HAIKU_MODEL"  || no "haiku_model"  "$out"

# T8 extra_env: space-separated KEY=VAL tokens exported before claude
print "T8  extra_env KEY=VAL tokens exported before claude"
cat > "$TMP/providers/env.zsh" <<'EOF'
cckick_p=(description "env" base_url "https://x" auth API_KEY auth_var K1 model "m" extra_env "API_TIMEOUT_MS=3000000 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1")
EOF
out=$(cckick env 2>/dev/null)
[[ "$out" == *"TIMEOUT=3000000"* ]] && ok "API_TIMEOUT_MS exported" || no "extra_env TIMEOUT" "$out"
[[ "$out" == *"TRAFFIC=1"* ]]       && ok "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC exported" || no "extra_env TRAFFIC" "$out"

# T9 symmetric isolation: inherited ANTHROPIC_DEFAULT_*_MODEL cleared when the provider sets none
print "T9  symmetric isolation: inherited per-tier models cleared"
export ANTHROPIC_DEFAULT_OPUS_MODEL=STALE_O ANTHROPIC_DEFAULT_SONNET_MODEL=STALE_S ANTHROPIC_DEFAULT_HAIKU_MODEL=STALE_H
cat > "$TMP/providers/bare.zsh" <<'EOF'
cckick_p=(description "bare" base_url "https://x" auth API_KEY auth_var K1 model "m")
EOF
out=$(cckick bare 2>/dev/null)
[[ "$out" == *"OPUS="* && "$out" != *"STALE_O"* ]]  && ok "inherited OPUS cleared"   || no "OPUS isolation"   "$out"
[[ "$out" == *"HAIKU="* && "$out" != *"STALE_H"* ]] && ok "inherited HAIKU cleared" || no "HAIKU isolation" "$out"
unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL

print ""
print "result: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
