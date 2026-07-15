# shellcheck shell=bash
# comms.sh — inter-agent message passing (OTP-style named mailboxes).
#
# Each child has a mailbox at .fleet/inbox/<id>.jsonl. `fleet send` enqueues a
# message and delivers it by typing it into the target's tmux prompt — but only
# when the target is *ready* (at its prompt, not mid-task). If the target is
# busy, the message waits; the target's Stop hook drains the mailbox the moment
# it returns to its prompt. This is the "hybrid" delivery model.
#
# Requires: registry.sh + tmux.sh sourced. Uses flock when available.

# Hard cap on conversation depth, to stop two agents ping-ponging forever.
# Auto-tracked: a message a sender produces right after receiving one inherits
# hop+1; the cap refuses sends past it. Configure via [supervisor] max_hops.
fleet_max_hops() { printf '%s\n' "${FLEET_MAX_HOPS:-${SUP_MAX_HOPS:-6}}"; }

# inbox/<id>.jsonl — validated via the central choke point (lib/common.sh). This one
# matters: `fleet send`/`fleet ask` take BOTH the target and `--from` from argv, and
# --from is chosen by whichever agent is talking, so an unvalidated id here reaches
# mkdir/append/truncate/mv on a caller-named path. Fails closed (no path, status 1).
fleet_inbox_file() { fleet_member_path "${STATE_DIR:-}/inbox" "${1:-}" .jsonl; }

# enqueue a message carrying its hop depth and kind (ask|msg|fyi|answer).
# notify=true (default) → pending injection into the thread; notify=false → stored
# as a read-only record (e.g. a full answer the asker reads via `fleet inbox`).
fleet_enqueue() {
  local to="$1" from="$2" text="$3" hops="${4:-1}" kind="${5:-msg}" notify="${6:-true}" f ts delivered=false
  [[ "$notify" == "false" ]] && delivered=true
  # The readers below all gate on `[[ -f "$f" ]]`, which absorbs an empty path on its
  # own; this WRITER cannot — it would mkdir/lock/append relative to $PWD. Fail closed.
  f="$(fleet_inbox_file "$to")" || { warn "refusing to enqueue mail for invalid member id '$to'"; return 1; }
  mkdir -p "$(dirname "$f")"
  # A valid id still lets an attacker pre-plant OR race-replant a SYMLINK at the inbox or
  # the lock. Confirmed 2026-07-15 against 6d19957: a link at "$f.lock" was followed by the
  # TRUNCATING `9>` open and an out-of-tree victim was TRUNCATED. Closed by making the whole
  # lock+append ONE fd-bound no-follow transaction (fleet_safe_enqueue -> lib/fleet-safeio.py
  # `enqueue`): flock(lock, O_NOFOLLOW) then APPEND the line (inbox, O_NOFOLLOW|fstat-regular)
  # then release. No shell `exec 9>>lock`/`>>inbox`: the O_NOFOLLOW open IS the check, so a
  # pre-planted or live-replanted symlink at EITHER path is refused, never followed. Mutual
  # exclusion (and 60-way mailbox correctness) is unchanged — same lock inode. A refused
  # symlink or a missing primitive FAILS CLOSED (mail refused), never reported as success.
  ts="$(date +%s)"
  local rc=0
  jq -nc --argjson ts "$ts" --arg from "$from" --arg to "$to" --arg text "$text" --argjson hops "$hops" --arg kind "$kind" --argjson delivered "$delivered" \
    '{ts:$ts, from:$from, to:$to, text:$text, hops:$hops, kind:$kind, delivered:$delivered}' \
    | fleet_safe_enqueue "$f" "$f.lock" || rc=$?
  if (( rc != 0 )); then
    warn "refusing to enqueue: inbox '$f' or its lock is unsafe (symlink) or safe-IO unavailable"
    return 1
  fi
}

# Deliver a brief note into <to>'s thread now if it's idle, else queue it for the
# next idle drain. Used by the off-thread responder and by `fleet send`.
fleet_notify() {
  local to="$1" from="$2" text="$3" hop="${4:-1}"
  fleet_enqueue "$to" "$from" "$text" "$hop" fyi true
  fleet_drain_inbox "$to" >/dev/null 2>&1 || true
}

# Compute the hop depth for a message <from> is about to send: one deeper than
# the last message delivered TO <from> (a reply), else 1 (a fresh thread).
# Returns the hop number on stdout, or empty if the cap would be exceeded.
fleet_next_hop() {
  local from="$1" prev hop
  prev="$(fleet_state_get "$from" '.last_inbound_hops' 0)"; [[ "$prev" =~ ^[0-9]+$ ]] || prev=0
  hop=$(( prev + 1 ))
  # consume the inherited depth so only the immediate reply carries it
  fleet_state_jq "$from" '.last_inbound_hops=0' >/dev/null 2>&1 || true
  (( hop > $(fleet_max_hops) )) && { printf ''; return 1; }
  printf '%s\n' "$hop"
}

