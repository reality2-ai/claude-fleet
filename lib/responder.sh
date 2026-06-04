#!/usr/bin/env bash
# responder.sh — an ephemeral "expert" that answers a peer's question from a
# repo's context WITHOUT disturbing that repo's main interactive session.
#
# Launched by `fleet ask` in a transient tmux window whose cwd is the target
# repo. It runs a headless `claude -p` (a fresh session that sees the codebase
# but not the main session's in-progress conversation), then routes the answer
# back to the asker via `fleet send`. Exits when done (window closes).
#
# Usage: responder.sh <to> <from> <question>
set -uo pipefail
to="$1"; from="$2"; q="$3"
export FLEET_NO_REPORT=1   # this ephemeral session must not self-report

primer="You are \"$to\", the resident expert on the repository at $PWD. A peer agent named \"$from\" has asked you a question. Answer concisely and specifically using ONLY this codebase; cite file paths where useful. If the question falls outside this repo, say so in one line and suggest who might know."

ans="$("${FLEET_CLAUDE_BIN:-claude}" -p --append-system-prompt "$primer" "$q" 2>/dev/null)"
ans="${ans//$'\n'/ }"          # single line for delivery
# High safety cap (full replies are delivered via keystroke-chunked injection, so
# this only bounds pathological output) — trimmed at a WORD boundary with a
# visible marker, never a silent mid-sentence cut.
MAXLEN="${FLEET_ANSWER_MAX:-16000}"
if [ "${#ans}" -gt "$MAXLEN" ]; then
  ans="${ans:0:$MAXLEN}"; ans="${ans% *}"
  ans="$ans … [reply truncated — ask a narrower question for the rest]"
fi
[ -z "$ans" ] && ans="(no answer produced)"

# route the answer back to the original asker, attributed to the responding expert
fleet send "$from" --from "$to" "re «${q:0:60}»: $ans"
