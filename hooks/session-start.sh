#!/usr/bin/env bash
# SessionStart hook — register the session: id, cwd, pid, state=running.
# Also records the session id under run/<id>.session so 'fleet up' can resume it.
# shellcheck source-path=SCRIPTDIR source=hook-common.sh
source "$(cd "$(dirname "$0")" && pwd)/hook-common.sh"

fleet_state_jq "$CHILD_ID" \
  --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg p "$PROVIDER" --argjson now "$NOW" --argjson pid "$PPID" '
    .session_id = $sid | .cwd = $cwd | .pid = $pid
  | .provider = $p
  | .state = "running" | .started_at = (.started_at // $now) | .heartbeat = $now
  | .reason = null' >/dev/null 2>&1 || true

if [[ -n "$SESSION_ID" ]]; then
  mkdir -p "$RUN_DIR" 2>/dev/null || true
  printf '%s\n' "$SESSION_ID" >"$RUN_DIR/$CHILD_ID.session" 2>/dev/null || true
fi
fleet_log session-start "$CHILD_ID" "session=${SESSION_ID:0:8} pid=$PPID" 2>/dev/null || true
exit 0
