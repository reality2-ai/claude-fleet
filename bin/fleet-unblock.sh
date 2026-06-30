#!/usr/bin/env bash
# fleet-unblock — periodic janitor: press Enter on every fleet window so any message left
# sitting unsubmitted in an input box gets submitted.
#
# WHY BLIND (not content-gated): an empty-box Enter is a verified NO-OP in Claude Code — it
# starts no turn and costs no tokens — so a blind Enter is free when the box is empty and
# submits whatever is stuck when it isn't. Blind is deliberately chosen over screen-parsing
# because it is:
#   • PROVIDER-NEUTRAL — works on Codex panes too (they don't render the ❯ box a Claude-
#     specific detector keys on, so a gated janitor would silently skip them);
#   • ROBUST — no fragile capture/regex/SGR parsing to get wrong across Claude Code versions
#     (that parsing is the whole class of bug this janitor exists to backstop).
# It makes NO API calls, so it survives an account-wide rate-limit (can unstick the supervisor
# itself). The human's own session is not a window in the fleet tmux session, so it is never
# touched; add any window to FLEET_UNBLOCK_SKIP to exclude it.
#
# Run as a fleet-server session:
#   tmux -L fleet new-session -d -s r2-unblock "<path>/fleet-unblock.sh >/tmp/fleet-unblock.log 2>&1"
# Stop:  pkill -f '[f]leet-unblock.sh'
# Tune:  FLEET_UNBLOCK_INTERVAL=120  FLEET_UNBLOCK_SKIP="win1 win2"  FLEET_TMUX_SOCKET/SESSION
set -uo pipefail
SOCK="${FLEET_TMUX_SOCKET:-fleet}"
SESSION="${FLEET_TMUX_SESSION:-fleet}"
INTERVAL="${FLEET_UNBLOCK_INTERVAL:-120}"
SKIP=" ${FLEET_UNBLOCK_SKIP:-} "

echo "fleet-unblock: socket=$SOCK session=$SESSION interval=${INTERVAL}s skip='${SKIP}' (blind Enter; empty=no-op; no API calls)"
while true; do
  sleep "$INTERVAL"
  tmux -L "$SOCK" has-session -t "$SESSION" 2>/dev/null || continue
  while IFS= read -r w; do
    [[ -n "$w" ]] || continue
    case "$SKIP" in *" $w "*) continue ;; esac
    tmux -L "$SOCK" send-keys -t "$SESSION:$w" Enter 2>/dev/null
  done < <(tmux -L "$SOCK" list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null)
done
