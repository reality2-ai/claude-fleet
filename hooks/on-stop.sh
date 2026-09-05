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

# ── stop_hook_active — RETURN SUCCESS AND DO NOTHING (2026-09-04) ──────────────
# The harness re-fires Stop after any hook (this one or another plugin's) has kept
# the turn open, and sets `stop_hook_active` for those re-fires. Measured on the
# supervisor lane: NINE consecutive Stop fires, roughly twelve seconds apart, until
# the harness overrode the cap — and every one of them ran this script in full.
#
# That is not merely wasted work. Everything below is a SIDE EFFECT: it drains the
# inbox by typing into a tmux pane, submits a stuck input box, and can keystroke
# `/compact`. Re-running those against a turn that is still open is exactly the
# pane-corruption case the hard-ceiling comment further down argues against, and a
# drain fired mid-turn re-injects into a session that has not returned to its prompt.
#
# So: on a re-fire, exit 0 immediately. The FIRST Stop of the turn did the work; the
# state it wrote is still current, and the next genuine turn boundary fires again.
# `.ready` is deliberately NOT set here either — a re-fire means the turn did not
# end, and reporting ready would be a false statement about this lane.
# ‼ AMENDED SAME DAY, AND THE FIRST VERSION OF THIS GUARD BROKE MAIL DELIVERY FLEET-WIDE.
#   It exited here, BEFORE the drain — so any lane whose turns end with a BLOCKING Stop
#   hook (a `/goal` condition, most obviously) never drained its inbox at all. Measured on
#   r2: eight undelivered messages, 1340 seconds stale, while the lane was live and
#   working. `fleet doctor` reported it; nothing else would have.
#
#   THE ORIGINAL REASONING NAMED THE WRONG CULPRIT. What it argued against was `/compact`
#   keystroked on top of a half-submitted message — a COMPACTION hazard, which the drain
#   merely shares a pane with. The drain itself is the one thing on a re-fire that must
#   still happen: the model IS about to be re-invoked, so text placed in its box is read,
#   and withholding it means a lane pursuing a goal never hears anything from anybody.
#
#   So the guard is NARROWED to what it was always for: on a re-fire, skip the
#   PANE-RECONFIGURING work — the stuck-box flush, both compaction paths, and the idle
#   notification — and let the drain run. `.ready` is still NOT set, because a re-fire
#   means the turn did not end and reporting ready would be a false statement.
STOP_REFIRE=0
if [[ "$(hjq '.stop_hook_active')" == "true" ]]; then
  STOP_REFIRE=1
  fleet_journal_append "$CHILD_ID" "stop re-fire (stop_hook_active) — drain only" 2>/dev/null || true
fi

if (( STOP_REFIRE == 0 )); then
  fleet_state_jq "$CHILD_ID" --argjson now "$NOW" '.ready=true | .heartbeat=$now' >/dev/null 2>&1 || true
else
  fleet_state_jq "$CHILD_ID" --argjson now "$NOW" '.heartbeat=$now' >/dev/null 2>&1 || true
fi
# Optional ground-truth liveness journal (no-op unless FLEET_JOURNAL is set).
fleet_journal_append "$CHILD_ID" "stop turn" 2>/dev/null || true

# Count undelivered queued messages BEFORE draining — would this child keep working?
_pending=0
_inbox="$(fleet_inbox_file "$CHILD_ID" 2>/dev/null)" || _inbox=""
[[ -n "$_inbox" && -f "$_inbox" ]] && _pending="$(jq -s '[.[]|select(.delivered==false)]|length' "$_inbox" 2>/dev/null || echo 0)"

# Backstop: an earlier inject may have left a complete message unsubmitted in this worker's
# input box (it started a turn in the paste→Enter window; Enter/C-u were swallowed mid-turn).
# Now that it's at its prompt, submit that stuck message before draining new mail. MANAGED
# workers only (never auto-submit the human's ad-hoc lane).
# shellcheck disable=SC2015  # best-effort chain; the trailing `|| true` is the intended fallback
[[ "$MANAGED" == true && "$STOP_REFIRE" == 0 ]] && { fleet_flush_stuck_box "$CHILD_ID" >/dev/null 2>&1 && sleep 0.3 || true; }

