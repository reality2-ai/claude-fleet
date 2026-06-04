#!/usr/bin/env bash
# SessionEnd hook — mark the child stopped and record the reason. Does NOT clear
# session_id/run file, so 'fleet up' can still resume the conversation later.
source "$(dirname "$(readlink -f "$0")")/hook-common.sh"

REASON="$(hjq '.reason')"; [[ -z "$REASON" ]] && REASON="exit"
fleet_state_jq "$CHILD_ID" --arg r "$REASON" --argjson now "$NOW" \
  '.state = "stopped" | .reason = $r | .heartbeat = $now' >/dev/null 2>&1 || true
fleet_log session-end "$CHILD_ID" "reason=$REASON" 2>/dev/null || true
exit 0
