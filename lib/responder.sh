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
# shellcheck source=manifest.sh
source "$TOOL_ROOT/lib/manifest.sh"
# shellcheck source=provider.sh
source "$TOOL_ROOT/lib/provider.sh"
# shellcheck source=tmux.sh
source "$TOOL_ROOT/lib/tmux.sh"
# shellcheck source=comms.sh
source "$TOOL_ROOT/lib/comms.sh"
# shellcheck source=transport.sh
source "$TOOL_ROOT/lib/transport.sh"
# shellcheck source=faculty.sh
source "$TOOL_ROOT/lib/faculty.sh"
fleet_load_paths
[[ -f "$MANIFEST" ]] && fleet_manifest_load "$MANIFEST"

export FLEET_NO_REPORT=1   # the ephemeral fork must never self-report

# #27 isolation: run the fork in a throw-away git worktree so any accidental
# git staging/committing lands in a discarded tree, not the live checkout.
# The worktree is at HEAD so the fork can still read repo files at relative paths.
# Falls back silently if CWD is not a git repo or git is unavailable.
_ask_wt=""
if _ask_wt="$(mktemp -d /tmp/fleet-ask-XXXXXX 2>/dev/null)"; then
  rmdir "$_ask_wt"   # worktree add requires the target path to not exist yet
  if git worktree add --detach "$_ask_wt" HEAD 2>/dev/null; then
    trap 'git worktree remove --force "$_ask_wt" 2>/dev/null; rm -rf "$_ask_wt" 2>/dev/null' EXIT
    cd "$_ask_wt" || true
  else
    rm -rf "$_ask_wt" 2>/dev/null; _ask_wt=""
  fi
fi

# A short, single-line form of the question for the notes.
qshort="$q"; [ "${#qshort}" -gt 60 ] && qshort="${qshort:0:60}…"

# Resume an off-thread target context when the provider supports it. Claude uses
# a real fork. Codex uses a headless resumed run, which preserves context without
# typing the question into the live tmux window.
sid=""; [[ -f "$RUN_DIR/$to.session" ]] && sid="$(<"$RUN_DIR/$to.session")"
provider="$(fleet_state_get "$to" '.provider' "")"
[[ -z "$provider" && "$to" != "supervisor" ]] && provider="$(fleet_provider_for_child "$to")"
[[ -z "$provider" ]] && provider="$(fleet_default_provider)"

primer="You are \"$to\", answering a question from a peer agent \"$from\" in the same fleet. You have been resumed from a fork of your own working session, so you carry your current context. Answer ONLY the question — concisely and specifically, citing file paths where useful. Do NOT start new work, make edits, or message other agents; just answer. If it's outside your repo or expertise, say so in one line and name who might know."

# F3: this fork's context may LAG the live thread — hedge against stale rulings.
primer="$primer NOTE: your forked context may LAG the live thread. For any recent decision, verify against COMMITTED canon (git log / RESUME.md) rather than trusting recollection, and prefer committed state; if you cannot confirm currency, EXPLICITLY FLAG that your answer may be stale instead of asserting it."

# F5: the fork runs in an intentional read-only worktree mirror of the repo at HEAD.
[[ -n "$_ask_wt" ]] && primer="$primer You are running in an intentional READ-ONLY worktree mirror of the real repo, checked out at HEAD (for isolation). Answer ABOUT that repo; uncommitted working-tree changes are NOT visible here (say so if it's relevant). Do NOT try to cd elsewhere or complain about the working directory — just answer the question."

# F4: a context-free fork (no resolvable session) must not answer with false confidence.
[[ -z "$sid" ]] && primer="(answering WITHOUT live session context — from the primer only) $primer"

ans=""
ans="$(faculty_headless_answer "$provider" "$sid" "$primer" "$q" 2>/dev/null)"

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
fleet_notify "$to" "fleet" "peer '$from' consulted you about «$qshort» — answered off-thread from your provider-native context; no action needed." "$hop"
fleet_log answered "$to" "forked reply → $from (hop $hop)"
