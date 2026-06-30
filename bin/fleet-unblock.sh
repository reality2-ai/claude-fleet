#!/usr/bin/env bash
# fleet-unblock — periodic janitor that submits any fleet message left sitting UNSUBMITTED
# in a worker's input box.
#
# WHY: inter-agent delivery types/pastes a message into a live TUI and presses Enter. That
# Enter can occasionally race a turn boundary (the worker starts its own turn in the same
# instant), leaving a COMPLETE message in the box that never submitted — it then waits for a
# human Enter. The Stop-hook flush (fleet_flush_stuck_box) catches these at the next turn end,
# but a worker that goes idle and STAYS idle with a stuck box has no turn-end to trigger it.
# This loop is that backstop: every interval, press Enter on any worker whose box actually
# holds content. It makes NO API calls (survives an account-wide rate-limit) and is
# provider-neutral (Enter works on any TUI).
#
# SAFETY: it only ever presses Enter when the box genuinely holds real (non-dim) content — it
# never fires a blind Enter at an empty prompt or a menu, so it can't poke an idle worker into
# a spurious empty turn (which would waste tokens) or pick a default off a dialog. The human's
# own session is not a window in the fleet tmux session, so it is never touched. A window whose
# prompt does not render the ❯ box (e.g. a Codex pane) simply never matches and is left alone.
#
# Run detached:  nohup claude-fleet/bin/fleet-unblock.sh >/tmp/fleet-unblock.log 2>&1 &
# Or as a fleet-server session:
#   tmux -L fleet new-session -d -s r2-unblock "exec <path>/fleet-unblock.sh"
# Stop: pkill -f fleet-unblock.sh
# Tune: FLEET_UNBLOCK_INTERVAL=1200  FLEET_UNBLOCK_SKIP="<window names>"  FLEET_TMUX_SESSION=fleet
set -uo pipefail
TOOL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FLEET_TMUX_SOCKET="${FLEET_TMUX_SOCKET:-fleet}"
# canonical, corrected detector (full-capture ❯ grep — robust to long wrapped messages)
# shellcheck source=../lib/registry.sh
source "$TOOL_ROOT/lib/registry.sh" 2>/dev/null || true
# shellcheck source=../lib/tmux.sh
source "$TOOL_ROOT/lib/tmux.sh"      2>/dev/null || true
# shellcheck source=../lib/comms.sh
source "$TOOL_ROOT/lib/comms.sh"     2>/dev/null || true

SESSION="${FLEET_TMUX_SESSION:-fleet}"
INTERVAL="${FLEET_UNBLOCK_INTERVAL:-1200}"     # ~20 min
SKIP=" ${FLEET_UNBLOCK_SKIP:-} "               # extra window names to never auto-Enter

# Read the LAST ❯ input line from the FULL capture (not a fixed tail — a long wrapped message
# pushes the ❯ above any small tail window), then test it for real, non-dim content.
_box_has_content() {
  local w="$1" line
  line="$(tmux -L "$FLEET_TMUX_SOCKET" capture-pane -e -p -t "$SESSION:$w" 2>/dev/null | grep -aF '❯' | tail -1)"
  [[ -n "$line" ]] || return 1
  if declare -F _fleet_line_has_real_input >/dev/null 2>&1; then
    _fleet_line_has_real_input "$line"
  else
    # fallback: strip SGR + ❯ + NBSP + ws; anything left is content
    line="$(printf '%s' "$line" | sed -E 's/\x1b\[[0-9;]*m//g')"
    line="${line#❯}"; line="${line//$' '/}"; line="${line//[[:space:]]/}"
    [[ -n "$line" ]]
  fi
}

echo "fleet-unblock: session=$SESSION interval=${INTERVAL}s skip='${SKIP}' (content-gated Enter; no API calls)"
while true; do
  sleep "$INTERVAL"
  tmux -L "$FLEET_TMUX_SOCKET" has-session -t "$SESSION" 2>/dev/null || continue
  while IFS= read -r w; do
    [[ -n "$w" ]] || continue
    case "$SKIP" in *" $w "*) continue ;; esac
    if _box_has_content "$w"; then
      tmux -L "$FLEET_TMUX_SOCKET" send-keys -t "$SESSION:$w" Enter 2>/dev/null
      printf '%s unblock %-14s -> box held content; pressed Enter\n' "$(date '+%F %T')" "$w"
    fi
  done < <(tmux -L "$FLEET_TMUX_SOCKET" list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null)
done
