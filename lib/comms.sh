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
fleet_inject() {
  local to="$1" from="$2" text="$3" hops="${4:-1}" kind="${5:-msg}"
  # never keystroke-inject a claude-bg worker — its window hosts a bash controller,
  # not a TUI; delivery there goes through the controller's programmatic turns.
  [[ "$(fleet_state_get "$to" '.faculty' '')" == "claude-bg" ]] && return 1
  text="$(printf '%s' "$text" | tr '\n' ' ')"   # single line — Enter submits
  local tag="fleet msg"; [[ "$kind" == "ask" ]] && tag="fleet ask"
  local full
  full="[$tag from $from · hop $hops/$(fleet_max_hops)] $text"
  local tgt="$FLEET_TMUX_SESSION:$to" i=0 n=${#full}
  while (( i < n )); do
    fleet_tmux send-keys -t "$tgt" -l "${full:i:FLEET_INJECT_CHUNK}" 2>/dev/null || return 1
    i=$(( i + FLEET_INJECT_CHUNK ))
    (( i < n )) && sleep 0.03
  done
  sleep "$FLEET_INJECT_DELAY"
  fleet_tmux send-keys -t "$tgt" Enter 2>/dev/null || return 1
  # A flaky Enter can leave the message sitting UNSUBMITTED in the TUI input box
  # (Roy observed messages waiting at the prompt for a manual Enter) — the single
  # Enter raced the TUI's render or the pane was briefly busy. Verify: if the
  # message's tail is still in the bottom input area, the Enter didn't land —
  # re-send it. A spurious extra Enter at an empty prompt is a harmless no-op in
  # Claude Code, so erring toward re-sending is safe. Disable with FLEET_INJECT_VERIFY=off.
  [[ "${FLEET_INJECT_VERIFY:-on}" == "off" ]] && return 0
  local marker="${full: -32}" try pane
  for try in 1 2 3 4; do
    sleep 0.3
    pane="$(fleet_tmux capture-pane -p -t "$tgt" 2>/dev/null | tail -n 2)"
    case "$pane" in *"$marker"*) ;; *) return 0 ;; esac   # tail gone from input → submitted
    fleet_tmux send-keys -t "$tgt" Enter 2>/dev/null || return 1
  done
  # Verify loop exhausted: the message's tail is STILL in the input box after 4
  # re-Enters — the inject did NOT land. Report failure so the caller leaves the
  # line undelivered (at-least-once retry on the next drain) instead of the old
  # optimistic `return 0` that silently dropped the line as "delivered".
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
    local idx delivered from text hops kind maxhop=0 ok_count=0 fail_count=0
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
      local _injected=0
      if declare -F transport_enqueue >/dev/null 2>&1; then
        transport_enqueue "$to" "$from" "$text" "$hops" "$kind" && _injected=1
      else
        fleet_inject "$to" "$from" "$text" "$hops" "$kind" && _injected=1
      fi
      if (( _injected == 1 )); then
        (( hops > maxhop )) && maxhop="$hops"
        ok_count=$(( ok_count + 1 ))
        printf '%s\n' "$(jq -c '.delivered=true' <<<"$line")" >>"$f.tmp"
      else
        # Leave undelivered for the next drain. Stop trying further lines this
        # pass (the pane is likely wedged/busy); they too stay queued.
        fail_count=$(( fail_count + 1 ))
        printf '%s\n' "$line" >>"$f.tmp"
        # copy the remaining lines verbatim (still undelivered) and bail.
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
