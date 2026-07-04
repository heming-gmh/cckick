#!/usr/bin/env zsh
# ccpoint 测试套件。用法:zsh tests/run.zsh 或 make test。
# 自包含:建临时 providers + 假 claude,断言核心行为。退出码 0=全过,1=有失败。

emulate -L zsh
set -u

CCPOINT_ROOT=${0:A:h:h}
PASS=0; FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/bin" "$TMP/providers"
cat > "$TMP/bin/claude" <<'EOF'
#!/bin/zsh
echo "API_KEY=${ANTHROPIC_API_KEY:-} TOKEN=${ANTHROPIC_AUTH_TOKEN:-} BASE=${ANTHROPIC_BASE_URL:-} MODEL=${ANTHROPIC_MODEL:-}"
echo "ARGC=$#"
EOF
chmod +x "$TMP/bin/claude"

export CCPOINT_CONFIG_DIR="$TMP" CCPOINT_PROVIDERS_DIR="$TMP/providers"
export PATH="$TMP/bin:$PATH"
source "$CCPOINT_ROOT/ccpoint.zsh"

ok() { print "  ✓ $1"; PASS=$((PASS+1)); }
no() { print "  ✗ $1"; print "    $2"; FAIL=$((FAIL+1)); }

print "ccpoint 测试套件"
print ""

# T1 list
print "T1  ccpoint list"
cat > "$TMP/providers/deepseek.zsh" <<'EOF'
ccpoint_p=(description "DeepSeek" base_url "https://x" auth API_KEY auth_var K1 model "m")
EOF
out=$(ccpoint list)
[[ "$out" == *deepseek* ]] && [[ "$out" == *DeepSeek* ]] && ok "list 列出 provider + description" || no "list" "$out"

# T2 防串号对称(API_KEY 模式也清 AUTH_TOKEN)
print "T2  防串号对称:API_KEY 模式清继承的 AUTH_TOKEN"
export K1=sk-fresh ANTHROPIC_AUTH_TOKEN=STALE
cat > "$TMP/providers/api.zsh" <<'EOF'
ccpoint_p=(description "api" base_url "https://x" auth API_KEY auth_var K1 model "m")
EOF
out=$(ccpoint api 2>/dev/null)
[[ "$out" == *"API_KEY=sk-fresh"* ]] && ok "API_KEY 设值" || no "API_KEY" "$out"
[[ "$out" == *"TOKEN="* && "$out" != *"TOKEN=STALE"* ]] && ok "AUTH_TOKEN 被清(不再串号)" || no "AUTH_TOKEN" "$out"
unset ANTHROPIC_AUTH_TOKEN

# T3 extra_args 引号切词
print "T3  extra_args 引号切词(含空格参数不被切碎)"
cat > "$TMP/providers/args.zsh" <<'EOF'
ccpoint_p=(description "args" base_url "https://x" auth API_KEY auth_var K1 model "m" extra_args '--header "a b c" --flag')
EOF
out=$(ccpoint args 2>/dev/null)
[[ "$out" == *"ARGC=3"* ]] && ok "切出 3 个参数(引号剥掉)" || no "extra_args" "$out"

# T4 _start 失败 → EXIT trap 清场(critical)
print "T4  _start 失败 → EXIT trap 清场(代理不残留)"
cat > "$TMP/providers/leak.zsh" <<'EOF'
ccpoint_p=(description "leak" auth API_KEY auth_var K1 model "m")
ccpoint_start_leak() {
  sleep 30 &
  CCPOINT_PROXY_PID=$!
  return 1
}
ccpoint_stop_leak() {
  kill "$CCPOINT_PROXY_PID" 2>/dev/null
}
EOF
ccpoint leak >/dev/null 2>&1
sleep 0.3
if pgrep -f 'sleep 30' >/dev/null; then
  no "代理泄漏" "sleep 30 残留"; pkill -f 'sleep 30' 2>/dev/null
else
  ok "代理已清(无残留)"
fi

# T5 name 校验(防路径穿越)
print "T5  name 校验(防 ../ 路径穿越)"
ccpoint '../evil' >/dev/null 2>&1 && no "../ 未被拒" "" || ok "../ 被拒"
ccpoint 'a;b'      >/dev/null 2>&1 && no "分号未被拒" "" || ok "分号被拒"

# T6 print 不吃 %
print "T6  print 不把 description 的 % 当转义吃掉"
cat > "$TMP/providers/pct.zsh" <<'EOF'
ccpoint_p=(description "50%off 促销" auth API_KEY auth_var K1 model "m")
EOF
out=$(ccpoint pct 2>&1)
[[ "$out" == *"50%off"* ]] && ok "50%off 原样显示" || no "print %" "$out"

print ""
print "结果:$PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1
