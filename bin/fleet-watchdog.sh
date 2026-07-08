#!/usr/bin/env bash
# fleet-watchdog — keeps idle worker sessions moving so the human (and the supervisor)
# don't have to cycle between them. Nudges a child only on its TRANSITION to idle
# (idle this cycle but not last), so a genuinely-done/holding child is nudged once and
# then left alone — it won't be re-spun until it becomes active again.
#
# TOKEN POSTURE: the idle-nudge is OPT-IN (FLEET_IDLE_NUDGE=on). Default OFF = pull-based
# supervisor — idle workers are left alone (no "carry on" traffic + no reply cost); they
# resume only on a real message. Flip on when you want autonomous queue-draining cadence
# and are not token-constrained. The doctor oversight check runs regardless (cheap,
# edge-triggered) unless FLEET_WATCHDOG_DOCTOR=off.
#
# Run detached:  nohup claude-fleet/bin/fleet-watchdog.sh >/tmp/fleet-watchdog.log 2>&1 &
# Stop:          pkill -f fleet-watchdog.sh
# Tune:          FLEET_WATCHDOG_INTERVAL=240 (seconds)  FLEET_WATCHDOG_SKIP="supervisor R2 website"
#                FLEET_IDLE_NUDGE=on|off (default off)
set -uo pipefail
FLEET="$(cd "$(dirname "$0")" && pwd)/fleet"
INTERVAL="${FLEET_WATCHDOG_INTERVAL:-240}"
SKIP="${FLEET_WATCHDOG_SKIP:-supervisor R2}"
# Self-check the oversight wire each cycle and escalate a one-line digest to the
# supervisor — but edge-triggered (only when the digest CHANGES), like the idle
# nudge's prev-suppression, so a persistent fault isn't re-reported every tick.
# Disable with FLEET_WATCHDOG_DOCTOR=off.
prev=""
prev_doctor=""
while true; do
  sleep "$INTERVAL"

  if [[ "${FLEET_WATCHDOG_DOCTOR:-on}" != "off" ]]; then
    doctor_out="$("$FLEET" doctor --quiet 2>/dev/null)"; doctor_rc=$?
    if [[ "$doctor_rc" -ne 0 ]]; then
      if [[ "$doctor_out" != "$prev_doctor" ]]; then    # edge-triggered: only on change
        "$FLEET" send supervisor "[doctor] oversight-wire check failed: ${doctor_out}" >/dev/null 2>&1
      fi
      prev_doctor="$doctor_out"
    else
      prev_doctor=""   # recovered → re-arm so the next fault is reported
    fi
  fi

  now="$("$FLEET" status 2>/dev/null | awk 'NR>1 && $2=="idle"{print $1}' | tr '\n' ' ')"
  if [[ "${FLEET_IDLE_NUDGE:-off}" == "on" ]]; then
    for c in $now; do
      case " $SKIP " in *" $c "*) continue ;; esac
      case " $prev " in *" $c "*) continue ;; esac   # already idle last cycle → leave it
      "$FLEET" send "$c" "Watchdog nudge — carry on autonomously through your queue; keep progressing and flag the supervisor ONLY on a real blocker or a directional (a/b/c) fork. If you have genuinely finished everything, briefly say so and idle (you won't be re-nudged unless you become active again). Working mode: honest conjecture/refutation, peer-refuted before 'done', fitness = the mission." >/dev/null 2>&1
    done
  fi
  prev="$now"
done
