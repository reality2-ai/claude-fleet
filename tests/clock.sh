#!/usr/bin/env bash
# clock.sh — tests for the agent-facing clock emitted by hooks/prompt-submit.sh.
#
# The claim under test is that an agent gains a sense of DURATION it cannot derive for
# itself: how long since its own last turn, how long on this task, how old the session
# is, and whether a deadline is close enough to matter.
#
# The controls that make the green ones mean something:
#   * a fresh child with no history must NOT invent a gap out of a zero epoch
#   * the same prompt twice must NOT reset the task clock (same task continuing)
#   * a distant deadline must stay SILENT, or "deadline shown" proves only that the
#     jq ran, not that the window works
#   * FLEET_CLOCK=off must suppress the line while still recording the task
#
# Hermetic: throwaway workspace, no fleet, no tmux. Requires: bash >= 4, jq.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/prompt-submit.sh"

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }

WS="$(mktemp -d)"; trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/.fleet/state" "$WS/.fleet/run" "$WS/.fleet/log" "$WS/.fleet/decisions"
NOW="$(date +%s)"

# Run the hook as a subprocess with a crafted payload — calls PRODUCTION, never
# reimplements the rule. A control that reimplements it tests its own copy.
run() {
  jq -nc --arg p "$1" --arg c "$WS" '{prompt:$p, cwd:$c, session_id:"s-clock-0001"}' \
    | FLEET_CHILD_ID=clockw "$HOOK" 2>/dev/null
}
ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
state() { jq -r "$1 // empty" "$WS/.fleet/state/clockw.json" 2>/dev/null; }

section "1. first turn — no history to report"
OUT1="$(run 'build the thing')"; C1="$(ctx "$OUT1")"
if [[ -n "$C1" ]]; then ok "a clock line is emitted"; else no "no clock line emitted"; fi
if grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' <<<"$C1"; then ok "carries an absolute wall time"; else no "no absolute wall time"; fi
# CONTROL: a zero heartbeat must not become a gap "since 1970".
if ! grep -q 'since your last turn' <<<"$C1"; then ok "control: no fabricated gap on the first turn"; else no "invented a gap from an empty heartbeat"; fi
if grep -q 'new task' <<<"$C1"; then ok "first prompt reads as a new task"; else no "first prompt not marked new"; fi
if [[ "$(state '.current_task')" == "build the thing" ]]; then ok "task still recorded (unchanged behaviour)"; else no "task recording regressed"; fi

section "2. elapsed durations"
# Backdate the stored epochs to synthesise history, then take one more turn.
jq --argjson hb "$((NOW - 11400))" --argjson ta "$((NOW - 19800))" --argjson st "$((NOW - 187200))" \
   '.heartbeat=$hb | .task_started_at=$ta | .started_at=$st' \
   "$WS/.fleet/state/clockw.json" > "$WS/s.tmp" && mv "$WS/s.tmp" "$WS/.fleet/state/clockw.json"
C2="$(ctx "$(run 'build the thing')")"
if grep -qE '3h [0-9]+m since your last turn' <<<"$C2"; then ok "gap since the last turn (3h10m)"; else no "gap wrong or missing: $C2"; fi
if grep -qE '5h [0-9]+m on this task' <<<"$C2"; then ok "elapsed on the current task (5h30m)"; else no "task elapsed wrong or missing"; fi
if grep -qE 'session 2d [0-9]+h' <<<"$C2"; then ok "session age (2d4h)"; else no "session age wrong or missing"; fi
# CONTROL: identical prompt = same task continuing, so its clock must NOT reset.
if ! grep -q 'new task' <<<"$C2"; then ok "control: repeating a prompt does not reset the task clock"; else no "same task was treated as new"; fi

section "3. a different prompt starts a new task clock"
C3="$(ctx "$(run 'now do something else entirely')")"
if grep -q 'new task' <<<"$C3"; then ok "a changed prompt starts a new task clock"; else no "changed prompt did not reset the task clock"; fi

section "4. deadlines — only when near enough to matter"
mkjson() { jq -nc --arg id "$1" --argjson de "$2" --arg d "$3" \
  '{id:$id, state:"ratified", scope:"global", due_epoch:$de, due:$d, answer:"x"}' > "$WS/.fleet/decisions/$1.json"; }
# CONTROL FIRST: a deadline outside the window must be SILENT.
mkjson d900 "$((NOW + 1209600))" "2026-08-21"
C4="$(ctx "$(run 'far deadline probe')")"
if ! grep -q 'd900' <<<"$C4"; then ok "control: a deadline 14d out stays silent"; else no "mentioned a deadline far outside the window"; fi
# +25h, not +24h: NOW is captured once at the top of this file and several turns run
# before this point, so a 24h fixture has already drifted under a day by the time the
# hook reads the clock and renders "23h 59m" instead of "1d 0h". Picking a fixture that
# sits on a unit boundary makes the assertion depend on how fast the test ran.
mkjson d901 "$((NOW + 90000))" "2026-08-08 17:00"
C5="$(ctx "$(run 'near deadline probe')")"
if grep -q 'd901 due 2026-08-08 17:00' <<<"$C5"; then ok "a deadline inside 48h is surfaced"; else no "near deadline not surfaced: $C5"; fi
if grep -qE 'd901 .*1d [0-9]+h left' <<<"$C5"; then ok "remaining time is computed, not stored"; else no "remaining time missing: $C5"; fi
mkjson d902 "$((NOW - 7200))" "2026-08-07 06:00"
C6="$(ctx "$(run 'overdue probe')")"
if grep -qE 'OVERDUE — decision d902 .*2h .*ago' <<<"$C6"; then ok "an overdue decision reads as OVERDUE with elapsed"; else no "overdue not reported: $C6"; fi
# The nearest deadline wins, not merely the first file read.
if ! grep -q 'd901' <<<"$C6"; then ok "the nearest (overdue) deadline is chosen over the later one"; else no "picked a later deadline over an overdue one"; fi
# A superseded decision must not carry a live deadline.
jq -nc --arg id d903 --argjson de "$((NOW + 3600))" \
  '{id:$id, state:"ratified", scope:"global", due_epoch:$de, due:"soon", supersedes:"d902"}' > "$WS/.fleet/decisions/d903.json"
jq '.state="ratified"' "$WS/.fleet/decisions/d902.json" > "$WS/t" && mv "$WS/t" "$WS/.fleet/decisions/d902.json"
C7="$(ctx "$(run 'supersede probe')")"
if ! grep -q 'd902' <<<"$C7"; then ok "a superseded decision's deadline is dropped"; else no "a superseded decision still reports a deadline"; fi

section "5. off switch"
OUT8="$(jq -nc --arg p x --arg c "$WS" '{prompt:$p,cwd:$c,session_id:"s-clock-0001"}' | FLEET_CHILD_ID=clockw FLEET_CLOCK=off "$HOOK" 2>/dev/null)"
if [[ -z "$(ctx "$OUT8")" ]]; then ok "FLEET_CLOCK=off emits no clock"; else no "FLEET_CLOCK=off still emitted a clock"; fi
if [[ "$(state '.current_task')" == "x" ]]; then ok "task recording survives FLEET_CLOCK=off"; else no "off switch broke task recording"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
exit $(( fail > 0 ))
