# ccpoint provider: 智谱 Z.ai 国际版 (GLM-5.2)
# 密钥从 $ZAI_API_KEY 取。AUTH_TOKEN 模式 → ccpoint 自动清空 ANTHROPIC_API_KEY 防串号。
ccpoint_p=(
  description "智谱 Z.ai 国际版 (GLM-5.2)"
  base_url    "https://api.z.ai/api/anthropic"
  auth        AUTH_TOKEN
  auth_var    ZAI_API_KEY
  model       "glm-5.2[1m]"
)
