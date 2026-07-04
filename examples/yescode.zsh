# cckick provider: co.yes.vg relay
# Key is read from $YESCODE_TOKEN. AUTH_TOKEN mode clears ANTHROPIC_API_KEY; model unset → use /model.
cckick_p=(
  description "co.yes.vg relay"
  base_url    "https://co.yes.vg"
  auth        AUTH_TOKEN
  auth_var    YESCODE_TOKEN
)
