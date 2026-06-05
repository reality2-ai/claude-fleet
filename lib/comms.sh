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

# enqueue a message as undelivered, carrying its hop depth and kind (ask|msg)
fleet_enqueue() {
  local to="$1" from="$2" text="$3" hops="${4:-1}" kind="${5:-msg}" f ts
  f="$(fleet_inbox_file "$to")"; mkdir -p "$(dirname "$f")"
  ts="$(date +%s)"
  exec 9>"$f.lock"; flock 9 2>/dev/null || true
  jq -nc --argjson ts "$ts" --arg from "$from" --arg to "$to" --arg text "$text" --argjson hops "$hops" --arg kind "$kind" \
    '{ts:$ts, from:$from, to:$to, text:$text, hops:$hops, kind:$kind, delivered:false}' >>"$f"
  flock -u 9 2>/dev/null || true; exec 9>&-
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

# Deliver one message into a target's tmux prompt and submit it. The full text is
# typed in small keystroke chunks (gentle on a full-screen TUI — avoids the
# reflow/blank a single huge keystroke blast causes), then a brief settle pause,
# then ONE Enter — so even a long reply arrives complete, as a single turn.
FLEET_INJECT_DELAY="${FLEET_INJECT_DELAY:-0.2}"
FLEET_INJECT_CHUNK="${FLEET_INJECT_CHUNK:-500}"
fleet_inject() {
  local to="$1" from="$2" text="$3" hops="${4:-1}" kind="${5:-msg}"
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
}

# Deliver any undelivered mail to <to>. Returns 0 if delivered (or nothing to
# do), 1 if it had to leave mail queued (target offline or busy).
#   fleet_drain_inbox <to> [force]
fleet_drain_inbox() {
  local to="$1" force="${2:-}" f
  f="$(fleet_inbox_file "$to")"
  [[ -f "$f" ]] || return 0
  fleet_tmux_has_window "$to" || return 1                   # offline → keep queued
  if [[ "$force" != "force" ]]; then
    [[ "$(fleet_state_get "$to" '.ready' false)" == "true" ]] || return 1   # busy → keep queued
  fi
  exec 9>"$f.lock"; flock 9 2>/dev/null || true
  local n; n="$(jq -s '[.[]|select(.delivered==false)]|length' "$f" 2>/dev/null || echo 0)"
  if [[ "${n:-0}" -gt 0 ]]; then
    local line from text hops kind maxhop=0
    while IFS= read -r line; do
      from="$(jq -r '.from' <<<"$line")"; text="$(jq -r '.text' <<<"$line")"
      hops="$(jq -r '.hops // 1' <<<"$line")"; kind="$(jq -r '.kind // "msg"' <<<"$line")"
      fleet_inject "$to" "$from" "$text" "$hops" "$kind" || break
      (( hops > maxhop )) && maxhop="$hops"
    done < <(jq -c 'select(.delivered==false)' "$f")
    jq -c '.delivered=true' "$f" >"$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
    # record the deepest hop delivered so this agent's reply inherits hop+1
    fleet_state_jq "$to" --argjson h "$maxhop" '.last_inbound_hops=$h' >/dev/null 2>&1 || true
    fleet_log deliver "$to" "$n message(s)"
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
You are "$id", one member of a fleet of Claude Code sessions. Each member is the
resident expert on its own repo and holds deep context on it. You are the expert
on: ${me_cwd}.

Your peers — consult them when a question is genuinely about THEIR area:
${peers}
To reach a peer (run in Bash):
  - Ask a question (you expect an answer back):
        fleet ask <peer-id> "your question"
  - Tell them something (no answer needed):
        fleet send <peer-id> "a heads-up"

How it works: the message is delivered into the PEER'S OWN session as a normal
turn — it appears in their thread, they answer there (visible to the human
operator), and their reply comes back to you the same way. There is no hidden
side-channel; everything happens in the actual sessions.

There is also a "supervisor" coordinating the fleet. Escalate to it (blockers,
cross-cutting decisions, "who owns X?") with:  fleet send supervisor "..."

Messages arrive in your input prefixed:
    [fleet ask from <id> · hop N/MAX] ...   ← a question; answer it
    [fleet msg from <id> · hop N/MAX] ...   ← info; reply only if useful
Answer in your normal response (the human can see it), THEN route your answer back
to the asker:  fleet send <that-id> "your answer". The hop number is the
conversation depth; at MAX, don't reply further (the fleet refuses it) — wrap up or
escalate to the supervisor. Read queued mail anytime with:  fleet inbox

REPLY ROUTING (a firm rule):
  - A "[fleet ask from <id>]" you leave unanswered is a dropped message — the
    asker is blocked on you. Always close the loop, even if it's "I don't know" or
    "that's outside <your-repo>; ask <other-peer>".
  - Keep cross-agent messages short and specific. Avoid loops: only reply when you
    are answering a question or adding genuinely new information — a bare "thanks"
    needs no message. Prefer asking the right peer over guessing about a repo that
    isn't yours.
EOF
  # Optional workspace-supplied context (architecture, ownership rules, etc.),
  # appended verbatim so the generic tool stays domain-agnostic.
  if [[ -f "$STATE_DIR/primer.md" ]]; then
    printf '\n=== Shared workspace context ===\n'
    cat "$STATE_DIR/primer.md"
  fi
}
