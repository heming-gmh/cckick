# cckick provider: Z.ai (GLM-5.2, Anthropic-compatible)
# Key is read from $ZAI_API_KEY. AUTH_TOKEN mode → cckick clears ANTHROPIC_API_KEY to prevent bleed.
cckick_p=(
  description "Z.ai (GLM-5.2, Anthropic-compatible)"
  base_url    "https://api.z.ai/api/anthropic"
  auth        AUTH_TOKEN
  auth_var    ZAI_API_KEY
  model       "glm-5.2[1m]"
)
