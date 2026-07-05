# cckick provider: OpenRouter — hosted aggregator (Anthropic-compatible)
#
# Demonstrates the "planner/coder" cost split (cf. Mitchell Hashimoto's
# Fable-planner / cheap-coder / Fable-judge pipeline): the MAIN loop runs a
# premium reasoning model (you act as the planner/judge interactively), and
# every subagent (Task/Agent/Workflow — the bulk of the token-heavy coding)
# runs a cheap fast model via CLAUDE_CODE_SUBAGENT_MODEL. cckick v0.2's
# extra_env does both jobs in one line:
#   - CLAUDE_CODE_SUBAGENT_MODEL forces ALL subagents onto the cheap coder;
#   - ANTHROPIC_API_KEY (set to empty) is REQUIRED by OpenRouter: it expects
#     Bearer auth (ANTHROPIC_AUTH_TOKEN, i.e. auth=AUTH_TOKEN) and a SET-BUT-
#     EMPTY API key (if it's unset, Claude Code may fall back to first-party
#     Anthropic and 401). extra_env exports it empty AFTER cckick's clean-slate
#     unset, satisfying both. (Verified: extra_env parses KEY= empty values.)
#
# Key from $OPENROUTER_API_KEY (export it in ~/.zshrc). Verify the exact slugs
# on https://openrouter.ai/anthropic — they shift between model generations.
#
# ⚠ ANTHROPIC MODELS ONLY via this native endpoint. Claude Code sends an
#    experimental `context_management` beta that only Anthropic first-party
#    models accept; routing any leg to a non-Anthropic model (GLM/Qwen/DeepSeek)
#    400s on the first turn. To use a non-Anthropic cheap coder, point cckick at
#    a stripping / role-routing proxy instead — see examples/opencode_go.zsh,
#    or the claude-code-router / agentgateway / LiteLLM projects.
cckick_p=(
  description "OpenRouter (planner/coder: Fable plans, Haiku codes)"
  base_url    "https://openrouter.ai/api"
  auth        AUTH_TOKEN
  auth_var    OPENROUTER_API_KEY
  model       "anthropic/claude-fable-5"        # main loop = planner / judge
  extra_env   "CLAUDE_CODE_SUBAGENT_MODEL=anthropic/claude-haiku-latest ANTHROPIC_API_KEY="
  # Cheaper planner alternative: model "anthropic/claude-opus-4-8"
)
