#!/usr/bin/env bash
# fleet-unblock — periodic janitor that submits a STUCK FLEET MESSAGE left unsubmitted in a
# worker's input box (an inject whose Enter raced a turn boundary and never landed).
#
# SAFETY (the load-bearing rule): it presses Enter on a window ONLY when that window's box holds
# a recognisable fleet inject — content beginning with "[fleet msg from …]" / "[fleet ask from
# …]", a tag we control. It NEVER fires a blind Enter, because the fleet tmux session is often
# ATTACHED with a human typing into a worker window (e.g. the supervisor); a blind Enter would
# submit the human's half-typed message (Roy hit exactly this). The tag never matches human
# typing, and is provider-neutral (same tag on Codex panes). Makes NO API calls, so it survives
# an account-wide rate-limit. The human's own session is not a fleet window regardless.
#
# Run as a fleet-server session:
#   tmux -L fleet new-session -d -s r2-unblock "<path>/fleet-unblock.sh >/tmp/fleet-unblock.log 2>&1"
# Stop:  tmux -L fleet kill-session -t r2-unblock
# Tune:  FLEET_UNBLOCK_INTERVAL=120  FLEET_UNBLOCK_SKIP="win1 win2"  FLEET_TMUX_SOCKET/SESSION
set -uo pipefail
TOOL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FLEET_TMUX_SOCKET="${FLEET_TMUX_SOCKET:-fleet}"
export FLEET_TMUX_SESSION="${FLEET_TMUX_SESSION:-fleet}"
# shellcheck source=../lib/registry.sh
source "$TOOL_ROOT/lib/registry.sh" 2>/dev/null || true
# shellcheck source=../lib/tmux.sh
source "$TOOL_ROOT/lib/tmux.sh"      2>/dev/null || true
# shellcheck source=../lib/comms.sh
source "$TOOL_ROOT/lib/comms.sh"     2>/dev/null || true

SESSION="${FLEET_TMUX_SESSION:-fleet}"
INTERVAL="${FLEET_UNBLOCK_INTERVAL:-120}"
SKIP=" ${FLEET_UNBLOCK_SKIP:-} "

echo "fleet-unblock: socket=$FLEET_TMUX_SOCKET session=$SESSION interval=${INTERVAL}s skip='${SKIP}' (tag-gated: only submits stuck fleet injects, never human text; no API calls)"
while true; do
  sleep "$INTERVAL"
  tmux -L "$FLEET_TMUX_SOCKET" has-session -t "$SESSION" 2>/dev/null || continue
  while IFS= read -r w; do
    [[ -n "$w" ]] || continue
    case "$SKIP" in *" $w "*) continue ;; esac
    if declare -F fleet_box_has_stuck_inject >/dev/null 2>&1 && fleet_box_has_stuck_inject "$w"; then
      tmux -L "$FLEET_TMUX_SOCKET" send-keys -t "$SESSION:$w" Enter 2>/dev/null
      printf '%s unblock %-14s -> stuck fleet inject; pressed Enter\n' "$(date '+%F %T')" "$w"
    fi
  done < <(tmux -L "$FLEET_TMUX_SOCKET" list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null)
done
