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

fleet_inbox_file() { printf '%s/inbox/%s.jsonl\n' "$STATE_DIR" "$1"; }

# enqueue a message carrying its hop depth and kind (ask|msg|fyi|answer).
# notify=true (default) → pending injection into the thread; notify=false → stored
# as a read-only record (e.g. a full answer the asker reads via `fleet inbox`).
fleet_enqueue() {
  local to="$1" from="$2" text="$3" hops="${4:-1}" kind="${5:-msg}" notify="${6:-true}" f ts delivered=false
  [[ "$notify" == "false" ]] && delivered=true
  f="$(fleet_inbox_file "$to")"; mkdir -p "$(dirname "$f")"
  ts="$(date +%s)"
  exec 9>"$f.lock"; flock 9 2>/dev/null || true
  jq -nc --argjson ts "$ts" --arg from "$from" --arg to "$to" --arg text "$text" --argjson hops "$hops" --arg kind "$kind" --argjson delivered "$delivered" \
    '{ts:$ts, from:$from, to:$to, text:$text, hops:$hops, kind:$kind, delivered:$delivered}' >>"$f"
  flock -u 9 2>/dev/null || true; exec 9>&-
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

# Is <to>'s pane sitting at its idle prompt (NOT mid-task)? Conservative by
# construction: returns 0 (idle) ONLY when the pane tail shows the empty input
# box AND shows no "working" signature; on any doubt (no window, capture failed,
# any active-work marker) it returns non-zero so a mid-task worker is NEVER
# injected into / unstuck. Reused by the .ready TTL unstick (fleet_reconcile) and
# fleet doctor. Disable the whole idle-gate with FLEET_PANE_IDLE_CHECK=off (then
# treats every live pane as idle — only for tests/degraded hosts).
#   fleet_pane_is_idle <to>
fleet_pane_is_idle() {
  local to="$1"
  [[ "${FLEET_PANE_IDLE_CHECK:-on}" == "off" ]] && return 0
  fleet_tmux_has_window "$to" 2>/dev/null || return 1
  local tgt="$FLEET_TMUX_SESSION:$to" pane
  pane="$(fleet_tmux capture-pane -p -t "$tgt" 2>/dev/null)" || return 1
  [[ -n "$pane" ]] || return 1
  local tail; tail="$(printf '%s\n' "$pane" | grep -vE '^[[:space:]]*$' | tail -n 12)"
  # WORKING signatures Claude Code surfaces while a turn is in flight — if ANY of
  # these are present we are NOT idle (err toward "busy").
  local working='esc to interrupt|to interrupt\)|[Ee]sc to|✶|✻|✽|·\s*[0-9]+\s*tokens|Running…|Thinking…|Working…|[Ww]aiting…|tool use|⏵⏵|Compacting'
  printf '%s\n' "$tail" | grep -qE "$working" && return 1
  # IDLE signatures: the empty Claude Code input box / prompt. Require a positive
  # match so an unknown/garbled pane is treated as busy, never idle. (`?` escaped
  # and POSIX classes used so the pattern is portable across grep variants.)
  local promptbox='│ >|^[[:space:]]*>[[:space:]]*$|Try "|\? for shortcuts|╰─|╭─'
  printf '%s\n' "$tail" | grep -qE "$promptbox" && return 0
  return 1
}

# Wait briefly for <to>'s pane to be genuinely idle (at an empty prompt, not
# mid-turn), polling fleet_pane_is_idle up to <budget> times (~0.2s each). Returns
# 0 as soon as it is idle, 1 if still busy after the budget. This absorbs the brief
# render race right after a turn ends (the Stop-hook drain fires the instant the turn
# completes, a beat before the input box has fully redrawn) WITHOUT typing into a
# pane that is still working. Honours FLEET_PANE_IDLE_CHECK=off via fleet_pane_is_idle
# (which then reports every live pane idle, returning 0 on the first poll).
#   fleet_wait_idle <to> [budget]
fleet_wait_idle() {
  local to="$1" budget="${2:-3}" i
  [[ "$budget" =~ ^[0-9]+$ ]] || budget=3
  for (( i=0; i<budget; i++ )); do
    fleet_pane_is_idle "$to" && return 0
    sleep "${FLEET_INJECT_IDLE_POLL:-0.2}"
  done
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
# escapes (-e) so dim ghost text isn't mistaken for content; take the LAST ❯ line
# (history lines also have ❯). Conservative: no window / capture failure → "not busy",
# so a missed read errs toward delivering, never toward never-delivering.
fleet_input_busy() {
  local to="$1" region line
  region="$(fleet_tmux capture-pane -e -p -t "$FLEET_TMUX_SESSION:$to" 2>/dev/null | tail -n 6)" || return 1
  line="$(printf '%s\n' "$region" | grep -aF '❯' | tail -n1)"
  [[ -z "$line" ]] && return 1
  _fleet_line_has_real_input "$line"
}

fleet_inject() {
  local to="$1" from="$2" text="$3" hops="${4:-1}" kind="${5:-msg}"
  # never keystroke-inject a claude-bg worker — its window hosts a bash controller,
  # not a TUI; delivery there goes through the controller's programmatic turns.
  [[ "$(fleet_state_get "$to" '.faculty' '')" == "claude-bg" ]] && return 1

  # --- DEFER GATE (rc 2 = backpressure, NOT failure — leaves the message queued
  # for the next drain). Two independent reasons never to type right now:
  #
  #  (a) MID-TURN pane (empty box, Claude still working). Enter sent into a working
  #      pane is silently SWALLOWED — the text lands in the box but never submits
  #      until the turn ends, so it sits at the prompt waiting for a manual Enter
  #      (the "messages stuck waiting for enter" bug). The .ready state flag the
  #      drain trusts goes stale the instant the worker picks up new work, so we
  #      must check the LIVE pane, not the flag. fleet_wait_idle waits out the brief
  #      post-turn render race so the Stop-hook drain still delivers immediately.
  #  (b) BUSY box — real, non-dim input already present (a human mid-typing or a
  #      prior un-submitted inject). Typing onto it concatenates + garbles.
  if ! fleet_wait_idle "$to" "${FLEET_INJECT_IDLE_WAIT:-3}"; then return 2; fi
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
  sleep "$FLEET_INJECT_DELAY"
  fleet_tmux send-keys -t "$tgt" Enter 2>/dev/null || return 1

  # --- SUBMIT VERIFY (multi-line / paste-placeholder safe). After a successful
  # submit the input box is EMPTY again, so reuse the dim-aware reader: if real,
  # non-dim input still SURVIVES, the Enter didn't land (raced the render, or the
  # pane briefly busied) — re-send it. A spurious Enter at an empty prompt is a
  # harmless no-op. (The old tail-grep for the message's tail text broke on
  # multi-line wrap and on paste placeholders; the empty-box test handles both.)
  # Disable with FLEET_INJECT_VERIFY=off.
  [[ "${FLEET_INJECT_VERIFY:-on}" == "off" ]] && return 0
  local try
  for try in 1 2 3 4; do
    sleep 0.3
    fleet_input_busy "$to" || return 0          # box clear → submitted
    fleet_tmux send-keys -t "$tgt" Enter 2>/dev/null || return 1
  done
  # Verify exhausted: real input still in the box after 4 re-Enters — the inject did
  # not land cleanly. Clear it (C-u kills the line) so we never leave a stuck/garbled
  # fragment, then report failure → the line stays queued for a clean at-least-once
  # retry on the next drain (when the box is empty again).
  fleet_tmux send-keys -t "$tgt" C-u 2>/dev/null || true
  return 1
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

# Deliver any undelivered mail to <to>. Returns 0 if delivered (or nothing to
# do), 1 if it had to leave mail queued (target offline or busy).
#   fleet_drain_inbox <to> [force]
fleet_drain_inbox() {
  local to="$1" force="${2:-}" f
  f="$(fleet_inbox_file "$to")"
  [[ -f "$f" ]] || return 0
  # claude-bg workers are driven by their own controller (programmatic -p turns); the
  # cli-tmux drain must NOT type into the controller's bash window. Leave mail for it.
  [[ "$(fleet_state_get "$to" '.faculty' '')" == "claude-bg" ]] && return 1
  fleet_tmux_has_window "$to" || return 1                   # offline → keep queued
  if [[ "$force" != "force" ]]; then
    [[ "$(fleet_state_get "$to" '.ready' false)" == "true" ]] || return 1   # busy → keep queued
  fi
  exec 9>"$f.lock"; flock 9 2>/dev/null || true
  local n; n="$(jq -s '[.[]|select(.delivered==false)]|length' "$f" 2>/dev/null || echo 0)"
  if [[ "${n:-0}" -gt 0 ]]; then
    # PER-LINE marking, stable by line position: read every line, inject each
    # currently-undelivered one, and mark delivered=true ONLY for the lines whose
    # fleet_inject returned 0. A failed inject leaves that line undelivered so the
    # NEXT drain retries it (at-least-once, never silent loss); dedup stays stable
    # by line position so a re-drain can't double-deliver a line already consumed.
    local -a lines=(); local line
    while IFS= read -r line; do lines+=("$line"); done <"$f"
    local idx delivered from text hops kind maxhop=0 ok_count=0 fail_count=0 deferred_count=0
    : >"$f.tmp"
    for idx in "${!lines[@]}"; do
      line="${lines[$idx]}"
      [[ -z "$line" ]] && continue
      delivered="$(jq -r '.delivered // false' <<<"$line" 2>/dev/null)"
      if [[ "$delivered" == "true" ]]; then
        printf '%s\n' "$line" >>"$f.tmp"; continue
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
        printf '%s\n' "$(jq -c '.delivered=true' <<<"$line")" >>"$f.tmp"
      else
        # Not delivered. rc==2 = DEFERRED (box has real input — a human typing or a
        # stuck inject): normal backpressure, NOT a failure — leave queued, copy the
        # rest, bail WITHOUT bumping the failure counter (doctor stays quiet; the next
        # drain retries once the box clears). Any other rc = a genuine inject failure.
        if (( _rc == 2 )); then deferred_count=$(( deferred_count + 1 ))
        else fail_count=$(( fail_count + 1 )); fi
        printf '%s\n' "$line" >>"$f.tmp"
        local j
        for (( j=idx+1; j<${#lines[@]}; j++ )); do
          [[ -n "${lines[$j]}" ]] && printf '%s\n' "${lines[$j]}" >>"$f.tmp"
        done
        break
      fi
    done
    mv "$f.tmp" "$f" 2>/dev/null || rm -f "$f.tmp"
    if (( ok_count > 0 )); then
      # record the deepest hop delivered so this agent's reply inherits hop+1
      fleet_state_jq "$to" --argjson h "$maxhop" '.last_inbound_hops=$h' >/dev/null 2>&1 || true
      fleet_log deliver "$to" "$ok_count message(s)"
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
      flock -u 9 2>/dev/null || true; exec 9>&-
      return 1
    fi
    if (( deferred_count > 0 )); then
      # Deferred (box occupied by real input) — NOT a failure: mail stays queued, no
      # counter bump, quiet log. The next drain delivers once the prompt is clear.
      fleet_log deliver-defer "$to" "$deferred_count message(s) deferred (prompt busy)" 2>/dev/null || true
      flock -u 9 2>/dev/null || true; exec 9>&-
      return 1
    fi
  fi
  flock -u 9 2>/dev/null || true; exec 9>&-
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
