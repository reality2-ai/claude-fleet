#!/usr/bin/env bash
# UserPromptSubmit hook — record the latest prompt as the child's current task, and
# give the agent a sense of TIME PASSING.
#
# WHY THE CLOCK EXISTS
#
# An agent has no running clock. `46ed04b` stamped every injected peer message, which
# fixed *instants*: a lane can now read the wall time at the moment mail arrives. It did
# nothing for DURATION, and duration is what the question "should I hurry up?" is made
# of. A stamp on an incoming message cannot tell a worker that it has been sitting on
# the same task since Tuesday, that the last thing it heard was nine hours ago, or that
# a ratified decision falls due tomorrow. Worse, the stamp only rides on peer mail — a
# human prompt, or a lane working through its own plan, carries no time at all.
#
# So this emits the three durations an agent cannot derive for itself, each turn:
#   * the gap since its own last turn ended  — was that a pause or a night?
#   * elapsed on the current task            — is this taking unreasonably long?
#   * session age                            — how much history is behind this context?
# plus the nearest decision deadline, but only when it is close enough to change what
# the agent should do (default: inside 48h, or already overdue).
#
# RECOMPUTED, NEVER STORED. Every figure is derived from epochs at read time, for the
# same reason `_fleet_decisions_current_print` recomputes its due tags: a stored "2 days
# left" rots exactly like any other unrecomputed number, and an agent has no clock with
# which to notice it had.
#
# Cost: ~35 tokens per turn against a context that measures in the hundreds of
# thousands. Set FLEET_CLOCK=off to disable.
#   FLEET_CLOCK=off        no clock line at all (task recording still happens)
#   FLEET_CLOCK_DUE_H=48   how near a deadline must be before it is worth mentioning
# shellcheck source-path=SCRIPTDIR source=hook-common.sh
source "$(cd "$(dirname "$0")" && pwd)/hook-common.sh"

PROMPT="$(hjq '.prompt // .user_prompt // .input // .message // .text')"
# collapse whitespace, keep it short
TASK="$(printf '%s' "$PROMPT" | tr '\n' ' ' | sed 's/  */ /g')"
TASK="${TASK:0:160}"

# Read the PRIOR state before overwriting it — the gap since the last turn is the
# difference between the old heartbeat and now, and the update below destroys it.
_prev_hb="$(fleet_state_get "$CHILD_ID" '.heartbeat' 0 2>/dev/null)"
_prev_task="$(fleet_state_get "$CHILD_ID" '.current_task' '' 2>/dev/null)"
_task_at="$(fleet_state_get "$CHILD_ID" '.task_started_at' 0 2>/dev/null)"
_sess_at="$(fleet_state_get "$CHILD_ID" '.started_at' 0 2>/dev/null)"
for _v in _prev_hb _task_at _sess_at; do
  [[ "${!_v}" =~ ^[0-9]+$ ]] || printf -v "$_v" '%s' 0
done

# A new task starts its own clock. Same text = same task continuing, so an agent that
# is asked twice for the same thing does not get a reset elapsed figure.
_new_task_at="$_task_at"
if [[ "$TASK" != "$_prev_task" || "$_task_at" -eq 0 ]]; then _new_task_at="$NOW"; fi

fleet_state_jq "$CHILD_ID" --arg t "$TASK" --argjson now "$NOW" --argjson ta "$_new_task_at" \
  '.current_task = $t | .heartbeat = $now | .state = "running" | .ready = false
   | .task_started_at = $ta' >/dev/null 2>&1 || true

[[ "${FLEET_CLOCK:-on}" == "off" ]] && exit 0

# --- build the clock line ----------------------------------------------------
_parts="$(fleet_now_local 2>/dev/null)"
[[ -n "$_parts" ]] || exit 0        # no clock to report is not a reason to fail a turn

if (( _prev_hb > 0 && NOW > _prev_hb )); then
  _parts="$_parts · $(fleet_dur_short $(( NOW - _prev_hb )) 2>/dev/null) since your last turn"
fi
if (( _new_task_at > 0 && NOW > _new_task_at )); then
  _parts="$_parts · $(fleet_dur_short $(( NOW - _new_task_at )) 2>/dev/null) on this task"
elif (( _new_task_at == NOW )); then
  _parts="$_parts · new task"
fi
if (( _sess_at > 0 && NOW > _sess_at )); then
  _parts="$_parts · session $(fleet_dur_short $(( NOW - _sess_at )) 2>/dev/null)"
fi

# Nearest deadline, mentioned only when it is close enough to change a decision.
# Read straight off the ledger files rather than sourcing decisions.sh: this runs on
# every turn of every worker, and the hook prelude deliberately avoids pulling the
# heavier libs in. Superseded records are excluded the same way the ledger does it.
_due_h="${FLEET_CLOCK_DUE_H:-48}"
[[ "$_due_h" =~ ^[0-9]+$ ]] || _due_h=48
_due=""
if (( _due_h > 0 )) && [[ -d "$STATE_DIR/decisions" ]]; then
  _due="$(jq -sr --arg me "$CHILD_ID" --argjson now "$NOW" --argjson win "$(( _due_h * 3600 ))" '
      [ .[] | select(type=="object") ] as $all
    | [ $all[] | select((.state // .latch_state // "") == "ratified") | .supersedes // empty ] as $dead
    | [ $all[]
        | select((.due_epoch // null) != null)
        | select(((.state // .latch_state // .status // "open")) as $s | $s=="open" or $s=="ratified" or $s=="answered")
        | select((.id as $i | $dead | index($i)) == null)
        | select(((.scope // .waiting // "global")) as $sc | $sc=="global" or $sc==$me) ]
    | map(select((.due_epoch - $now) <= $win))
    | sort_by(.due_epoch) | .[0]
    | if . == null then "" else "\(.id)|\(.due // "")|\(.due_epoch - $now)" end
  ' "$STATE_DIR/decisions"/*.json 2>/dev/null || true)"
fi
if [[ -n "$_due" && "$_due" == *"|"* ]]; then
  _did="${_due%%|*}"; _rest="${_due#*|}"; _dwhen="${_rest%%|*}"; _dleft="${_rest##*|}"
  if [[ "$_dleft" =~ ^-?[0-9]+$ ]]; then
    if (( _dleft < 0 )); then
      _parts="$_parts
[fleet clock] OVERDUE — decision $_did was due $_dwhen, $(fleet_dur_short "$_dleft" 2>/dev/null) ago"
    else
      _parts="$_parts
[fleet clock] decision $_did due $_dwhen — $(fleet_dur_short "$_dleft" 2>/dev/null) left"
    fi
  fi
fi

jq -nc --arg c "[fleet clock] $_parts" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}' 2>/dev/null || true
exit 0
