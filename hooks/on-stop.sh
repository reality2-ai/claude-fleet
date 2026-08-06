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
_inbox="$(fleet_inbox_file "$CHILD_ID" 2>/dev/null)" || _inbox=""
[[ -n "$_inbox" && -f "$_inbox" ]] && _pending="$(jq -s '[.[]|select(.delivered==false)]|length' "$_inbox" 2>/dev/null || echo 0)"

# Backstop: an earlier inject may have left a complete message unsubmitted in this worker's
# input box (it started a turn in the paste→Enter window; Enter/C-u were swallowed mid-turn).
# Now that it's at its prompt, submit that stuck message before draining new mail. MANAGED
# workers only (never auto-submit the human's ad-hoc lane).
# shellcheck disable=SC2015  # best-effort chain; the trailing `|| true` is the intended fallback
[[ "$MANAGED" == true ]] && { fleet_flush_stuck_box "$CHILD_ID" >/dev/null 2>&1 && sleep 0.3 || true; }

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
if [[ "$MANAGED" == true ]] && (( _hard_pct > 0 )); then
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

(( _hard_fired == 1 )) || fleet_drain_inbox "$CHILD_ID" force >/dev/null 2>&1 || true

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
if [[ "$MANAGED" == true && "${_pending:-0}" -eq 0 ]] && (( _hard_fired == 0 )) && (( _compact_pct > 0 || _compact_every > 0 )); then
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
