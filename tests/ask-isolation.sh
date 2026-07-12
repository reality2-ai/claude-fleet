#!/usr/bin/env bash
# ask-isolation.sh — regression tests for the `fleet ask` live-checkout isolation
# defect (lib/responder.sh + lib/provider.sh).
#
# Ground truth of the bug: responder.sh created & cd-ed into an isolated worktree,
# but fleet_agent_headless_answer dropped that cwd and passed NO read-only controls,
# so a resumed Claude/Codex fork could restore the writer's original cwd and mutate
# the live checkout. These tests prove, WITHOUT a real provider:
#   A. both provider adapters receive the STRUCTURAL read-only flags (not prompt text)
#      and the isolated cwd is passed through explicitly;
#   B. a resumed responder whose fork tries to write in its cwd CANNOT touch the
#      writer's live checkout — the write lands in the throw-away isolate;
#   C. isolation fails CLOSED — the fork never launches from the live checkout.
#
# Hermetic: stub `claude`/`codex`, throwaway repos, private tmux socket. No network.
# Requires: bash >= 4, jq, git, tmux.  Usage: tests/ask-isolation.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }
# assert a file contains / lacks a fixed string
has()   { if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else no "$1 (missing '$3' in $2)"; fi; }
lacks() { if grep -qF -- "$3" "$2" 2>/dev/null; then no "$1 (unexpected '$3' in $2)"; else ok "$1"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

# ============================================================================
section "A. provider adapters carry structural read-only flags + isolated cwd"
# ----------------------------------------------------------------------------
# Source just enough to call fleet_agent_headless_answer directly.
# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"   || { echo "cannot source common.sh"; exit 1; }
# shellcheck disable=SC1091
source "$ROOT/lib/provider.sh" || { echo "cannot source provider.sh"; exit 1; }

# stub that records argv (one per line) + its PWD, then prints an answer
mk_argv_stub() {
  local path="$1" log="$2"
  cat > "$path" <<STUBEOF
#!/usr/bin/env bash
{ printf 'PWD=%s\n' "\$PWD"; printf '%s\n' "\$@"; } >> "$log"
printf 'stub-answer\n'
STUBEOF
  chmod +x "$path"
}

ISO="$TMP/isolated-cwd"; mkdir -p "$ISO"

# --- claude adapter ---
CLOG="$TMP/claude.argv"; : > "$CLOG"
mk_argv_stub "$TMP/claude" "$CLOG"
FLEET_CLAUDE_BIN="$TMP/claude" \
  fleet_agent_headless_answer claude "SID-123" "the-primer" "the-prompt" "$ISO" >/dev/null 2>&1
has  "claude: -p print mode"                 "$CLOG" "-p"
has  "claude: resumes the session"           "$CLOG" "--resume"
has  "claude: forks (no live-thread write)"  "$CLOG" "--fork-session"
has  "claude: read-only allowlist present"   "$CLOG" "--allowedTools"
has  "claude: allows Read"                    "$CLOG" "Read"
has  "claude: hard-denies mutation tools"    "$CLOG" "--disallowedTools"
has  "claude: denies Bash (no exec surface)" "$CLOG" "Bash"
has  "claude: denies Write"                   "$CLOG" "Write"
has  "claude: denies Edit"                    "$CLOG" "Edit"
# the fork must launch IN the isolated cwd, never the caller's live checkout
has  "claude: launches in the isolated cwd"  "$CLOG" "PWD=$ISO"

# --- codex adapter ---
XLOG="$TMP/codex.argv"; : > "$XLOG"
mk_argv_stub "$TMP/codex" "$XLOG"
FLEET_CODEX_BIN="$TMP/codex" \
  fleet_agent_headless_answer codex "SID-777" "the-primer" "the-prompt" "$ISO" >/dev/null 2>&1
has  "codex: pins isolated cwd via --cd"     "$XLOG" "--cd"
has  "codex: --cd points at the isolate"     "$XLOG" "$ISO"
has  "codex: sandbox flag present"           "$XLOG" "--sandbox"
has  "codex: sandbox is read-only"           "$XLOG" "read-only"
has  "codex: approval flag present"          "$XLOG" "--ask-for-approval"
has  "codex: never blocks on approval"       "$XLOG" "never"
has  "codex: resumes the session"            "$XLOG" "resume"
has  "codex: runs non-interactive exec"      "$XLOG" "exec"

# ============================================================================
section "B. resumed fork cannot mutate the writer's live checkout (cwd isolation)"
# ----------------------------------------------------------------------------
export TOOL_ROOT="$ROOT"
export FLEET_TMUX_USER_SCOPE=off
SOCK="askiso$$"; export FLEET_TMUX_SOCKET="$SOCK" FLEET_TMUX_SESSION="$SOCK"
trap 'command tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TMP"' EXIT

# workspace holding the fleet state (inbox/run/log/state)
WS="$TMP/ws"; mkdir -p "$WS/.fleet/state" "$WS/.fleet/run" "$WS/.fleet/log" "$WS/.fleet/inbox"
export FLEET_WORKSPACE="$WS"

# a stub claude that ATTEMPTS to write in its cwd (as a mutating tool would) and
# records where it ran. If cwd isolation holds, ./PWNED lands in the throw-away
# worktree, NEVER in the writer's live checkout.
run_stub_log="$TMP/responder-claude.log"; : > "$run_stub_log"
cat > "$TMP/claude-mut" <<STUBEOF
#!/usr/bin/env bash
{ printf 'PWD=%s\n' "\$PWD"; printf '%s\n' "\$@"; } >> "$run_stub_log"
echo pwned > ./PWNED 2>/dev/null || true
printf 'stub-answer-from-fork\n'
STUBEOF
chmod +x "$TMP/claude-mut"
export FLEET_CLAUDE_BIN="$TMP/claude-mut"

# --- git writer checkout (the live tree we must protect) ---
WRITER="$TMP/writer"; mkdir -p "$WRITER"
( cd "$WRITER" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'canon\n' > sentinel.txt && git add -A && git commit -qm init )

# a resolvable session so the responder takes the resume+fork path
echo "SID-RESUMED" > "$WS/.fleet/run/peertarget.session"

# run the responder AS IF launched in the writer checkout (its documented cwd).
# Args are <to=target-expert> <from=asker>: the target's session is resumed, the
# asker (peerasker) receives the answer in its inbox.
( cd "$WRITER" && "$ROOT/lib/responder.sh" peertarget peerasker "does the fork write here?" 1 ) \
  >/dev/null 2>&1

if [[ ! -e "$WRITER/PWNED" ]]; then ok "writer checkout has no stray fork write"; else no "writer checkout was written by the fork"; fi
# sentinel content untouched
if grep -qx canon "$WRITER/sentinel.txt" 2>/dev/null; then ok "writer sentinel content intact"; else no "writer sentinel content changed"; fi
# the fork actually ran, and it ran in an isolated /tmp/fleet-ask worktree — NOT the writer
has  "fork launched (stub recorded a run)"        "$run_stub_log" "PWD="
has  "fork launched in an isolated worktree"      "$run_stub_log" "/tmp/fleet-ask"
lacks "fork did NOT launch in the writer tree"    "$run_stub_log" "PWD=$WRITER"
# and it carried the structural read-only flags end-to-end through the responder
has  "responder passed read-only allowlist"       "$run_stub_log" "--disallowedTools"
has  "responder denied Bash to the fork"          "$run_stub_log" "Bash"
# the answer reached the asker's inbox
if [[ -f "$WS/.fleet/inbox/peerasker.jsonl" ]] && grep -qF stub-answer-from-fork "$WS/.fleet/inbox/peerasker.jsonl"; then
  ok "answer delivered to asker inbox"
else no "answer not delivered to asker inbox"; fi

# ============================================================================
section "C. isolation fails CLOSED (never launches from the live checkout)"
# ----------------------------------------------------------------------------
# Static guarantee: every unrecoverable isolation failure routes to _isolation_abort,
# and the fork is NEVER launched from a non-isolated cwd (no bare `cd ... || true`).
R="$ROOT/lib/responder.sh"
has  "abort on outer mktemp failure"     "$R" '|| _isolation_abort "mktemp failed"'
has  "abort on cd into worktree failure" "$R" 'cd "$_ask_wt" || _isolation_abort'
has  "abort on norepo mktemp failure"    "$R" '|| _isolation_abort "mktemp (norepo) failed"'
has  "abort on cd into tempdir failure"  "$R" 'cd "$_ask_wt" || _isolation_abort "cd tempdir failed"'
lacks "no live-checkout cd fallthrough"  "$R" 'cd "$_ask_wt" || true'
has  "isolated cwd threaded to provider" "$R" 'faculty_headless_answer "$provider" "$sid" "$primer" "$q" "$_ask_cwd"'

# Functional degrade: a NON-git writer dir cannot get a worktree, but the fork must
# STILL run in an isolated temp dir — never the non-git live tree.
run2="$TMP/responder-nogit.log"; : > "$run2"
cat > "$TMP/claude-mut2" <<STUBEOF
#!/usr/bin/env bash
{ printf 'PWD=%s\n' "\$PWD"; } >> "$run2"
echo pwned > ./PWNED 2>/dev/null || true
printf 'ok\n'
STUBEOF
chmod +x "$TMP/claude-mut2"
NOGIT="$TMP/nogit-writer"; mkdir -p "$NOGIT"; printf 'plain\n' > "$NOGIT/keep.txt"
FLEET_CLAUDE_BIN="$TMP/claude-mut2" \
  bash -c 'cd "$1" && "$2" a b "q" 1' _ "$NOGIT" "$ROOT/lib/responder.sh" >/dev/null 2>&1
if [[ ! -e "$NOGIT/PWNED" ]]; then ok "non-git writer dir not written by the fork"; else no "non-git writer dir was written"; fi
lacks "fork did NOT run in the non-git writer dir" "$run2" "PWD=$NOGIT"
has   "fork ran in an isolated temp dir instead"   "$run2" "/tmp/fleet-ask"

# ============================================================================
printf '\n%s\n' "----------------------------------------"
printf 'ask-isolation: %s%d passed%s, %s%d failed%s\n' "$_grn" "$pass" "$_rst" \
  "$( ((fail>0)) && printf '%s' "$_red" )" "$fail" "$_rst"
[[ "$fail" -eq 0 ]]
