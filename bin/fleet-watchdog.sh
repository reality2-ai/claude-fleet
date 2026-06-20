#!/usr/bin/env bash
# fleet-watchdog — keeps idle worker sessions moving so the human (and the supervisor)
# don't have to cycle between them. Nudges a child only on its TRANSITION to idle
# (idle this cycle but not last), so a genuinely-done/holding child is nudged once and
# then left alone — it won't be re-spun until it becomes active again.
#
# Run detached:  nohup claude-fleet/bin/fleet-watchdog.sh >/tmp/fleet-watchdog.log 2>&1 &
# Stop:          pkill -f fleet-watchdog.sh
# Tune:          FLEET_WATCHDOG_INTERVAL=240 (seconds)  FLEET_WATCHDOG_SKIP="supervisor R2 website"
set -uo pipefail
FLEET="$(cd "$(dirname "$0")" && pwd)/fleet"
INTERVAL="${FLEET_WATCHDOG_INTERVAL:-240}"
SKIP="${FLEET_WATCHDOG_SKIP:-supervisor R2}"
prev=""
while true; do
  sleep "$INTERVAL"
  now="$("$FLEET" status 2>/dev/null | awk 'NR>1 && $2=="idle"{print $1}' | tr '\n' ' ')"
  for c in $now; do
    case " $SKIP " in *" $c "*) continue ;; esac
    case " $prev " in *" $c "*) continue ;; esac   # already idle last cycle → leave it
    "$FLEET" send "$c" "Watchdog nudge — carry on autonomously through your queue; keep progressing and flag the supervisor ONLY on a real blocker or a directional (a/b/c) fork. If you have genuinely finished everything, briefly say so and idle (you won't be re-nudged unless you become active again). Working mode: honest conjecture/refutation, peer-refuted before 'done', fitness = the mission." >/dev/null 2>&1
  done
  prev="$now"
done
