# ccpoint provider: OpenCode Go 中转 (本地代理)
# 这是"复杂 provider"示例:启动前起本地代理 + 健康检查,退出时 trap 清场。
# 密钥从 $OPENCODE_GO_API_KEY 取。
ccpoint_p=(
  description "OpenCode Go 中转 (本地代理 :4099)"
  auth        API_KEY
  auth_var    OPENCODE_GO_API_KEY
  model       "glm-5.2[1m]"
  # base_url 不写死,由 _start 动态注入
)

# 启动前:起代理 + 等就绪(返回非零 → ccpoint 中止启动;EXIT trap 会调 _stop 清场)
# ⚠ CCPOINT_PROXY_PID 不要加 local —— _stop 要跨函数读到它(见 README 钩子约定)。
ccpoint_start_opencode_go() {
  local port="${CCPOINT_PROXY_PORT:-4099}"
  ccpoint_p[base_url]="http://127.0.0.1:$port"
  print -u 2 "→ 启动 OpenCode Go 代理(端口 $port)..."
  # ⚠ --api-key 会进进程列表(ps aux 可见,同机其他用户能读)。ccpoint 核心特意走 env var
  #    避开 ps 泄露,这里若 oc-cc-proxy 支持从环境变量读 key,优先用 env 传(如 OC_CC_PROXY_API_KEY=...).
  uvx oc-cc-proxy \
    --api-key "$OPENCODE_GO_API_KEY" \
    --host 127.0.0.1 \
    --port "$port" \
    > /tmp/oc-cc-proxy.log 2>&1 &
  CCPOINT_PROXY_PID=$!

  local i
  for i in {1..30}; do
    curl -s --connect-timeout 1 "http://127.0.0.1:$port/health" >/dev/null 2>&1 && return 0
    kill -0 "$CCPOINT_PROXY_PID" 2>/dev/null || { print -u 2 "✗ 代理进程退出,见 /tmp/oc-cc-proxy.log"; return 1; }
    sleep 1
  done
  print -u 2 "✗ 代理 30s 内未就绪"
  return 1
}

# 退出:TERM → 限时 wait → SIGKILL 兜底(防止代理卡死占端口;ccpoint 自动 trap EXIT/INT/TERM/HUP 调本函数)
ccpoint_stop_opencode_go() {
  [[ -n "${CCPOINT_PROXY_PID:-}" ]] || return 0
  kill "$CCPOINT_PROXY_PID" 2>/dev/null
  local i
  for i in {1..20}; do
    kill -0 "$CCPOINT_PROXY_PID" 2>/dev/null || return 0
    sleep 0.1
  done
  print -u 2 "ccpoint: 代理 2s 未退出,SIGKILL"
  kill -9 "$CCPOINT_PROXY_PID" 2>/dev/null
}
