# ccpoint provider 示例模板
#
# 用法:拷贝到 ~/.config/ccpoint/providers/<name>.zsh 并修改。
# <name> 必须是合法 shell 标识符([a-z_][a-z0-9_]*),文件名(去 .zsh)即 provider 名,
# 也是 ccpoint <name> 直选时用的名字,以及 _start/_stop 钩子函数名的后缀。
#
# 密钥永远不在本文件里 — 用 auth_var 指向一个环境变量,在 ~/.zshrc 里 export 它。

# ─── 简单 provider(80% 场景,只填这张表)──────────────────────────────
typeset -A ccpoint_p
ccpoint_p=(
  description  "你的 provider 显示名"
  base_url     "https://provider.example.com/anthropic"
  auth         API_KEY            # 或 AUTH_TOKEN(二选一);AUTH_TOKEN 时 ccpoint 自动清空 ANTHROPIC_API_KEY 防串号
  auth_var     YOUR_PROVIDER_KEY  # 从哪个环境变量取密钥(在 ~/.zshrc 里 export YOUR_PROVIDER_KEY=...)
  model        "model-name"       # 可选;不设则用 claude 默认 / 用 /model 现切
  # extra_args  "--dangerously-skip-permissions"  # 可选:额外传给 claude 的参数
)

# ─── 复杂 provider(需要起本地代理 / 预热 / 动态端口等,加钩子)─────────
# 取消注释按需改。<name> 要和文件名一致。
#
# ccpoint_start_<name>() {
#   # 启动前逻辑:起进程、健康检查、动态改写 base_url
#   ccpoint_p[base_url]="http://127.0.0.1:4099"
#   your-proxy --port 4099 &
#   CCPOINT_PROXY_PID=$!
#   # 健康检查:返回非零 → ccpoint 中止启动、调 _stop 清场、报错退出
#   curl --retry 10 --retry-connrefused -s http://127.0.0.1:4099/health || return 1
# }
#
# ccpoint_stop_<name>() {
#   # 退出清场:ccpoint 自动 trap EXIT/INT/TERM/HUP 调用本函数
#   [[ -n "${CCPOINT_PROXY_PID:-}" ]] && kill "$CCPOINT_PROXY_PID" 2>/dev/null
# }
