# shellcheck shell=zsh disable=SC1072,SC1073,SC1036,SC1058,SC1009
# cckick.zsh — kick Claude Code onto any endpoint.
# Pure shell · no proxy · exit restores default.
#
# Main logic, sourced by cckick.plugin.zsh.
# User config: ${CCKICK_CONFIG_DIR:-${XDG_CONFIG_HOME:-~/.config}/cckick}/providers/*.zsh

# zsh only
if [[ -z "$ZSH_VERSION" ]]; then
  print -u 2 "cckick: requires zsh (current shell is not zsh)"
  return 1 2>/dev/null || exit 1
fi

# Config dirs (user can override before sourcing)
: "${CCKICK_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/cckick}"
: "${CCKICK_PROVIDERS_DIR:=$CCKICK_CONFIG_DIR/providers}"

# fzf soft-dependency (arrow keys + fuzzy search if available, number menu otherwise)
(( $+commands[fzf] )) && _cckick_fzf=1 || _cckick_fzf=0

# ─── private ─────────────────────────────────────────────────────────

# List all provider names (scan providers/*.zsh, strip extension)
_cckick_list() {
  [[ -d "$CCKICK_PROVIDERS_DIR" ]] || return 0
  local f
  for f in "$CCKICK_PROVIDERS_DIR"/*.zsh(N); do
    print -- "${f:t:r}"
  done
}

# Get a provider's description (source in a subshell, don't pollute current shell)
# ⚠ This executes the provider file's top-level code — so provider files must only
#    declare cckick_p + hooks at the top level (see README safety notes).
_cckick_description() {
  local name="$1"
  local f="$CCKICK_PROVIDERS_DIR/$name.zsh"
  [[ -f "$f" ]] || { print "(unknown)"; return 1; }
  (
    emulate -L zsh
    typeset -A cckick_p=()
    source "$f" 2>/dev/null
    print -r -- "${cckick_p[description]:-(no description)}"
  )
}

# Launch a provider (subshell: source → symmetric clean slate → trap → _start → export → claude)
# Trap is installed BEFORE _start, so any failure path (source / clean-slate / _start / key)
# triggers EXIT → _stop cleanup. Subshell exit leaves the parent shell untouched → default endpoint.
_cckick_launch() {
  local name="$1"

  # Validate provider name (prevent ../ path traversal + odd chars — name goes into the source path)
  if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "$name" == *..* ]]; then
    print -u 2 "cckick: invalid provider name '$name' (allowed: letters/digits/._- only)"
    return 1
  fi
  local f="$CCKICK_PROVIDERS_DIR/$name.zsh"
  [[ -f "$f" ]] || { print -u 2 "cckick: provider '$name' not found (looked for: $f)"; return 1; }

  # Resolve claude's absolute path BEFORE sourcing: a provider could export PATH or define a
  # claude() function to hijack. Resolving ${commands[claude]} early + calling the absolute path
  # bypasses PATH and same-named functions.
  local claude_bin="${commands[claude]:-}"
  [[ -n "$claude_bin" ]] || { print -u 2 "cckick: claude not found in PATH"; return 1; }

  # Reset hook-shared state (prevent a stale CCKICK_PROXY_PID from a previous run being read by _stop)
  unset CCKICK_PROXY_PID 2>/dev/null

  (
    emulate -L zsh
    typeset -A cckick_p=()
    source "$f" 2>/dev/null

    # Validate required fields (don't rely on source's return code — a trailing non-zero
    # statement in the provider file would make source return non-zero)
    if [[ -z "${cckick_p[description]}" || -z "${cckick_p[auth]}" ]]; then
      print -u 2 "cckick: provider '$name' is missing the description/auth fields"
      exit 1
    fi

    # Symmetric clean slate: drop everything inherited from the parent shell so only this
    # provider's values take effect. (Earlier versions only cleared API_KEY in AUTH_TOKEN mode —
    # but API_KEY mode didn't clear AUTH_TOKEN, so a stale inherited token would make claude
    # prefer the Bearer and silently use the wrong account.)
    unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL

    # Install trap BEFORE _start starts any subprocess — so a half-started _start (e.g. proxy
    # up but health check failing) still triggers EXIT → _stop and doesn't leak the process.
    # Signal traps only exit (with standard codes); cleanup is attached to EXIT only, so _stop
    # runs exactly once.
    local stop_fn="cckick_stop_$name"
    if (( $+functions[$stop_fn] )); then
      trap "$stop_fn" EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      trap 'exit 129' HUP
    fi

    # Pre-launch hook (health check etc.); failure → exit 1 → EXIT trap → _stop cleanup
    local start_fn="cckick_start_$name"
    if (( $+functions[$start_fn] )); then
      "$start_fn" || { print -u 2 "cckick: $name pre-launch hook failed (_start returned non-zero, proxy may not be ready)"; exit 1; }
    fi

    # Validate auth_var is set (else (P) expansion looks up an empty-named var → misleading error)
    local auth_var="${cckick_p[auth_var]}"
    if [[ -z "$auth_var" ]]; then
      print -u 2 "cckick: provider '$name' is missing the auth_var field (should name the env var holding the key)"
      exit 1
    fi
    local key_val="${(P)auth_var:-}"
    if [[ -z "$key_val" ]]; then
      print -u 2 "cckick: env var \$$auth_var is not set (provider=$name). Export it in ~/.zshrc and reopen the terminal."
      exit 1
    fi

    # Export auth + endpoint
    case "${cckick_p[auth]}" in
      API_KEY)    export ANTHROPIC_API_KEY="$key_val" ;;
      AUTH_TOKEN) export ANTHROPIC_AUTH_TOKEN="$key_val" ;;
      *) print -u 2 "cckick: auth must be API_KEY or AUTH_TOKEN (got: ${cckick_p[auth]:-empty})"; exit 1 ;;
    esac
    [[ -n "${cckick_p[base_url]}" ]] && export ANTHROPIC_BASE_URL="${cckick_p[base_url]}"
    [[ -n "${cckick_p[model]}" ]]    && export ANTHROPIC_MODEL="${cckick_p[model]}"

    # No print -P (it would eat % in description as prompt escapes); use ANSI literal + -r
    print -r -- $'\e[36m→ cckick:\e[0m \e[1m'"$name"$'\e[0m — '"${cckick_p[description]}"
    # extra_args: (z) shell-lex split + (Q) strip quotes (supports spaces inside one arg);
    # call the absolute claude_bin (prevents PATH hijack via provider)
    "$claude_bin" ${(Q)${(z)cckick_p[extra_args]:-}}
  )
}

# ─── public API ──────────────────────────────────────────────────────

cckick() {
  emulate -L zsh
  local cmd="${1:-}"

  case "$cmd" in
    "")
      # interactive select
      [[ -d "$CCKICK_PROVIDERS_DIR" ]] || { print -u 2 "cckick: no providers configured. Run cckick init or see README."; return 1; }
      local names_str=$(_cckick_list)
      local -a choices
      choices=()
      local n
      for n in "${(f)names_str}"; do
        [[ -z "$n" ]] && continue
        choices+=("$n|$(_cckick_description "$n")")
      done
      (( ${#choices[@]} == 0 )) && { print -u 2 "cckick: no *.zsh provider files under $CCKICK_PROVIDERS_DIR"; return 1; }

      local choice name
      if (( _cckick_fzf )); then
        choice=$(printf '%s\n' "${choices[@]}" \
          | fzf --prompt='cckick ❯ ' \
                --header='arrow keys to select · Enter to launch · Esc to cancel' \
                --delimiter='|' --with-nth=2 \
                --height=40% --reverse --tiebreak=index) || return
      else
        # Manual single-column menu: avoids zsh select's multi-column CJK width alignment bug
        local i=1 sel
        print -u 2 "cckick — pick a provider:"
        for c in "${choices[@]}"; do
          print -u 2 "  $i) ${c#*|}"
          ((i++))
        done
        while read 'sel?cckick ❯ # '; do
          if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#choices[@]} )); then
            choice="${choices[sel]}"
            break
          fi
          print -u 2 "  invalid, retry (1-${#choices[@]})"
        done
        [[ -n "$choice" ]] || return
      fi
      name="${choice%%|*}"
      _cckick_launch "$name"
      ;;
    list|--list|-l)
      local names_str=$(_cckick_list)
      local n
      for n in "${(f)names_str}"; do
        [[ -z "$n" ]] && continue
        print -r -- "$n	$(_cckick_description "$n")"
      done
      ;;
    init)
      mkdir -p "$CCKICK_PROVIDERS_DIR" \
        && print "cckick: created $CCKICK_PROVIDERS_DIR. Drop provider files there (see cckick.example.zsh / examples/)."
      ;;
    help|--help|-h)
      print -r -- $'\e[1mcckick\e[0m — kick Claude Code onto any endpoint.'
      print ""
      print "Usage:"
      print "  cckick              interactive select (fzf or number menu)"
      print "  cckick <name>       launch a specific provider"
      print "  cckick list         list configured providers"
      print "  cckick init         create the config dir $CCKICK_PROVIDERS_DIR"
      print "  cckick help         show this help"
      print ""
      print "Provider config: $CCKICK_PROVIDERS_DIR/*.zsh (see cckick.example.zsh / examples/)"
      ;;
    *)
      _cckick_launch "$cmd"
      ;;
  esac
}
