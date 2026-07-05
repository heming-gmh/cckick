# cckick provider: Z.ai (GLM-5.2, Anthropic-compatible)
# Key is read from $ZAI_API_KEY. AUTH_TOKEN mode → cckick clears ANTHROPIC_API_KEY to prevent bleed.
# Showcases per-tier models: Opus/Sonnet stay on GLM-5.2, Haiku downgrades to the faster GLM-4.7.
cckick_p=(
  description "Z.ai (GLM-5.2, Anthropic-compatible)"
  base_url    "https://api.z.ai/api/anthropic"
  auth        AUTH_TOKEN
  auth_var    ZAI_API_KEY
  model       "glm-5.2[1m]"
  opus_model   "glm-5.2[1m]"
  sonnet_model "glm-5.2[1m]"
  haiku_model  "glm-4.7"
)
