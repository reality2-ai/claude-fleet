#!/usr/bin/env bash
# UserPromptSubmit hook — record the latest prompt as the child's current task.
source "$(dirname "$(readlink -f "$0")")/hook-common.sh"

PROMPT="$(hjq '.prompt')"
# collapse whitespace, keep it short
TASK="$(printf '%s' "$PROMPT" | tr '\n' ' ' | sed 's/  */ /g')"
TASK="${TASK:0:160}"

fleet_state_jq "$CHILD_ID" --arg t "$TASK" --argjson now "$NOW" \
  '.current_task = $t | .heartbeat = $now | .state = "running"' >/dev/null 2>&1 || true
exit 0