# Is <to>'s pane ACTIVELY mid-turn (a turn in flight RIGHT NOW)? Keys ONLY on positive
# active-work signals Claude Code shows DURING a turn — primarily the "esc to interrupt"
# footer, plus "still thinking" / "Compacting". It deliberately does NOT key on:
#   • the permission-mode glyph ⏵⏵ — shown in EVERY footer, idle or busy;
#   • spinner GLYPHS ✻ ✶ ✽ — whose timing summary ("Brewed for 10m 50s") PERSISTS after
#     the turn ends;
#   • a token count or bare "shift+tab to cycle" — present at an idle prompt too.
# Keying on those (as the old detector did) marked a calm pane "working" forever, which —
# once the inject path depended on it — stranded ALL mail to ALL workers. On doubt (no
# window / capture fail / nothing recognisable) it returns NON-zero = NOT working, so
# callers err toward DELIVERING, never toward never-delivering. FLEET_PANE_IDLE_CHECK=off
# forces "not working".
#   fleet_pane_is_working <to>
fleet_pane_is_working() {
  local to="$1"
  [[ "${FLEET_PANE_IDLE_CHECK:-on}" == "off" ]] && return 1
  fleet_tmux_has_window "$to" 2>/dev/null || return 1
  local tgt="$FLEET_TMUX_SESSION:$to" tail
  tail="$(fleet_tmux capture-pane -p -t "$tgt" 2>/dev/null | grep -vE '^[[:space:]]*$' | tail -n 6)" || return 1
  [[ -n "$tail" ]] || return 1
  local working='esc to interrupt|to interrupt\)|still thinking|[Cc]ompacting…|[Cc]ompacting conversation'
  printf '%s\n' "$tail" | grep -qE "$working"
}

# Is <to>'s pane sitting at its idle prompt (NOT mid-turn)? Idle = NOT actively working
# AND a recognised prompt box is present (so a garbled/unknown pane is treated as busy,
# never idle). Recognises the current Claude Code prompt (the ❯ box + "shift+tab to cycle"
# footer) as well as older box styles. Used by the .ready TTL unstick (fleet_reconcile)
# and fleet doctor. FLEET_PANE_IDLE_CHECK=off → every live pane reads idle.
#   fleet_pane_is_idle <to>
fleet_pane_is_idle() {
  local to="$1"
  [[ "${FLEET_PANE_IDLE_CHECK:-on}" == "off" ]] && return 0
  fleet_tmux_has_window "$to" 2>/dev/null || return 1
  fleet_pane_is_working "$to" && return 1
  local tgt="$FLEET_TMUX_SESSION:$to" tail
  tail="$(fleet_tmux capture-pane -p -t "$tgt" 2>/dev/null | grep -vE '^[[:space:]]*$' | tail -n 12)" || return 1
  [[ -n "$tail" ]] || return 1
  # Positive prompt-box signatures (so an unknown/garbled pane is treated as busy, never
  # idle). ❯ + "shift+tab to cycle" = current Claude Code; the rest cover older styles.
  local promptbox='❯|│ >|^[[:space:]]*>[[:space:]]*$|Try "|\? for shortcuts|shift\+tab to cycle|╰─|╭─'
  printf '%s\n' "$tail" | grep -qE "$promptbox" && return 0
  return 1
}

# Is <to>'s pane blocked on a hard provider quota/credits exhaustion? This is
# distinct from a transient throttle: retry nudges will not fix it. The operator
# should request usage/admin credits or hand off to another provider.
fleet_pane_is_provider_exhausted() {
  local to="$1"
  [[ "${FLEET_PROVIDER_EXHAUSTION_CHECK:-on}" == "off" ]] && return 1
  fleet_tmux_has_window "$to" 2>/dev/null || return 1
  local tgt="$FLEET_TMUX_SESSION:$to" tail
  tail="$(fleet_tmux capture-pane -p -t "$tgt" 2>/dev/null | grep -vE '^[[:space:]]*$' | tail -n 10)" || return 1
  [[ -n "$tail" ]] || return 1
  local sig='usage-credits|request more usage from your admin|contact your admin.*usage|usage from your admin|quota exhausted|credits exhausted'
  printf '%s\n' "$tail" | grep -qiE "$sig"
}

# Is <to>'s pane currently blocked on an API rate-limit / transient API error
# (i.e. "throttled")? Distinct from idle/dead: a throttled worker is HEALTHY but
# waiting on the provider, and must NEVER be restarted for it (the api-watchdog
# un-sticks it when the block lifts). Mirrors the signature set the api-watchdog
# uses. Returns 0 when throttled. FLEET_THROTTLE_CHECK=off forces "not throttled".
#   fleet_pane_is_throttled <to>
fleet_pane_is_throttled() {
  local to="$1"
  [[ "${FLEET_THROTTLE_CHECK:-on}" == "off" ]] && return 1
  fleet_tmux_has_window "$to" 2>/dev/null || return 1
  fleet_pane_is_provider_exhausted "$to" && return 1
  local tgt="$FLEET_TMUX_SESSION:$to" tail
  tail="$(fleet_tmux capture-pane -p -t "$tgt" 2>/dev/null | grep -vE '^[[:space:]]*$' | tail -n 8)" || return 1
  [[ -n "$tail" ]] || return 1
  local sig='temporarily (limiting|unavailable)|rate.?limit|Overloaded|overloaded_error|API [Ee]rror|error 529|529 |Internal server error|exceeded your|usage limit|temporarily limiting requests'
  printf '%s\n' "$tail" | grep -qiE "$sig"
}

