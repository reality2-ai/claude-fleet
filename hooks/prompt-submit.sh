#!/usr/bin/env bash
# UserPromptSubmit hook — record the latest prompt as the child's current task.
# shellcheck source-path=SCRIPTDIR source=hook-common.sh
source "$(cd "$(dirname "$0")" && pwd)/hook-common.sh"

PROMPT="$(hjq '.prompt // .user_prompt // .input // .message // .text')"
# collapse whitespace, keep it short
TASK="$(printf '%s' "$PROMPT" | tr '\n' ' ' | sed 's/  */ /g')"
TASK="${TASK:0:160}"

fleet_state_jq "$CHILD_ID" --arg t "$TASK" --argjson now "$NOW" \
  '.current_task = $t | .heartbeat = $now | .state = "running" | .ready = false' >/dev/null 2>&1 || true
exit 0

# COMMS reminder — per-turn, deliberately TINY. A fat reminder is self-defeating:
# it is input context on EVERY turn, the exact cost this standard exists to cut.
# Full schema lives in the injected system prompt (skill/COMMS.md); this only
# keeps it from decaying after compaction. Toggle: FLEET_COMMS_STANDARD=off
if [[ "${FLEET_COMMS_STANDARD:-on}" != "off" ]]; then
  printf 'COMMS: agent→agent DENSE wire format (>to !find @file:line =MUST ?open #verdict ^precond). RFC2119 UPPERCASE=binding. →Roy=prose. Evidence verbatim.\n'
fi
