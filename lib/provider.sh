# shellcheck shell=bash
# provider.sh — CLI/provider differences for Claude Code and OpenAI Codex.

fleet_default_provider() { printf '%s\n' "${FLEET_AGENT_PROVIDER:-${SUP_PROVIDER:-claude}}"; }

fleet_provider_for_child() {
  local id="$1" p
  p="$(fleet_child_get "$id" provider "")"
  printf '%s\n' "${p:-$(fleet_default_provider)}"
}

fleet_provider_bin() {
  case "$1" in
    claude) printf '%s\n' "${FLEET_CLAUDE_BIN:-claude}" ;;
    codex)  printf '%s\n' "${FLEET_CODEX_BIN:-codex}" ;;
    *)      die "unknown agent provider '$1' (expected claude or codex)" ;;
  esac
}

fleet_is_supervisor_id() {
  [[ "$1" == "supervisor" || "$1" == supervisor-* ]]
}

fleet_prompt_join() {
  local primer="$1" prompt="$2"
  if [[ -n "$primer" && -n "$prompt" ]]; then
    printf '%s\n\n%s\n' "$primer" "$prompt"
  elif [[ -n "$primer" ]]; then
    printf '%s\n' "$primer"
  else
    printf '%s\n' "$prompt"
  fi
}

_toml_string() {
  jq -Rn --arg s "$1" '$s'
}

_codex_hook_group() {
  local event="$1" matcher="$2" command="$3" smsg="${4:-}"
  local cmd status
  cmd="$(_toml_string "$command")"
  if [[ -n "$smsg" ]]; then status=",statusMessage=$(_toml_string "$smsg")"; else status=""; fi
  if [[ -n "$matcher" ]]; then
    printf 'hooks.%s=[{matcher=%s,hooks=[{type="command",command=%s%s}]}]' \
      "$event" "$(_toml_string "$matcher")" "$cmd" "$status"
  else
    printf 'hooks.%s=[{hooks=[{type="command",command=%s%s}]}]' \
      "$event" "$cmd" "$status"
  fi
}

# Append Codex hook overrides to the named argv array. This is used for managed
# fleet-launched sessions so self-reporting works even when the child cwd is a
# separate repo that would not inherit the workspace .codex/ layer.
fleet_codex_add_managed_hooks() {
  local arr_name="$1" h="$TOOL_ROOT/hooks" kv
  local -n argv="$arr_name"
  [[ "${FLEET_CODEX_MANAGED_HOOKS:-on}" == "off" ]] && return 0
  [[ "${FLEET_CODEX_BYPASS_HOOK_TRUST:-on}" == "off" ]] || argv+=(--dangerously-bypass-hook-trust)

  kv="$(_codex_hook_group SessionStart "startup|resume" "$h/session-start.sh" "fleet: session start")"
  argv+=(-c "$kv")
  kv="$(_codex_hook_group UserPromptSubmit "" "$h/prompt-submit.sh" "fleet: task")"
  argv+=(-c "$kv")
  kv="$(_codex_hook_group PermissionRequest "Bash|apply_patch|Edit|Write|MultiEdit|NotebookEdit" "FLEET_HOOK_EVENT=PermissionRequest $h/auto-approve.sh" "fleet: permission")"
  argv+=(-c "$kv")
  kv="$(_codex_hook_group PostToolUse "Bash|apply_patch|Edit|Write|MultiEdit|NotebookEdit" "$h/post-edit.sh" "fleet: claims")"
  argv+=(-c "$kv")
  kv="$(_codex_hook_group Stop "" "$h/on-stop.sh" "fleet: ready")"
  argv+=(-c "$kv")
}

fleet_codex_add_common_flags() {
  local arr_name="$1" id="$2" pm="$3" model profile sandbox approval extra
  local -n argv="$arr_name"

  model="$(fleet_child_get "$id" model "${FLEET_CODEX_MODEL:-}")"
  profile="$(fleet_child_get "$id" profile "${FLEET_CODEX_PROFILE:-}")"
  sandbox="$(fleet_child_get "$id" sandbox "${FLEET_CODEX_SANDBOX:-}")"
  approval="$(fleet_child_get "$id" approval_policy "${FLEET_CODEX_APPROVAL:-}")"

  [[ -n "$model" ]] && argv+=(--model "$model")
  [[ -n "$profile" ]] && argv+=(--profile "$profile")

  # Match the Claude managed-worker default: non-supervisor workers run
  # unattended unless FLEET_SKIP_PERMISSIONS=off. The supervisor remains
  # prompt-gated, and callers such as `fleet refute` can force plan/read-only by
  # temporarily setting FLEET_SKIP_PERMISSIONS=off.
  if [[ "${FLEET_SKIP_PERMISSIONS:-on}" == "on" ]] && ! fleet_is_supervisor_id "$id"; then
    argv+=(--dangerously-bypass-approvals-and-sandbox)
    sandbox=""; approval=""
  else
    case "$pm" in
      bypassPermissions) argv+=(--dangerously-bypass-approvals-and-sandbox); sandbox=""; approval="" ;;
      acceptEdits)       sandbox="${sandbox:-workspace-write}"; approval="${approval:-on-request}" ;;
      plan)              sandbox="${sandbox:-read-only}"; approval="${approval:-untrusted}" ;;
    esac
  fi

  [[ -n "$sandbox" ]] && argv+=(--sandbox "$sandbox")
  [[ -n "$approval" ]] && argv+=(--ask-for-approval "$approval")

  extra="$(fleet_child_get "$id" codex_args "${FLEET_CODEX_ARGS:-}")"
  if [[ -n "$extra" ]]; then
    # shellcheck disable=SC2206 # deliberate simple whitespace split for opt-in flags
    local -a words=( $extra )
    argv+=("${words[@]}")
  fi
}