# Deliver one message into a target's tmux prompt and submit it. The full text is
# typed in small keystroke chunks (gentle on a full-screen TUI — avoids the
# reflow/blank a single huge keystroke blast causes), then a brief settle pause,
# then ONE Enter — so even a long reply arrives complete, as a single turn.
FLEET_INJECT_DELAY="${FLEET_INJECT_DELAY:-0.2}"
FLEET_INJECT_CHUNK="${FLEET_INJECT_CHUNK:-500}"
FLEET_INJECT_CHUNK_DELAY="${FLEET_INJECT_CHUNK_DELAY:-0.05}"

# Does a captured (escapes-preserved) ❯ input line hold REAL, non-dim content? Pure +
# deterministic (no tmux) so it is unit-testable. Claude Code renders ghost/placeholder
# text in an EMPTY box DIM (\e[2m…); real typed input is NON-dim. Drop DIM spans (to
# their reset, or to end-of-line if unclosed), strip remaining SGR codes, the ❯ glyph,
# the U+00A0 (NBSP) pad Claude Code uses, and whitespace — anything left is real input.
_fleet_line_has_real_input() {
  local line="$1" esc on off; esc=$'\e'; on=$'\x01'; off=$'\x02'
  # Map dim-ON (\e[2m) → on-sentinel and dim-OFF (\e[0m / \e[22m / \e[m) → off-sentinel,
  # strip every other SGR code, then delete all text between the sentinels (the dim
  # ghost/placeholder run — even when it carries intermediate SGR like \e[39m, which a
  # naive [^\e]* would stop at). Whatever survives outside a dim region is real input.
  line="$(printf '%s' "$line" | sed -E \
    -e "s/${esc}\[2m/${on}/g" \
    -e "s/${esc}\[(0|22|)m/${off}/g" \
    -e "s/${esc}\[[0-9;]*m//g" \
    -e "s/${on}[^${off}]*${off}//g" \
    -e "s/${on}[^${off}]*\$//g" \
    -e "s/[${on}${off}]//g")"
  line="${line#❯}"
  line="${line//$' '/}"
  line="${line//[[:space:]]/}"
  [[ -n "$line" ]]
}

# Is <to>'s Claude Code input box occupied by REAL input we must NOT type onto (a human
# mid-typing, or a prior un-submitted inject)? Typing onto it concatenates + can't
# cleanly submit (the "stuck + truncated in the current prompt" bug). Capture WITH
# escapes (-e) so dim ghost text isn't mistaken for content; grep the LAST ❯ line.
#
# IMPORTANT: grep ❯ from the FULL capture, NOT a fixed `tail -n N` slice. A long message
# in the box WRAPS across many rows, and the ❯ sits at the TOP of that wrapped block — a
# `tail -6` (the old code) would slice the ❯ line off the bottom and report the box CLEAR
# even though it's full. That false-clear made confirm-landed bail before pressing Enter,
# leaving long messages stranded in the box (the overnight fleet-wide stuck). The last ❯
# in the whole pane is always the live input prompt (history is above it).
# Conservative: no window / capture failure → "not busy", so a missed read errs toward
# delivering, never toward never-delivering.
fleet_input_busy() {
  local to="$1" line
  line="$(fleet_tmux capture-pane -e -p -t "$FLEET_TMUX_SESSION:$to" 2>/dev/null | grep -aF '❯' | tail -n1)" || return 1
  [[ -z "$line" ]] && return 1
  _fleet_line_has_real_input "$line"
}

# Forensic trace for the delivery path (off unless FLEET_INJECT_TRACE points to a file).
# Records, per step, the pane's working-state and the raw ❯ input line, so an intermittent
# stuck-at-prompt can be reconstructed after the fact instead of inferred.
_fleet_inject_trace() {
  [[ -n "${FLEET_INJECT_TRACE:-}" ]] || return 0
  local to="$1" tag="$2" wk box
  fleet_pane_is_working "$to" && wk=WORKING || wk=idle
  box="$(fleet_tmux capture-pane -e -p -t "$FLEET_TMUX_SESSION:$to" 2>/dev/null | grep -aF '❯' | tail -1 | tr -d '\r' | cat -v | head -c 120)"
  printf '%s %-10s %-8s %-7s box=[%s]\n' "$(date '+%H:%M:%S')" "$to" "$tag" "$wk" "$box" >> "$FLEET_INJECT_TRACE" 2>/dev/null || true
}

fleet_inject() {
  local to="$1" from="$2" text="$3" hops="${4:-1}" kind="${5:-msg}"
  # never keystroke-inject a claude-bg worker — its window hosts a bash controller,
  # not a TUI; delivery there goes through the controller's programmatic turns.
  [[ "$(fleet_state_get "$to" '.faculty' '')" == "claude-bg" ]] && return 1
  _fleet_inject_trace "$to" entry

  # --- DEFER GATE (rc 2 = backpressure, NOT failure — leaves the message queued for the
  # next drain). Defer ONLY when the box already holds REAL (non-dim) input — a human
  # mid-typing, or a prior inject still sitting unsubmitted — so we never paste on top of
  # and garble it. We do NOT defer merely because the pane is mid-turn: GROUND TRUTH from
  # the live trace is that an Enter submitted while Claude is working is QUEUED by Claude
  # Code (it shows "Press up to edit queued messages") and processed when the turn ends —
  # it is NOT swallowed. So delivering to a busy worker is fine; the earlier "submit only
  # when idle" gate was wrong and was itself stranding messages (it skipped the Enter and
  # left the text in the box). Note: Claude Code's dim "Press up to edit queued messages"
  # hint reads as a CLEAR box (not real input), so it does not block the next delivery.
  if [[ "${FLEET_INJECT_DEFER:-on}" != "off" ]] && fleet_input_busy "$to"; then return 2; fi

  text="$(printf '%s' "$text" | tr '\n' ' ')"   # single line — Enter submits
  local tag="fleet msg"; [[ "$kind" == "ask" ]] && tag="fleet ask"
  local full
  full="[$tag from $from · hop $hops/$(fleet_max_hops)] $text"
  local tgt="$FLEET_TMUX_SESSION:$to"

  # --- INSERT. Default: ATOMIC bracketed paste via a tmux buffer (FLEET_INJECT_PASTE
  # on). The whole message is loaded into a per-target buffer and pasted in ONE
  # operation wrapped in bracketed-paste control codes (-p), so the TUI inserts it
  # atomically and NEVER auto-submits it — no char-stream reflow race can truncate it
  # the way chunked `send-keys -l` could (the "message truncated too" bug), and any
  # special chars / future multi-line content survive intact. The Enter below is the
  # only submit. FLEET_INJECT_PASTE=off restores the legacy chunked-typing path.
  if [[ "${FLEET_INJECT_PASTE:-on}" != "off" ]]; then
    local buf="fleet-inj-${to}"
    if ! printf '%s' "$full" | fleet_tmux load-buffer -b "$buf" - 2>/dev/null \
       || ! fleet_tmux paste-buffer -d -p -b "$buf" -t "$tgt" 2>/dev/null; then
      fleet_tmux delete-buffer -b "$buf" 2>/dev/null || true
      return 1
    fi
  else
    local i=0 n=${#full}
    while (( i < n )); do
      fleet_tmux send-keys -t "$tgt" -l "${full:i:FLEET_INJECT_CHUNK}" 2>/dev/null || return 1
      i=$(( i + FLEET_INJECT_CHUNK ))
      (( i < n )) && sleep "$FLEET_INJECT_CHUNK_DELAY"
    done
  fi
  _fleet_inject_trace "$to" pasted
  sleep "$FLEET_INJECT_DELAY"

  # Advisory landed-check (does NOT block the Enter). The overnight fleet-wide stuck was a
  # pre-submit check that read the box as empty and SKIPPED the Enter, stranding the message.
  # We never skip the Enter again. We only note whether our content is visibly present, to
  # decide requeue-vs-delivered at the end (so a paste the TUI genuinely dropped isn't marked
  # delivered = silent loss). Uses the full-capture fleet_input_busy.
  local seen_landed=0
  fleet_input_busy "$to" && seen_landed=1

  # --- SUBMIT — ALWAYS press Enter, then an EXTRA Enter (Roy's belt-and-suspenders). On a
  # landed paste the first Enter submits; if it raced the paste render and didn't take, the
  # second submits; if the first already landed, the second is a harmless no-op at a clear/
  # queued prompt. Enter is handled whether the pane is idle (submits as a turn) or busy
  # (Claude Code QUEUES it — "Press up to edit queued messages" — and runs it at turn end).
  fleet_tmux send-keys -t "$tgt" Enter 2>/dev/null || return 1
  sleep "${FLEET_INJECT_ENTER_GAP:-0.2}"
  fleet_tmux send-keys -t "$tgt" Enter 2>/dev/null || true
  _fleet_inject_trace "$to" entered

  [[ "${FLEET_INJECT_VERIFY:-on}" == "off" ]] && return 0
  # --- VERIFY: our message should be GONE from the box (submitted, or queued behind a turn).
  # If it lingers, re-Enter (a spurious Enter at a clear/queued prompt is a no-op).
  local try
  for try in $(seq 1 "${FLEET_INJECT_SUBMIT_TRIES:-6}"); do
    sleep 0.3
    if ! fleet_input_busy "$to"; then
      # Box clear. If we saw our content land, it submitted → delivered. If we NEVER saw it
      # land and it's still clear, the paste didn't take (the box was empty all along) →
      # requeue rather than silently mark delivered.
      if (( seen_landed )); then _fleet_inject_trace "$to" submitted; return 0; fi
      _fleet_inject_trace "$to" never-landed; return 1
    fi
    seen_landed=1                                      # it's in the box now → it did land
    fleet_tmux send-keys -t "$tgt" Enter 2>/dev/null || return 1
  done
  # Still in the box after repeated Enters (rare). It's intact; the Stop-hook flush and the
  # unblock janitor will submit it at the worker's next idle. Count delivered to avoid a
  # duplicate re-paste. (Never C-u: it would drop a valid message and is a no-op mid-turn.)
  _fleet_inject_trace "$to" left-for-flush
  return 0
}

# Does <to>'s input box hold a STUCK FLEET INJECT specifically (not arbitrary text)? Every
# inject begins with a literal "[fleet msg from …]" / "[fleet ask from …]" tag that we control,
# so matching it identifies our own un-submitted message — and, crucially, NEVER matches a
# human's typing. This is the gate for the auto-Enter mechanisms (Stop-hook flush + unblock
# janitor): the fleet tmux session is often ATTACHED with a human typing into a worker window
# (e.g. the supervisor), so "leftover box content" is NOT safe to auto-submit — only content
# that is provably one of our injects is. Provider-neutral: the tag is the same on Codex panes.
# (A long inject that Claude Code collapsed to a "[Pasted text #N]" placeholder won't match;
# those are submitted in-band at delivery, not left for this gate.)
fleet_box_has_stuck_inject() {
  local to="$1" line
  line="$(fleet_tmux capture-pane -e -p -t "$FLEET_TMUX_SESSION:$to" 2>/dev/null | grep -aF '❯' | tail -1)" || return 1
  [[ -n "$line" ]] || return 1
  printf '%s' "$line" | sed -E 's/\x1b\[[0-9;]*m//g' | grep -qE '\[fleet (msg|ask) from '
}

# Stop-hook backstop: when a MANAGED worker returns to its prompt, an earlier inject may have
# left a COMPLETE message sitting unsubmitted in its input box (it started a turn in the
# paste→Enter window, and the Enter was queued/raced). Submit it — but ONLY if the box holds a
# recognisable fleet inject, never arbitrary text, because a human may be typing into this
# window (the fleet session is often attached). Returns 0 if it flushed one.
fleet_flush_stuck_box() {
  local to="$1"
  [[ "$(fleet_state_get "$to" '.faculty' '')" == "claude-bg" ]] && return 1
  fleet_tmux_has_window "$to" || return 1
  fleet_pane_is_working "$to" && return 1            # only act at idle
  fleet_box_has_stuck_inject "$to" || return 1       # only submit OUR inject, never human text
  fleet_tmux send-keys -t "$FLEET_TMUX_SESSION:$to" Enter 2>/dev/null || return 1
  fleet_log unstick-box "$to" "submitted a stuck fleet inject at idle" 2>/dev/null || true
  return 0
}

# Bound a worker's growing context by injecting Claude Code's /compact slash
# command at its prompt. A long-lived `--resume` session re-processes its whole
# transcript every turn, so token cost climbs with session age; /compact replaces
# the transcript with a summary so subsequent turns run cheap again. RESUME.md +
# entity memory are the durable anchors, so a compaction never loses real state.
#
# ONLY safe to call when the pane is idle (at its prompt with no queued mail) —
# the caller (the Stop hook) guarantees that. Returns non-zero for a non-TUI
# worker (claude-bg, driven by a bash controller), an offline window, or a send
# failure, so the counter that triggers it can decline to reset and retry later.
fleet_compact() {
  local to="$1"
  # a claude-bg window hosts a controller, not a TUI — never keystroke /compact there
  [[ "$(fleet_state_get "$to" '.faculty' '')" == "claude-bg" ]] && return 1
  fleet_tmux_has_window "$to" || return 1
  local tgt="$FLEET_TMUX_SESSION:$to"
  fleet_tmux send-keys -t "$tgt" -l "/compact" 2>/dev/null || return 1
  sleep "${FLEET_INJECT_DELAY:-0.2}"
  fleet_tmux send-keys -t "$tgt" Enter 2>/dev/null || return 1
  # A flaky first Enter can leave /compact sitting unsubmitted in the input box;
  # a spurious second Enter at an empty prompt is a harmless no-op in Claude Code.
  sleep 0.3; fleet_tmux send-keys -t "$tgt" Enter 2>/dev/null || true
  fleet_log compact "$to" "injected /compact (context bound)" 2>/dev/null || true
  return 0
}

# Restore the exclusive drain snapshot <snap> back to the inbox <f>. On SUCCESS the snapshot
# is consumed by the rename and nothing lingers. On FAILURE (destination conflict — e.g. $f
# raced to a directory — or safe-IO down) the snapshot is the SOLE surviving copy of the mail,
# so it is KEPT on disk and its path logged LOUDLY; it is NEVER removed. Callers must not
# `rm` <snap> after this — do so only where the mail is confirmed safe at <f>.
_fleet_drain_restore() {
  local snap="$1" f="$2" to="$3"
  fleet_safe_rename "$snap" "$f" && return 0
  fleet_log deliver-fail "$to" "RESTORE FAILED; mail preserved in snapshot '$snap' (recover manually)" 2>/dev/null || true
  warn "fleet_drain_inbox: could not restore inbox for '$to' — mail preserved in $snap (not lost)"
  return 1
}

# Deliver any undelivered mail to <to>. Returns 0 if delivered (or nothing to
# do), 1 if it had to leave mail queued (target offline or busy).
#   fleet_drain_inbox <to> [force]
fleet_drain_inbox() {
  local to="$1" force="${2:-}" f
  f="$(fleet_inbox_file "$to")" || return 0
  [[ -f "$f" ]] || return 0
  # claude-bg workers are driven by their own controller (programmatic -p turns); the
  # cli-tmux drain must NOT type into the controller's bash window. Leave mail for it.
  [[ "$(fleet_state_get "$to" '.faculty' '')" == "claude-bg" ]] && return 1
  fleet_tmux_has_window "$to" || return 1                   # offline → keep queued
  if [[ "$force" != "force" ]]; then
    [[ "$(fleet_state_get "$to" '.ready' false)" == "true" ]] || return 1   # busy → keep queued
  fi
  # NO-FOLLOW lock held across the whole read-modify-write: a coprocess owns an
  # O_NOFOLLOW flock fd (bash cannot open O_NOFOLLOW), so a symlinked/replanted "$f.lock" is
  # refused, never followed/truncated (the old `9>`/`9>>` shell open did follow it). Fail
  # closed if the primitive is unavailable — mail simply stays queued, never drained unsafely.
  fleet_safe_lock "$f.lock" || return 1
  local dir; dir="$(dirname "$f")"
  # ATOMIC SNAPSHOT. A held lock + repeated by-name opens is NOT a transaction: the lock is
  # cooperative, and a hostile same-dir writer can swap a SAME-OWNER regular file between the
  # count/read/commit opens (O_NOFOLLOW catches a symlink, not a regular->regular swap). So
  # GRAB the inbox to a private, unpredictable name via rename under the held lock; every
  # read/commit below then operates on ONE inode no other writer can name or swap.
  local snap; snap="$(mktemp "$dir/.snap.XXXXXX" 2>/dev/null)" || { fleet_safe_unlock; return 1; }
  rm -f "$snap" 2>/dev/null || true                         # rotate creates it fresh via rename
  # Identity-checked grab: rotate emits the VERIFIED inode's content (open+fstat src, rename,
  # reopen dst, require same dev/ino/regular/owner). rc: 0 ok(+content), 4 no inbox, 3 symlinked
  # inbox, 6 swap detected in the open->rename window, other = error. A failure is NEVER read as
  # an empty queue — we preserve/restore the snapshot and fail closed (no data-loss-as-success).
  local content _rr=0
  content="$(fleet_safe_rotate "$f" "$snap")" || _rr=$?
  if (( _rr == 4 )); then fleet_safe_unlock; return 0; fi   # no inbox -> nothing to drain
  if (( _rr == 3 )); then                                   # symlinked inbox -> fail closed
    # Do NOT unlink the public inbox by name: a racer could swap it between rotate's symlink
    # detection and the unlink, so we'd delete the wrong inode. Leave $f in place and refuse
    # to drain (enqueue also refuses a symlinked inbox). rotate did not rename, so no snapshot
    # exists to keep.
    fleet_log deliver-fail "$to" "inbox is a symlink; refusing to drain (left in place)" 2>/dev/null || true
    fleet_safe_unlock; return 1
  fi
  if (( _rr != 0 )); then                                   # 6 = swap detected / other error
    # KEEP whatever rotate left at $snap (it may hold data); never remove a snapshot after an
    # error. Fail closed.
    fleet_log deliver-fail "$to" "snapshot grab failed (rc=$_rr; concurrent inbox swap?); not drained; any data preserved in $snap" 2>/dev/null || true
    fleet_safe_unlock; return 1
  fi
  # Count pending. A jq/parse FAILURE (malformed data) is NOT zero-pending: RESTORE the
  # snapshot to the inbox and fail closed, rather than silently declaring the queue empty.
  local n _jqrc=0
  n="$(printf '%s' "$content" | jq -s '[.[]|select(.delivered==false)]|length' 2>/dev/null)" || _jqrc=$?
  if (( _jqrc != 0 )) || [[ ! "$n" =~ ^[0-9]+$ ]]; then
    _fleet_drain_restore "$snap" "$f" "$to" || true        # restore or KEEP snapshot; never lose mail
    fleet_log deliver-fail "$to" "inbox parse failed (malformed JSON?); mail preserved, not drained" 2>/dev/null || true
    fleet_safe_unlock; return 1
  fi
  local q; q="$(mktemp "$dir/.drain.XXXXXX" 2>/dev/null)" || { _fleet_drain_restore "$snap" "$f" "$to" || true; fleet_safe_unlock; return 1; }
  if [[ "${n:-0}" -gt 0 ]]; then
    # PER-LINE marking, stable by line position: inject each currently-undelivered line and
    # mark delivered=true ONLY for the lines whose fleet_inject returned 0. A failed inject
    # leaves that line undelivered so the NEXT drain retries it (at-least-once, never silent
    # loss); dedup stays stable by line position so a re-drain can't double-deliver.
    local -a lines=(); local line
    while IFS= read -r line; do lines+=("$line"); done <<<"$content"
    local idx delivered from text hops kind maxhop=0 ok_count=0 fail_count=0 deferred_count=0 dead_count=0
    : >"$q"
    for idx in "${!lines[@]}"; do
      line="${lines[$idx]}"
      [[ -z "$line" ]] && continue
      delivered="$(jq -r '.delivered // false' <<<"$line" 2>/dev/null)"
      if [[ "$delivered" == "true" ]]; then
        printf '%s\n' "$line" >>"$q"; continue
      fi
      from="$(jq -r '.from' <<<"$line")"; text="$(jq -r '.text' <<<"$line")"
      hops="$(jq -r '.hops // 1' <<<"$line")"; kind="$(jq -r '.kind // "msg"' <<<"$line")"
      # inject call site — routed through the transport seam when present (its tmux
      # branch IS fleet_inject; hooks that don't source transport.sh fall through
      # to fleet_inject directly, so behaviour is identical on both paths).
      local _rc=0
      if declare -F transport_enqueue >/dev/null 2>&1; then
        transport_enqueue "$to" "$from" "$text" "$hops" "$kind"; _rc=$?
      else
        fleet_inject "$to" "$from" "$text" "$hops" "$kind"; _rc=$?
      fi
      if (( _rc == 0 )); then
        (( hops > maxhop )) && maxhop="$hops"
        ok_count=$(( ok_count + 1 ))
        printf '%s\n' "$(jq -c '.delivered=true' <<<"$line")" >>"$q"
      elif (( _rc == 2 )); then
        # DEFERRED — the pane is mid-turn or the box holds real input (a human typing,
        # a prior un-submitted inject). Normal backpressure, NOT a failure: leave this
        # message queued, copy the rest unchanged, and bail WITHOUT bumping any failure
        # counter. The next drain retries the whole queue once the pane is idle/clear.
        deferred_count=$(( deferred_count + 1 ))
        printf '%s\n' "$line" >>"$q"
        local j
        for (( j=idx+1; j<${#lines[@]}; j++ )); do
          [[ -n "${lines[$j]}" ]] && printf '%s\n' "${lines[$j]}" >>"$q"
        done
        break
      else
        # GENUINE inject failure (rc 1). A message that can NEVER be injected (a poison
        # pill) must not block every message queued behind it forever — head-of-line
        # blocking is exactly what makes peers think mail was "lost" (observed: one long
        # message blocked 39 behind it for 8.7h). Track per-message attempts; after
        # FLEET_INJECT_MAX_ATTEMPTS genuine failures, DEAD-LETTER it (quarantine: mark
        # delivered+dead so it stops retrying, logged loudly) and CONTINUE past it so the
        # rest of the queue flows. Under the budget, keep it queued with a bumped attempt
        # count and break to retry the head next drain (transient failures recover first).
        local _att; _att="$(jq -r '.attempts // 0' <<<"$line" 2>/dev/null)"; [[ "$_att" =~ ^[0-9]+$ ]] || _att=0
        _att=$(( _att + 1 ))
        if (( _att >= ${FLEET_INJECT_MAX_ATTEMPTS:-5} )); then
          dead_count=$(( dead_count + 1 ))
          printf '%s\n' "$(jq -c --argjson a "$_att" '.attempts=$a | .delivered=true | .dead=true' <<<"$line")" >>"$q"
          fleet_log deadletter "$to" "quarantined undeliverable msg from $from after $_att attempts (kind=$kind len=${#text})" 2>/dev/null || true
          continue
        fi
        fail_count=$(( fail_count + 1 ))
        printf '%s\n' "$(jq -c --argjson a "$_att" '.attempts=$a' <<<"$line")" >>"$q"
        local j
        for (( j=idx+1; j<${#lines[@]}; j++ )); do
          [[ -n "${lines[$j]}" ]] && printf '%s\n' "${lines[$j]}" >>"$q"
        done
        break
      fi
    done
    # COMMIT: write the processed queue to the inbox (absent post-rotate -> created no-follow;
    # a symlink an attacker replanted at $f is replaced by rename, a dir/special/foreign dest
    # refused). A FAILED commit must NOT read as a clean drain — the delivered-marks would be
    # lost and the next drain would re-inject — so RESTORE the snapshot (never lose mail) and
    # fail closed.
    local _wb=0; fleet_safe_write "$f" < "$q" || _wb=$?
    rm -f "$q" 2>/dev/null || true
    if (( _wb != 0 )); then
      # commit refused: RESTORE the snapshot (or KEEP it if restore also fails); never lose mail.
      _fleet_drain_restore "$snap" "$f" "$to" || true
      fleet_log deliver-fail "$to" "commit refused (unsafe inbox or safe-IO down); marks not persisted" 2>/dev/null || true
      fleet_safe_unlock
      return 1
    fi
    rm -f "$snap" 2>/dev/null || true   # commit succeeded: mail is safe at $f, drop the snapshot
    if (( ok_count > 0 )); then
      # record the deepest hop delivered so this agent's reply inherits hop+1
      fleet_state_jq "$to" --argjson h "$maxhop" '.last_inbound_hops=$h' >/dev/null 2>&1 || true
      fleet_log deliver "$to" "$ok_count message(s)"
    fi
    # A dead-letter unblocked the queue: record it on the recipient's state so it is
    # visible (fleet doctor / status), not just buried in the event log.
    if (( dead_count > 0 )); then
      local now2; now2="$(date +%s)"
      fleet_state_jq "$to" --argjson n "$dead_count" --argjson t "$now2" \
        '.dead_letters = ((.dead_letters // 0) + $n) | .last_dead_letter = $t' >/dev/null 2>&1 || true
    fi
    # Self-heal: a fully-clean drain (something delivered, nothing failed) clears
    # the failure counter so fleet doctor goes quiet once mail flows again.
    if (( ok_count > 0 && fail_count == 0 )); then
      fleet_state_jq "$to" '.inject_failures = 0' >/dev/null 2>&1 || true
    fi
    if (( fail_count > 0 )); then
      # Persisted, visible failure counter — fleet doctor reads this and screams.
      local now; now="$(date +%s)"
      fleet_state_jq "$to" --argjson n "$fail_count" --argjson t "$now" \
        '.inject_failures = ((.inject_failures // 0) + $n) | .last_drain_attempt = $t' >/dev/null 2>&1 || true
      fleet_log deliver-fail "$to" "$fail_count message(s) left queued (inject unverified)"
      fleet_safe_unlock
      return 1
    fi
    if (( deferred_count > 0 )); then
      # Deferred (box occupied by real input) — NOT a failure: mail stays queued, no
      # counter bump, quiet log. The next drain delivers once the prompt is clear.
      fleet_log deliver-defer "$to" "$deferred_count message(s) deferred (prompt busy)" 2>/dev/null || true
      fleet_safe_unlock
      return 1
    fi
  else
    # Nothing undelivered: RESTORE the snapshot unchanged so delivered-history lines survive.
    # On restore failure the snapshot is KEPT (never removed) and the drain fails closed —
    # losing delivered-history is still data loss.
    if ! _fleet_drain_restore "$snap" "$f" "$to"; then
      rm -f "$q" 2>/dev/null || true
      fleet_safe_unlock
      return 1
    fi
  fi
  # Only $q (scratch) is dropped here. $snap is NEVER removed on this line: by now it was
  # either committed-away (rm'd on success), renamed back by restore, or deliberately kept on
  # a restore failure above. Removing it here could delete the sole surviving copy of mail.
  rm -f "$q" 2>/dev/null || true
  fleet_safe_unlock
  return 0
}

# Build the per-child priming prompt that teaches a worker its identity, its
# peers, and how to use the mailbox. Requires the manifest to be loaded.
fleet_peer_primer() {
  local id="$1" me_cwd peers="" c
  me_cwd="$(fleet_child_get "$id" cwd ".")"
  for c in "${CHILD_IDS[@]:-}"; do
    [[ -z "$c" || "$c" == "$id" ]] && continue
    peers+="  - ${c}  (expert on $(fleet_child_get "$c" cwd "$c"))"$'\n'
  done
  [[ -z "$peers" ]] && peers="  (no peers configured)"$'\n'
  cat <<EOF
You are "$id", one member of a fleet of coding-agent sessions. Each member is the
resident expert on its own repo and holds deep context on it. You are the expert
on: ${me_cwd}.

Fleet-wide ownership rule:
One writer per repo. Claude lanes are normally the resident writers. Codex twin
lanes are adversarial read-only pair programmers and fail-over standbys unless a
fleet handoff explicitly promotes them to takeover writer. Read-only twins should
question, test assumptions, and propose concrete fixes, but not edit the working
tree.

Working doctrine:
- Treat every non-trivial claim as a conjecture. Confidence is earned by
  surviving checks, tests, and genuine attempts to refute it.
- Prefer falsifying evidence over agreement. Ask what would make the current
  approach wrong, incomplete, insecure, or too brittle.
- Before calling substantial work "done", get a peer or opposite-provider twin to
  challenge it, or clearly record why that refutation pass did not happen.
- Report findings with evidence: file path, command/result, failure mode, and
  the smallest concrete mitigation. Treat an adversary's finding as a lead until
  verified against ground truth.
- Verify-then-record: update durable state only after checking the repo, not from
  memory or transcript confidence alone.

Durable handoff requirement:
$(_fleet_resume_contract 2>/dev/null || cat <<'FALLBACK'
Maintain a repo-local RESUME.md as the durable handoff record for this worker.
Update it after each meaningful turn and before going idle with enough detail
that another agent can take over without your private transcript.
FALLBACK
)

Your peers — consult them when a question is genuinely about THEIR area:
${peers}
To reach a peer (run in Bash):
  - Ask a question:   fleet ask <peer-id> "your question"
  - Send a heads-up:  fleet send <peer-id> "info"

How \`ask\` works: it does NOT interrupt the peer's live session. The fleet spins
up a provider-native off-thread copy/resume of that peer's current context and
answers your question. The answer comes back to YOU — a one-line summary appears
in your thread, and the full reply is saved in your inbox. Read it with:
fleet inbox

How incoming messages work: you do NOT answer peers' questions yourself. When a
peer asks YOU something, the fleet answers it from a provider-native off-thread
copy/resume of your context; you'll just see a brief "no action needed" note. A
"fleet send" from a peer is a short FYI — act on it only if it actually affects
your current work. Nothing ever hijacks your thread with someone else's question.
Read anything queued any time with:  fleet inbox

There is also a logical "supervisor" pair coordinating the fleet. Escalate to it
(blockers, cross-cutting decisions, "who owns X?") with:
fleet pair-send supervisor "..."

Keep cross-agent messages short and specific, and prefer asking the right peer
over guessing about a repo that isn't yours. Notes are tagged with a hop counter
(N/MAX) that caps how deep a chain can go before the fleet refuses further
messages.
EOF
  # Optional workspace-supplied context (architecture, ownership rules, etc.),
  # appended verbatim so the generic tool stays domain-agnostic.
  if [[ -f "$STATE_DIR/primer.md" ]]; then
    printf '\n=== Shared workspace context ===\n'
    cat "$STATE_DIR/primer.md"
  fi
}
