# ccpoint provider: co.yes.vg 中转
# 密钥从 $YESCODE_TOKEN 取。AUTH_TOKEN 模式自动清 API_KEY;不设 model,用 /model 现切。
ccpoint_p=(
  description "co.yes.vg 中转"
  base_url    "https://co.yes.vg"
  auth        AUTH_TOKEN
  auth_var    YESCODE_TOKEN
)
