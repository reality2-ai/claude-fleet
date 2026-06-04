# shellcheck shell=bash
# hook-common.sh — shared prelude for the self-reporting hooks. Each hook script
# sources this, then mutates state/<id>.json. Hooks must be fast and must never
# fail the session, so everything here is best-effort and exits 0 on trouble.

# resolve the tool checkout from this file's location (hooks/ -> TOOL_ROOT)
TOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TOOL_ROOT

command -v jq >/dev/null 2>&1 || exit 0

# minimal subset of common/registry (avoid pulling tmux/restart into hooks)
source "$TOOL_ROOT/lib/common.sh" 2>/dev/null || exit 0

# read the hook payload from stdin
HOOK_JSON="$(cat 2>/dev/null || true)"
hjq() { printf '%s' "$HOOK_JSON" | jq -r "$1 // empty" 2>/dev/null; }

SESSION_ID="$(hjq '.session_id')"
CWD="$(hjq '.cwd')"; [[ -z "$CWD" ]] && CWD="$PWD"

# locate the workspace (.fleet) by walking up from the session cwd; if none,
# this session isn't under a fleet workspace — do nothing.
FLEET_WORKSPACE=""
_d="$CWD"
while [[ "$_d" != "/" ]]; do
  [[ -d "$_d/.fleet" ]] && { FLEET_WORKSPACE="$_d"; break; }
  _d="$(dirname "$_d")"
done
[[ -z "$FLEET_WORKSPACE" ]] && exit 0
fleet_load_paths 0 || exit 0
source "$TOOL_ROOT/lib/registry.sh" 2>/dev/null || exit 0

# resolve this session's child id: managed sessions carry FLEET_CHILD_ID;
# ad-hoc sessions key off the cwd basename, disambiguated by session id only on
# a genuine collision with another *live* session.
hc_resolve_id() {
  if [[ -n "${FLEET_CHILD_ID:-}" ]]; then printf '%s\n' "$FLEET_CHILD_ID"; return; fi
  local base; base="$(basename "$CWD")"
  local f="$CHILDSTATE_DIR/$base.json"
  if [[ -f "$f" ]]; then
    local owner; owner="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"
    if [[ -n "$owner" && "$owner" != "$SESSION_ID" ]]; then
      # collision: only disambiguate if the other owner still looks alive
      local mt; mt="$(fleet_mtime "$(fleet_transcript_path "$(jq -r '.cwd' "$f")" "$owner")")"
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
NOW="$(date +%s)"
