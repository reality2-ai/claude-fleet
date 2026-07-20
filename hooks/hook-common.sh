# shellcheck shell=bash
# hook-common.sh — shared prelude for the self-reporting hooks. Each hook script
# sources this, then mutates state/<id>.json. Hooks must be fast and must never
# fail the session, so everything here is best-effort and exits 0 on trouble.

# resolve `# shellcheck source=` paths relative to this file's dir, not the CWD
# shellcheck source-path=SCRIPTDIR
# resolve the tool checkout from this file's location (hooks/ -> TOOL_ROOT)
TOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TOOL_ROOT

command -v jq >/dev/null 2>&1 || exit 0

# An ephemeral fleet process (e.g. the `fleet ask` forked responder) sets this so
# its short-lived session never self-reports into the registry.
[[ -n "${FLEET_NO_REPORT:-}" ]] && exit 0

# minimal subset of common/registry (avoid pulling tmux/restart into hooks)
# shellcheck source=../lib/common.sh
source "$TOOL_ROOT/lib/common.sh" 2>/dev/null || exit 0

# read the hook payload from stdin
HOOK_JSON="$(cat 2>/dev/null || true)"
hjq() { printf '%s' "$HOOK_JSON" | jq -r "$1 // empty" 2>/dev/null; }

SESSION_ID="$(hjq '.session_id // .thread_id // .session.id // .thread.id')"
CWD="$(hjq '.cwd // .working_directory // .workspace_root')"; [[ -z "$CWD" ]] && CWD="$PWD"
PROVIDER="${FLEET_AGENT_PROVIDER:-}"
if [[ -z "$PROVIDER" ]]; then
  if [[ -n "${CODEX_HOME:-}" || "$HOOK_JSON" == *'"thread_id"'* ]]; then PROVIDER="codex"; else PROVIDER="claude"; fi
fi

# Use the CLI's manifest-aware discovery. This skips stale nested `.fleet/`
# runtime directories and selects the same parent workspace as every command.
FLEET_WORKSPACE="$(cd "$CWD" 2>/dev/null && unset FLEET_WORKSPACE && fleet_find_workspace)"
[[ -z "$FLEET_WORKSPACE" ]] && exit 0
export FLEET_WORKSPACE
fleet_load_paths 0 || exit 0
# shellcheck source=../lib/registry.sh
source "$TOOL_ROOT/lib/registry.sh" 2>/dev/null || exit 0

# resolve this session's child id: managed sessions carry FLEET_CHILD_ID;
# ad-hoc sessions key off the cwd basename, disambiguated by session id only on
# a genuine collision with another *live* session.
hc_resolve_id() {
  if [[ -n "${FLEET_CHILD_ID:-}" ]]; then printf '%s\n' "$FLEET_CHILD_ID"; return; fi
  local base; base="$(basename "$CWD")"
  # a cwd basename is not guaranteed to be a plain member id (e.g. '..'); no valid
  # path -> no id -> the caller exits 0 rather than keying state off a junk name.
  local f; f="$(fleet_state_path "$base")" || return 1
  if [[ -f "$f" ]]; then
    local owner; owner="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"
    if [[ -n "$owner" && "$owner" != "$SESSION_ID" ]]; then
      # collision: only disambiguate if the other owner still looks alive
      local state_provider; state_provider="$(jq -r '.provider // "claude"' "$f" 2>/dev/null)"
      local mt; mt="$(fleet_mtime "$(fleet_transcript_path "$(jq -r '.cwd' "$f")" "$owner" "$state_provider")")"
      local now; now="$(date +%s)"
      (( mt > 0 && now - mt < ${FLEET_DEAD_SECS:-1800} )) && base="$base-${SESSION_ID:0:4}"
    fi
  fi
  printf '%s\n' "$base"
}

CHILD_ID="$(hc_resolve_id)"
[[ -z "$CHILD_ID" ]] && exit 0
MANAGED=false; [[ -n "${FLEET_CHILD_ID:-}" ]] && MANAGED=true
fleet_state_ensure "$CHILD_ID" "$CWD" "$MANAGED" 2>/dev/null || exit 0
fleet_state_jq "$CHILD_ID" --arg p "$PROVIDER" '.provider=$p' >/dev/null 2>&1 || true
# shellcheck disable=SC2034  # consumed by the hook scripts that source this prelude
NOW="$(date +%s)"
