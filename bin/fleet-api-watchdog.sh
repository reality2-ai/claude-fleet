#!/usr/bin/env bash
# fleet-api-watchdog — un-sticks fleet sessions frozen on an API rate-limit / transient
# API error by periodically sending "try again", so they carry on the instant the block lifts.
#
# WHY A PLAIN SHELL SCRIPT (the crux — Roy's "the hard one is if that hits you"):
# An account-wide API rate-limit freezes EVERY Claude session at once — the workers AND the
# supervisor. Nothing that itself calls the Claude API (a peer worker, a CronCreate task, the
# supervisor) can recover the supervisor, because it's blocked by the same limit. The ONLY thing
# that survives is a process that makes NO API calls. This loop is exactly that — so it can
# un-stick the supervisor itself. It therefore does NOT skip the supervisor (unlike the idle nudger).
#
# HOW: every tick, capture each pane's tail. Nudge a pane iff (a) it shows a rate-limit/API-error
# signature, AND (b) the tail is UNCHANGED since last tick — i.e. it's genuinely STUCK, not mid a
# live auto-retry (Claude's own backoff changes the pane; a "retrying…" countdown is left alone).
# After a nudge the pane changes, so it won't be re-nudged until it's stuck again.
#
# Run detached:  nohup claude-fleet/bin/fleet-api-watchdog.sh >/tmp/fleet-api-watchdog.log 2>&1 &
# Stop:          pkill -f fleet-api-watchdog.sh
# Tune: FLEET_API_WATCHDOG_INTERVAL=75  FLEET_TMUX_SESSION=fleet  FLEET_API_NUDGE="try again"
set -uo pipefail
SESSION="${FLEET_TMUX_SESSION:-fleet}"
INTERVAL="${FLEET_API_WATCHDOG_INTERVAL:-75}"
NUDGE="${FLEET_API_NUDGE:-try again}"
# Rate-limit / transient-API-error signatures Claude Code surfaces in the pane.
SIG='temporarily (limiting|unavailable)|rate.?limit|Overloaded|overloaded_error|API [Ee]rror|error 529|529 |Internal server error|exceeded your|usage limit|temporarily limiting requests'
# Active-auto-retry markers — leave these alone (Claude is recovering itself).
RETRYING='[Rr]etrying|retry in|auto-?retry|backoff'

declare -A last nudged
echo "fleet-api-watchdog: session=$SESSION interval=${INTERVAL}s nudge='$NUDGE' (covers supervisor)"
while true; do
  sleep "$INTERVAL"
  tmux has-session -t "$SESSION" 2>/dev/null || continue
  while IFS= read -r w; do
    [[ -n "$w" ]] || continue
    tail="$(tmux capture-pane -p -t "$SESSION:$w" 2>/dev/null | grep -vE '^[[:space:]]*$' | tail -n 6)"
    if printf '%s' "$tail" | grep -qiE "$SIG" && ! printf '%s' "$tail" | grep -qiE "$RETRYING"; then
      if [[ "$tail" == "${last[$w]:-}" ]]; then          # stuck (unchanged) on an API error
        n=$(( ${nudged[$w]:-0} + 1 )); nudged[$w]=$n
        tmux send-keys -t "$SESSION:$w" -l "$NUDGE" 2>/dev/null
        sleep 0.4; tmux send-keys -t "$SESSION:$w" Enter 2>/dev/null
        sleep 0.3; tmux send-keys -t "$SESSION:$w" Enter 2>/dev/null   # 2nd Enter: harmless no-op if 1st landed
        printf '%s api-stuck %-12s -> nudged x%d\n' "$(date '+%F %T')" "$w" "$n"
      fi
    else
      nudged[$w]=0
    fi
    last[$w]="$tail"
  done < <(tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null)
done
