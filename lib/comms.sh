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

FLEET_MSG_TAG="${FLEET_MSG_TAG:-fleet msg}"

fleet_inbox_file() { printf '%s/inbox/%s.jsonl\n' "$STATE_DIR" "$1"; }

# enqueue a message as undelivered
fleet_enqueue() {
  local to="$1" from="$2" text="$3" f ts
  f="$(fleet_inbox_file "$to")"; mkdir -p "$(dirname "$f")"
  ts="$(date +%s)"
  exec 9>"$f.lock"; flock 9 2>/dev/null || true
  jq -nc --argjson ts "$ts" --arg from "$from" --arg to "$to" --arg text "$text" \
    '{ts:$ts, from:$from, to:$to, text:$text, delivered:false}' >>"$f"
  flock -u 9 2>/dev/null || true; exec 9>&-
}

# type one message into a target's tmux prompt and submit it
fleet_inject() {
  local to="$1" from="$2" text="$3"
  text="$(printf '%s' "$text" | tr '\n' ' ')"   # single line — Enter submits
  tmux send-keys -t "$FLEET_TMUX_SESSION:$to" -l "[$FLEET_MSG_TAG from $from] $text" 2>/dev/null || return 1
  tmux send-keys -t "$FLEET_TMUX_SESSION:$to" Enter 2>/dev/null || return 1
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
    local line from text
    while IFS= read -r line; do
      from="$(jq -r '.from' <<<"$line")"; text="$(jq -r '.text' <<<"$line")"
      fleet_inject "$to" "$from" "$text" || break
    done < <(jq -c 'select(.delivered==false)' "$f")
    jq -c '.delivered=true' "$f" >"$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
    fleet_log deliver "$to" "$n message(s)"
  fi
  flock -u 9 2>/dev/null || true; exec 9>&-
  return 0
}

# Ask a peer a question via an ephemeral expert session in its repo (does NOT
# touch the peer's main interactive session). Answer is routed back async.
#   fleet_ask <to> <from> <question>
fleet_ask() {
  local to="$1" from="$2" q="$3" rel cwd
  rel="$(fleet_child_get "$to" cwd "")"
  if [[ -n "$rel" ]]; then cwd="$WORKSPACE/$rel"; [[ "$rel" == /* ]] && cwd="$rel"
  else cwd="$(fleet_state_get "$to" '.cwd' "$WORKSPACE")"; fi
  [[ -d "$cwd" ]] || { warn "ask: don't know which repo '$to' is — add it to fleet.toml"; return 1; }
  fleet_tmux_ensure_session
  tmux new-window -t "$FLEET_TMUX_SESSION" -n "ask:$to" -c "$cwd" -e "FLEET_NO_REPORT=1" \
    "$TOOL_ROOT/lib/responder.sh" "$to" "$from" "$q"
  fleet_log ask "$to" "from=$from"
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
resident expert on its own R2 sub-repo and holds deep context on it. You are the
expert on: ${me_cwd}.

Your peers — consult them when a question is genuinely about THEIR area:
${peers}
Two ways to reach a peer (run in Bash):
  - Ask without interrupting them (PREFERRED for questions):
        fleet ask <peer-id> "your question"
    This spins up a fresh expert session in the peer's repo, which answers from
    that codebase and routes the reply back to you — the peer's own session is
    never disturbed. The answer arrives later as a "[${FLEET_MSG_TAG} from <id>]" line.
  - Notify/nudge their live session directly (use sparingly):
        fleet send <peer-id> "a heads-up"

Messages and answers arrive in your input prefixed: [${FLEET_MSG_TAG} from <id>] ...
Read queued mail anytime with:  fleet inbox

REPLY ROUTING (a firm rule, not a suggestion):
  - Every message you receive names its sender in the "[${FLEET_MSG_TAG} from <id>]"
    prefix. If it asks you anything, you MUST route your answer back to THAT exact
    id:  fleet send <that-id> "your answer".
  - A question you leave unanswered is a dropped message — the asker is blocked
    waiting on you. Always close the loop, even if the answer is "I don't know" or
    "that's outside <your-repo>; try <other-peer>".
  - When you ask a peer something, expect their reply to arrive the same way (a
    later "[${FLEET_MSG_TAG} from <id>]" line); fold it into what you were doing.

Keep cross-agent messages short and specific. Avoid loops: only reply when you are
answering a question or adding genuinely new information — acknowledgements like
"thanks" do not need to be sent. Prefer asking the right peer over guessing about a
repo that isn't yours.
EOF
}
