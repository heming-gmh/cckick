# ccpoint provider: DeepSeek (Anthropic 兼容端点)
# 密钥从 $DEEPSEEK_API_KEY 取(在 ~/.zshrc 里 export),本文件不含明文 key。
ccpoint_p=(
  description "DeepSeek (Anthropic 兼容端点)"
  base_url    "https://api.deepseek.com/anthropic/"
  auth        API_KEY
  auth_var    DEEPSEEK_API_KEY
  model       "deepseek-v4-pro[1m]"
)
