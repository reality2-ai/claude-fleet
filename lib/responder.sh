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

# A short, single-line form of the question for the notes.
qshort="$q"; [ "${#qshort}" -gt 60 ] && qshort="${qshort:0:60}…"

# #27 / live-checkout isolation: run the fork in a throw-away git worktree so any
# accidental git staging/committing lands in a discarded tree, not the live checkout.
# The worktree is at HEAD so the fork can still read repo files at relative paths.
#
# FAIL CLOSED: the fork must NEVER launch from the writer's live checkout. If we
# cannot establish an isolated cwd (mktemp/cd fails), we abort with an error answer
# rather than fall through with cwd still pointing at the live tree. Worktree-add
# failure (non-git target, or lock contention) degrades to an empty temp dir — still
# isolated — and the fork answers from context only.
_ask_wt=""
_ask_norepo=""
_ask_cwd=""
_isolation_abort() {
  local why="$1"
  fleet_enqueue "$from" "$to" "fleet ask aborted: could not create an isolated read-only workspace ($why); refusing to answer from the live checkout." "$hop" answer false
  fleet_notify "$from" "$to" "could not answer «$qshort» — isolation failed ($why); no live-checkout fallback" "$hop"
  fleet_log answered "$to" "ask ABORTED (isolation failed: $why) → $from (hop $hop)"
  exit 0
}
_ask_wt="$(mktemp -d /tmp/fleet-ask-XXXXXX 2>/dev/null)" || _isolation_abort "mktemp failed"
rmdir "$_ask_wt" 2>/dev/null   # worktree add requires the target path to not exist yet
# Retry worktree-add to ride out TRANSIENT concurrent-worktree lock contention:
# many asks can run at once and git takes a repo-level lock, so a single add often
# fails spuriously — and the old code then fell back to the LIVE checkout.
# Only a git repo can host a worktree; skip the retry loop (and its 3s of sleeps)
# for a non-git target and go straight to the empty-tempdir isolate below.
_wt_ok=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for _try in 1 2 3 4 5; do
    if git worktree add --detach "$_ask_wt" HEAD 2>/dev/null; then _wt_ok=1; break; fi
    sleep 0.6
  done
fi
if [[ -n "$_wt_ok" ]]; then
  trap 'git worktree remove --force "$_ask_wt" 2>/dev/null; rm -rf "$_ask_wt" 2>/dev/null' EXIT
  cd "$_ask_wt" || _isolation_abort "cd worktree failed"
  _ask_cwd="$_ask_wt"
else
  # ISOLATION FLOOR (#27/#45): NEVER fall back to the live checkout — an accidental
  # edit/commit there races the sole in-thread writer and can corrupt byte-exact KATs.
  # Drop into a fresh EMPTY temp dir so the fork has no access to the live tree; it
  # answers from context only. A temp-dir/cd failure here is unrecoverable → fail closed.
  rm -rf "$_ask_wt" 2>/dev/null
  _ask_wt="$(mktemp -d /tmp/fleet-ask-norepo-XXXXXX 2>/dev/null)" || _isolation_abort "mktemp (norepo) failed"
  trap 'rm -rf "$_ask_wt" 2>/dev/null' EXIT
  cd "$_ask_wt" || _isolation_abort "cd tempdir failed"
  _ask_cwd="$_ask_wt"
  _ask_norepo=1
fi

# Resume an off-thread target context when the provider supports it. Claude uses
# a real fork. Codex uses a headless resumed run, which preserves context without
# typing the question into the live tmux window.
sid=""; _to_sf="$(fleet_run_path "$to" .session)" && [[ -f "$_to_sf" ]] && sid="$(<"$_to_sf")"
provider="$(fleet_state_get "$to" '.provider' "")"
[[ -z "$provider" && "$to" != "supervisor" ]] && provider="$(fleet_provider_for_child "$to")"
[[ -z "$provider" ]] && provider="$(fleet_default_provider)"

primer="You are \"$to\", answering a question from a peer agent \"$from\" in the same fleet. You have been resumed from a fork of your own working session, so you carry your current context. Answer ONLY the question — concisely and specifically, citing file paths where useful. Do NOT start new work, make edits, or message other agents; just answer. If it's outside your repo or expertise, say so in one line and name who might know."

# F3: this fork's context may LAG the live thread — hedge against stale rulings.
primer="$primer NOTE: your forked context may LAG the live thread. For any recent decision, verify against COMMITTED canon (git log / RESUME.md) rather than trusting recollection, and prefer committed state; if you cannot confirm currency, EXPLICITLY FLAG that your answer may be stale instead of asserting it."

# F5: the fork runs in an intentional read-only worktree mirror of the repo at HEAD.
[[ -n "$_ask_wt" && -z "$_ask_norepo" ]] && primer="$primer You are running in an intentional READ-ONLY worktree mirror of the real repo, checked out at HEAD (for isolation). Answer ABOUT that repo; uncommitted working-tree changes are NOT visible here (say so if it's relevant). Do NOT try to cd elsewhere or complain about the working directory — just answer the question."
# F5b: worktree isolation was unavailable this run — the fork has NO repo files (empty dir),
# so it must answer from context only rather than ever touch the live checkout.
[[ -n "$_ask_norepo" ]] && primer="$primer NOTE: repo-file access is unavailable this run (isolation worktree could not be created), so you are in an EMPTY working dir. Answer from your CONTEXT ONLY; if the question genuinely needs a file lookup, say so in one line rather than guessing. Do NOT attempt to cd into the real repo."

# F4: a context-free fork (no resolvable session) must not answer with false confidence.
[[ -z "$sid" ]] && primer="(answering WITHOUT live session context — from the primer only) $primer"

ans=""
ans="$(faculty_headless_answer "$provider" "$sid" "$primer" "$q" "$_ask_cwd" 2>/dev/null)"

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
