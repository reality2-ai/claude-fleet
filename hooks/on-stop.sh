#!/usr/bin/env bash
# Stop hook — fires when the agent finishes a turn (it's now at its prompt).
# Marks the child ready and drains any queued peer messages into it (the
# "deliver when it next returns to its prompt" half of hybrid delivery).
source "$(cd "$(dirname "$0")" && pwd)/hook-common.sh"
source "$TOOL_ROOT/lib/tmux.sh" 2>/dev/null || exit 0
source "$TOOL_ROOT/lib/comms.sh" 2>/dev/null || exit 0

fleet_state_jq "$CHILD_ID" --argjson now "$NOW" '.ready=true | .heartbeat=$now' >/dev/null 2>&1 || true
fleet_drain_inbox "$CHILD_ID" force >/dev/null 2>&1 || true
exit 0