# HARD CEILING — the only compaction that runs while mail is waiting.
#
# The routine trigger further down fires only on a MANAGED worker that is IDLE with an
# EMPTY inbox. A worker kept busy by a steady stream of peer mail never meets that
# condition and simply grows until the provider auto-compacts at ~95%, which is the most
# expensive compaction available: it happens at maximum context, unplanned, mid-task.
# Measured on the r2-hive lane's own transcript (29,364 turns): 9.0% of turns ran above
# 700k tokens, 1.0% above 900k, and the peak was 999,801 — it reached the ceiling. The
# routine trigger was set to 70% the whole time. It was not holding.
#
# This runs BEFORE the drain, and skips the drain when it fires. That ordering is the
# whole safety argument: draining injects text into the pane, and `/compact` keystroked
# on top of a half-submitted message corrupts it. Mail stays queued — an already-supported
# state with its own defer path — and lands on the next turn against a fresh context.
#   FLEET_COMPACT_HARD_PCT=85 (0 disables)
_hard_pct="${FLEET_COMPACT_HARD_PCT:-85}"
[[ "$_hard_pct" =~ ^[0-9]+$ ]] || _hard_pct=0
case " ${FLEET_COMPACT_SKIP:-} " in *" $CHILD_ID "*) _hard_pct=0 ;; esac
_hard_fired=0
if [[ "$MANAGED" == true ]] && (( _hard_pct > 0 && STOP_REFIRE == 0 )); then
  _hctx="$(fleet_ctx_tokens "$CHILD_ID" 2>/dev/null || echo 0)"; [[ "$_hctx" =~ ^[0-9]+$ ]] || _hctx=0
  _hceil="${FLEET_CTX_CEILING:-1000000}"
  if (( _hctx > 0 && _hctx * 100 >= _hceil * _hard_pct )); then
    _hard_fired=1
    fleet_state_jq "$CHILD_ID" '.turns_since_compact=0' >/dev/null 2>&1 || true
    fleet_log compact "$CHILD_ID" "HARD ceiling ${_hctx}/${_hceil} (>=${_hard_pct}%) — compacting, drain deferred to next turn" 2>/dev/null || true
    ( fleet_compact "$CHILD_ID" >/dev/null 2>&1 || true ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
fi

# ‼ THE HOOK NO LONGER DELIVERS — `fleet courier` DOES (`D-159`, `D-161`).
#   This line made DELIVERY THE RECIPIENT'S JOB: a lane whose hooks are absent was
#   undeliverable-to while every health signal read normal (r2, 2026-09-05:
#   heartbeat 4s fresh, last_drain_attempt 2898s stale, mail queued behind it), and
#   a read-only reviewer could never receive at all because draining is a write.
#   The send path still attempts immediate delivery (`comms.sh:77`); what moved to
#   the courier is the RETRY, which is the half that needed somebody always running.
#
# ‼‼ AND THIS TRADE IS ONLY SAFE BECAUSE `fleet doctor` NOW TREATS AN ABSENT
#    COURIER AS A FAILURE. Before this line went, no courier meant slower mail;
#    after it, no courier means NO retries fleet-wide. The two changes are one
#    change and must never be separated — dropping this drain while absence is
#    still benign is a silent fleet-wide outage waiting for the first failed send.

# Event-driven idle signal (default ON): a MANAGED worker that returned to its prompt
# with NOTHING queued is about to sit idle — proactively tell the supervisor so it can
# give direction or pick up the completion, instead of the human discovering it idle.
# Fires only on genuine idle (empty inbox), never self-notifies, one note per idle.
#   FLEET_IDLE_NOTIFY=off  disables · FLEET_IDLE_NOTIFY_TO=<id>  routes to another coordinator
# WORKSPACE OFF-SWITCH, added 2026-08-07 on Roy's instruction ("we are getting too many
# nothing queued messages"). An env var cannot reach an ALREADY-RUNNING session — its
# environment is fixed at launch — but this script is re-read on every fire, so a file
# check takes effect immediately and fleet-wide without restarting any worker.
#   touch .fleet/no-idle-notify   silences · rm it   restores
# Default behaviour is unchanged when the file is absent.
if [[ -e "${FLEET_WORKSPACE:-.}/.fleet/no-idle-notify" ]]; then
  _idle_notify=off
else
  _idle_notify="${FLEET_IDLE_NOTIFY:-on}"
fi
if [[ "$_idle_notify" != "off" && "$MANAGED" == true && "$STOP_REFIRE" == 0 ]]; then
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

# Proactive context compaction. A long-lived --resume session re-processes its whole,
# ever-growing transcript every turn, so token cost climbs with session age — the dominant
# fleet token sink. When a MANAGED worker returns to its prompt IDLE, compact it if EITHER:
#   • SIZE (primary, adaptive): last-turn context ≥ FLEET_COMPACT_AT_PCT% of FLEET_CTX_CEILING
#     — fires BEFORE Claude's ~95% auto-compact, and adapts per-worker (a fast grower like the
#     supervisor compacts sooner than a slow one), keeping the AVERAGE per-turn cost lower; or
#   • TURNS (fallback/backstop): FLEET_COMPACT_EVERY turns since the last compaction — covers
#     the rare case the context size can't be read. It fires ONLY when the size reading came
#     back unknown (0). Running both unconditionally would compact a lane sitting at 5% of the
#     ceiling purely because it had taken 40 turns, and a compaction DESTROYS the cached prefix
#     — the turn backstop is insurance against a blind meter, never a second schedule.
# RESUME.md + entity memory anchor real state, so a compaction never loses working context.
#   FLEET_COMPACT_AT_PCT=70 (0 disables size trigger) · FLEET_COMPACT_EVERY=40 (0 disables)
#   FLEET_CTX_CEILING=1000000 · FLEET_COMPACT_SKIP="supervisor other" exempts lanes
# The default below WAS 0 while this comment said 40: the documented backstop did not exist,
# so a lane whose size reading was blind (every codex lane, until fleet_ctx_tokens learned
# codex's field names) never compacted at all and nothing said so.
_compact_pct="${FLEET_COMPACT_AT_PCT:-70}"; _compact_every="${FLEET_COMPACT_EVERY:-40}"
[[ "$_compact_pct"   =~ ^[0-9]+$ ]] || _compact_pct=0
[[ "$_compact_every" =~ ^[0-9]+$ ]] || _compact_every=0
case " ${FLEET_COMPACT_SKIP:-} " in *" $CHILD_ID "*) _compact_pct=0; _compact_every=0 ;; esac
# `_hard_fired` excluded: a compaction is already in flight, and a second `/compact`
# keystroked behind it lands in whatever pane state the first one left.
if [[ "$MANAGED" == true && "${_pending:-0}" -eq 0 ]] && (( _hard_fired == 0 && STOP_REFIRE == 0 )) && (( _compact_pct > 0 || _compact_every > 0 )); then
  _turns="$(fleet_state_get "$CHILD_ID" '.turns_since_compact' 0 2>/dev/null)"
  [[ "$_turns" =~ ^[0-9]+$ ]] || _turns=0
  _turns=$(( _turns + 1 ))
  _do=0; _ctx=0
  if (( _compact_pct > 0 )); then
    _ctx="$(fleet_ctx_tokens "$CHILD_ID" 2>/dev/null || echo 0)"; [[ "$_ctx" =~ ^[0-9]+$ ]] || _ctx=0
    _ceil="${FLEET_CTX_CEILING:-1000000}"
    (( _ctx > 0 && _ctx * 100 >= _ceil * _compact_pct )) && _do=1
  fi
  # Backstop ONLY on a blind meter (_ctx == 0), never alongside a working one.
  (( _ctx == 0 && _compact_every > 0 && _turns >= _compact_every )) && _do=1
  # A blind meter is a defect, not a normal state — leave a trail so it is findable
  # instead of being absorbed by the backstop and never noticed.
  if (( _ctx == 0 && _compact_pct > 0 )); then
    fleet_log ctx-unknown "$CHILD_ID" \
      "context size unreadable (provider=$PROVIDER); turn backstop at $_turns/$_compact_every" 2>/dev/null || true
  fi
  if (( _do == 1 )); then
    # Idle + over threshold: compact now, reset the counter. Background it so a busy pane
    # during the send can never stall hook completion (same rule as idle-notify).
    fleet_state_jq "$CHILD_ID" '.turns_since_compact=0' >/dev/null 2>&1 || true
    ( fleet_compact "$CHILD_ID" >/dev/null 2>&1 || true ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  else
    fleet_state_jq "$CHILD_ID" --argjson t "$_turns" '.turns_since_compact=$t' >/dev/null 2>&1 || true
  fi
fi
exit 0
