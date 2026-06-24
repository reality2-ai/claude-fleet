#!/usr/bin/env bash
# Stop hook — fires when the agent finishes a turn (it's now at its prompt).
# Marks the child ready and drains any queued peer messages into it (the
# "deliver when it next returns to its prompt" half of hybrid delivery).
# shellcheck source-path=SCRIPTDIR source=hook-common.sh
source "$(cd "$(dirname "$0")" && pwd)/hook-common.sh"
# shellcheck source=../lib/tmux.sh
source "$TOOL_ROOT/lib/tmux.sh" 2>/dev/null || exit 0
# shellcheck source=../lib/comms.sh
source "$TOOL_ROOT/lib/comms.sh" 2>/dev/null || exit 0

fleet_state_jq "$CHILD_ID" --argjson now "$NOW" '.ready=true | .heartbeat=$now' >/dev/null 2>&1 || true
# Optional ground-truth liveness journal (no-op unless FLEET_JOURNAL is set).
fleet_journal_append "$CHILD_ID" "stop turn" 2>/dev/null || true

# Count undelivered queued messages BEFORE draining — would this child keep working?
_pending=0
_inbox="$(fleet_inbox_file "$CHILD_ID" 2>/dev/null)"
[[ -n "$_inbox" && -f "$_inbox" ]] && _pending="$(jq -s '[.[]|select(.delivered==false)]|length' "$_inbox" 2>/dev/null || echo 0)"

fleet_drain_inbox "$CHILD_ID" force >/dev/null 2>&1 || true

# Event-driven idle signal (default ON): a MANAGED worker that returned to its prompt
# with NOTHING queued is about to sit idle — proactively tell the supervisor so it can
# give direction or pick up the completion, instead of the human discovering it idle.
# Fires only on genuine idle (empty inbox), never self-notifies, one note per idle.
#   FLEET_IDLE_NOTIFY=off  disables · FLEET_IDLE_NOTIFY_TO=<id>  routes to another coordinator
if [[ "${FLEET_IDLE_NOTIFY:-on}" != "off" && "$MANAGED" == true ]]; then
  _coord="${FLEET_IDLE_NOTIFY_TO:-supervisor}"
  if [[ "$CHILD_ID" != "$_coord" && "${_pending:-0}" -eq 0 ]]; then
    # BACKGROUND it (`&`) + disown: fleet_notify injects into the coordinator's tmux pane, which
    # BLOCKS while that pane is busy (e.g. the supervisor running a sweep). A blocking Stop hook
    # hangs the worker after its turn → `.ready` never goes true → subsequent sends queue forever
    # → fleet-wide stall. The notify must NEVER stall hook completion; fire-and-forget only.
    ( fleet_notify "$_coord" "$CHILD_ID" "[auto:idle] $CHILD_ID is at its prompt with nothing queued — awaiting direction, or my current task is complete (any substantive report was sent separately)." 1 >/dev/null 2>&1 || true ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
fi
exit 0