# Build argv for an interactive worker/supervisor/dispatch session.
# fleet_agent_build_args <array-name> <provider> <id> <name> <cwd> <primer> <prompt> <sid> <permission_mode>
fleet_agent_build_args() {
  local arr_name="$1" provider="$2" id="$3" name="$4" cwd="$5" primer="$6" prompt="$7" sid="$8" pm="$9"
  local bin; bin="$(fleet_provider_bin "$provider")"
  local -n argv="$arr_name"
  argv=()

  case "$provider" in
    claude)
      argv+=("$bin" --name "$name")
      [[ -n "${MANAGED_SETTINGS:-}" ]] && argv+=(--settings "$MANAGED_SETTINGS")
      [[ -n "$primer" ]] && argv+=(--append-system-prompt "$primer")
      # Autonomous WORKERS must never block on an interactive permission prompt. The
      # overnight stalls were workers hung at prompts for hardware commands (ssh tuxedo-os
      # '…espflash…serial…') the auto-approve hook didn't cover — no human to press "Yes".
      # Skip-permissions for workers (GitHub-failsafe doctrine: don't gate, checkpoint instead;
      # safety = pre-push secret-scan + auto-checkpoint hook + sandboxed worktrees). The
      # SUPERVISOR lanes keep prompt-gating (Roy oversees them). Toggle: FLEET_SKIP_PERMISSIONS=off
      if [[ "${FLEET_SKIP_PERMISSIONS:-on}" == "on" ]] && ! fleet_is_supervisor_id "$id"; then
        argv+=(--dangerously-skip-permissions)
      elif [[ -n "$pm" ]]; then
        argv+=(--permission-mode "$pm")
      fi
      if [[ -n "$sid" ]]; then argv+=(--resume "$sid"); fi
      [[ -n "$prompt" ]] && argv+=("$prompt")
      ;;
    codex)
      argv+=("$bin" --cd "$cwd")
      fleet_codex_add_managed_hooks "$arr_name"
      fleet_codex_add_common_flags "$arr_name" "$id" "$pm"
      local combined; combined="$(fleet_prompt_join "$primer" "$prompt")"
      if [[ -n "$sid" ]]; then
        argv+=(resume "$sid")
      fi
      [[ -n "$combined" ]] && argv+=("$combined")
      ;;
    *) die "unknown agent provider '$provider' (expected claude or codex)" ;;
  esac
  return 0
}

# One-shot forked answer for `fleet ask`. The fork carries the target's context
# but MUST NOT be able to mutate ANY checkout — its own throw-away worktree or,
# worse, the writer's live checkout that a resumed session may restore as cwd.
#
# Isolation is enforced STRUCTURALLY (real CLI capability flags), never by prompt
# text, on BOTH providers:
#   • the caller passes an isolated <cwd> (a detached worktree at HEAD or a bare
#     temp dir) which we bind explicitly — codex via --cd, claude via a cd'd
#     subshell — so file reads resolve inside the isolate, never the live tree;
#   • claude runs with NO mutation surface: a read-only tool allowlist plus a
#     hard deny of every edit/exec tool, so even if a resumed session restores the
#     original cwd it has no Edit/Write/Bash to write with;
#   • codex runs --sandbox read-only --ask-for-approval never, so model-generated
#     shell commands cannot escape to write and nothing blocks on an approval.
#
# fleet_agent_headless_answer <provider> <sid> <primer> <prompt> [cwd]
fleet_agent_headless_answer() {
  local provider="$1" sid="$2" primer="$3" prompt="$4" cwd="${5:-}"
  local bin; bin="$(fleet_provider_bin "$provider")"
  case "$provider" in
    claude)
      # Read-only posture: allow ONLY read tools (deny-by-default), and additionally
      # hard-deny the mutation/exec tools so no write surface can slip through.
      local -a ro=(
        --allowedTools Read Grep Glob
        --disallowedTools Edit Write MultiEdit NotebookEdit Bash
      )
      # Bind the isolated cwd in a subshell (claude has no --cd); if the resumed
      # session ignores it, the read-only tool posture above is the real guard.
      (
        [[ -n "$cwd" ]] && { cd "$cwd" || exit 3; }
        if [[ -n "$sid" ]]; then
          exec "$bin" -p --resume "$sid" --fork-session "${ro[@]}" --append-system-prompt "$primer" "$prompt"
        else
          exec "$bin" -p "${ro[@]}" --append-system-prompt "$primer" "$prompt"
        fi
      )
      ;;
    codex)
      local combined; combined="$(fleet_prompt_join "$primer" "$prompt")"
      # Global flags precede the subcommand: pin cwd, sandbox to read-only, never ask.
      local -a ro=(--sandbox read-only --ask-for-approval never)
      [[ -n "$cwd" ]] && ro=(--cd "$cwd" "${ro[@]}")
      if [[ -n "$sid" ]]; then
        "$bin" "${ro[@]}" exec resume "$sid" "$combined"
      else
        "$bin" "${ro[@]}" exec "$combined"
      fi
      ;;
    *) die "unknown agent provider '$provider' (expected claude or codex)" ;;
  esac
}
