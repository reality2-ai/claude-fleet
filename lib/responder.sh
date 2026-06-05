#!/usr/bin/env bash
# responder.sh — forked-context responder for `fleet ask`.
#
# Launched in a transient tmux window in the TARGET repo. It resumes a FORK of
# the target's live session — its real working context — headlessly, answers the
# peer's question WITHOUT touching the target's live thread, then:
#   1. stores the full answer in the ASKER's inbox (read with `fleet inbox`),
#   2. drops a one-line summary into the asker's thread,
#   3. drops a brief "no action needed" FYI into the target's thread.
#
# Usage: responder.sh <to> <from> <question> <hop>
# shellcheck source-path=SCRIPTDIR
set -uo pipefail

to="${1:?responder: <to> required}"
from="${2:?responder: <from> required}"
q="${3:?responder: <question> required}"
hop="${4:-1}"

: "${TOOL_ROOT:?responder: TOOL_ROOT must be set}"
# shellcheck source=common.sh
source "$TOOL_ROOT/lib/common.sh"
# shellcheck source=registry.sh
source "$TOOL_ROOT/lib/registry.sh"
# shellcheck source=tmux.sh
source "$TOOL_ROOT/lib/tmux.sh"
# shellcheck source=comms.sh
source "$TOOL_ROOT/lib/comms.sh"
fleet_load_paths

export FLEET_NO_REPORT=1   # the ephemeral fork must never self-report

# A short, single-line form of the question for the notes.
qshort="$q"; [ "${#qshort}" -gt 60 ] && qshort="${qshort:0:60}…"

# Resume a FORK of the target's live session (new id; the live thread is untouched
# and keeps its own id). If there's no recorded session, fall back to a fresh
# expert that at least sees the repo.
sid=""; [[ -f "$RUN_DIR/$to.session" ]] && sid="$(<"$RUN_DIR/$to.session")"

primer="You are \"$to\", answering a question from a peer agent \"$from\" in the same fleet. You have been resumed from a fork of your own working session, so you carry your current context. Answer ONLY the question — concisely and specifically, citing file paths where useful. Do NOT start new work, make edits, or message other agents; just answer. If it's outside your repo or expertise, say so in one line and name who might know."

ans=""
if [[ -n "$sid" ]]; then
  ans="$("${FLEET_CLAUDE_BIN:-claude}" -p --resume "$sid" --fork-session \
          --append-system-prompt "$primer" "$q" 2>/dev/null)"
else
  ans="$("${FLEET_CLAUDE_BIN:-claude}" -p --append-system-prompt "$primer" "$q" 2>/dev/null)"
fi

ans="${ans//$'\n'/ }"                       # single line for delivery
maxlen="${FLEET_ANSWER_MAX:-16000}"
if [ "${#ans}" -gt "$maxlen" ]; then
  ans="${ans:0:$maxlen}"; ans="${ans% *} … [reply truncated — ask a narrower question for the rest]"
fi
[ -z "$ans" ] && ans="(no answer produced)"

# A brief preview of the answer for the asker's thread.
brief="$ans"; [ "${#brief}" -gt 160 ] && { brief="${brief:0:160}"; brief="${brief% *}…"; }

# 1. full answer → asker's inbox, stored (not injected): read with `fleet inbox`
fleet_enqueue "$from" "$to" "$ans" "$hop" answer false
# 2. one-line summary → asker's thread (when it's next idle)
fleet_notify "$from" "$to" "answered «$qshort»: $brief  (full reply: fleet inbox $from)" "$hop"
# 3. brief, no-action FYI → target's thread (when it's next idle)
fleet_notify "$to" "fleet" "peer '$from' consulted you about «$qshort» — answered from a forked copy of your context; no action needed." "$hop"
fleet_log answered "$to" "forked reply → $from (hop $hop)"
