# ccpoint provider: DeepSeek (Anthropic-compatible endpoint)
# Key is read from $DEEPSEEK_API_KEY (export it in ~/.zshrc); this file holds no plaintext key.
ccpoint_p=(
  description "DeepSeek (Anthropic-compatible)"
  base_url    "https://api.deepseek.com/anthropic/"
  auth        API_KEY
  auth_var    DEEPSEEK_API_KEY
  model       "deepseek-v4-pro[1m]"
)
