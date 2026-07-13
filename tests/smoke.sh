#!/usr/bin/env bash
# smoke.sh — self-contained smoke test for claude-fleet.
#
# Runnable locally and in CI. It never touches a real fleet: it uses a stub
# `claude`, a private tmux socket, a throwaway $HOME, and the plain-tmux path
# (FLEET_TMUX_USER_SCOPE=off) so it needs no systemd user manager.
#
# Requires: bash >= 4, jq, tmux.  Usage: tests/smoke.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLEET="$ROOT/bin/fleet"

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
# assert a command succeeds
assert()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
# assert a file contains / lacks a fixed string, or has an exact line
has()     { if grep -qF  -- "$3" "$2" 2>/dev/null; then ok "$1"; else no "$1"; fi; }
hasline() { if grep -qxF -- "$3" "$2" 2>/dev/null; then ok "$1"; else no "$1"; fi; }
lacks()   { if grep -qiF -- "$3" "$2" 2>/dev/null; then no "$1"; else ok "$1"; fi; }
section() { printf '\n%s\n' "$1"; }

# --- hermetic environment ---------------------------------------------------
TMP="$(mktemp -d)"
export HOME="$TMP/home"; mkdir -p "$HOME"
export FLEET_TMUX_USER_SCOPE=off
# The fixtures treat manifest children without an explicit provider as Claude and
# assert against the Claude stub. Do not inherit a caller's Codex fleet default.
export FLEET_AGENT_PROVIDER=claude
SOCK="smoke$$"; export FLEET_TMUX_SOCKET="$SOCK" FLEET_TMUX_SESSION="$SOCK"
cleanup() { command tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

# stub claude: record argv (one per line) to $FLEET_STUB_LOG, then idle
STUB="$TMP/claude"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
[ -n "${FLEET_STUB_LOG:-}" ] && printf '%s\n' "$@" >> "$FLEET_STUB_LOG"
exec sleep 600
STUBEOF
chmod +x "$STUB"
export FLEET_CLAUDE_BIN="$STUB"

# stub codex: record argv (one per line) to $FLEET_CODEX_STUB_LOG, then idle
CSTUB="$TMP/codex"
cat > "$CSTUB" <<'STUBEOF'
#!/usr/bin/env bash
[ -n "${FLEET_CODEX_STUB_LOG:-}" ] && printf '%s\n' "$@" >> "$FLEET_CODEX_STUB_LOG"
exec sleep 600
STUBEOF
chmod +x "$CSTUB"
export FLEET_CODEX_BIN="$CSTUB"

# --- 1. static checks -------------------------------------------------------
section "1. syntax + basic commands"
syntax_ok=1
for f in "$ROOT/bin/fleet" "$ROOT"/lib/*.sh "$ROOT"/hooks/*.sh; do
  bash -n "$f" 2>/dev/null || { syntax_ok=0; echo "    bad syntax: $f"; }
done
if [ "$syntax_ok" = 1 ]; then ok "bash -n clean on all scripts"; else no "bash -n clean on all scripts"; fi
"$FLEET" version > "$TMP/ver.out" 2>&1; has "fleet version prints version" "$TMP/ver.out" "fleet 0."
assert "fleet help exits 0" "$FLEET" help

# --- 2. init scaffolding ----------------------------------------------------
section "2. init scaffolding"
WS1="$TMP/ws1"; mkdir -p "$WS1"
"$FLEET" init --no-hooks "$WS1" >/dev/null 2>&1
assert ".fleet/fleet.toml written"   test -f "$WS1/.fleet/fleet.toml"
assert ".fleet/.gitignore written"   test -f "$WS1/.fleet/.gitignore"
assert "state/ run/ log/ created"    test -d "$WS1/.fleet/state" -a -d "$WS1/.fleet/run" -a -d "$WS1/.fleet/log"
FLEET_WORKSPACE="$WS1" "$FLEET" status > "$TMP/status1.out" 2>&1
assert "status on fresh workspace exits 0" test $? -eq 0

# --- build a workspace with a real child cwd + a stub claude ----------------
WS2="$TMP/ws2"; mkdir -p "$WS2/repoA"
mkdir -p "$WS2/.fleet/state" "$WS2/.fleet/run" "$WS2/.fleet/log"
cat > "$WS2/.fleet/fleet.toml" <<'TOML'
[supervisor]
strategy="one_for_one"
max_restarts=3
max_seconds=60

[[child]]
id="alpha"
cwd="repoA"
restart="transient"
seed="seedwork"

[[child]]
id="beta"
cwd="repoA"
restart="transient"
provider="codex"
seed="codex seedwork"
TOML
export FLEET_WORKSPACE="$WS2"

# --- 3. lifecycle: fresh start ----------------------------------------------
section "3. lifecycle (fresh start)"
export FLEET_STUB_LOG="$TMP/alpha.fresh.log"; : > "$FLEET_STUB_LOG"
"$FLEET" up --no-supervisor alpha > "$TMP/up1.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins.out" 2>/dev/null
hasline "alpha has a tmux window" "$TMP/wins.out" "alpha"
hasline "fresh start passes the seed prompt" "$FLEET_STUB_LOG" "seedwork"
lacks   "fresh start does NOT --resume"      "$FLEET_STUB_LOG" "--resume"
FLEET_WORKSPACE="$WS2" "$FLEET" status > "$TMP/status2.out" 2>&1
has "status shows a live window for alpha" "$TMP/status2.out" "alpha"

# --- 4. lifecycle: resume + nudge -------------------------------------------
section "4. resume + carry-on nudge"
"$FLEET" down >/dev/null 2>&1; sleep 0.3
echo "sid-ABCDEF12" > "$WS2/.fleet/run/alpha.session"   # pretend a prior session
export FLEET_STUB_LOG="$TMP/alpha.resume.log"; : > "$FLEET_STUB_LOG"
"$FLEET" up --no-supervisor --no-pairs alpha > "$TMP/up2.out" 2>&1
sleep 0.6
hasline "resume passes --resume"        "$FLEET_STUB_LOG" "--resume"
hasline "resume passes the session id"  "$FLEET_STUB_LOG" "sid-ABCDEF12"
hasline "resume appends 'carry on' nudge" "$FLEET_STUB_LOG" "carry on"

# disable nudge via env
"$FLEET" down >/dev/null 2>&1; sleep 0.3
export FLEET_STUB_LOG="$TMP/alpha.nonudge.log"; : > "$FLEET_STUB_LOG"
export FLEET_CODEX_STUB_LOG="$TMP/beta.codex.resume.log"; : > "$FLEET_CODEX_STUB_LOG"
FLEET_RESUME_NUDGE="" "$FLEET" up --no-supervisor --no-pairs alpha > /dev/null 2>&1
sleep 0.6
lacks "FLEET_RESUME_NUDGE='' suppresses the nudge" "$FLEET_STUB_LOG" "carry on"
echo "sid-BETA-CODEX" > "$WS2/.fleet/run/beta.session"
"$FLEET" up --no-supervisor --no-pairs beta > "$TMP/beta_codex_resume.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_beta_resume.out" 2>/dev/null
hasline "codex resume starts beta while alpha is live" "$TMP/wins_beta_resume.out" "beta"
hasline "codex resume passes resume subcommand" "$FLEET_CODEX_STUB_LOG" "resume"
hasline "codex resume passes the session id" "$FLEET_CODEX_STUB_LOG" "sid-BETA-CODEX"
has "codex resume includes fleet doctrine primer" "$FLEET_CODEX_STUB_LOG" "Treat every non-trivial claim as a conjecture"

# --- 5. down tears the window down ------------------------------------------
section "5. down"
"$FLEET" down >/dev/null 2>&1; sleep 0.3
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins2.out" 2>/dev/null || true
lacks "down removes alpha's window" "$TMP/wins2.out" "alpha"

# --- 6. regression: flag-like member id must not break status ---------------
section "6. regression: '--help' member id (grep guard)"
echo '{"managed":false}' > "$WS2/.fleet/state/--help.json"
FLEET_WORKSPACE="$WS2" "$FLEET" status > "$TMP/status3.out" 2>&1
lacks "status with a '--help' id does not dump grep usage" "$TMP/status3.out" "Usage:"
has   "status still lists real members"                    "$TMP/status3.out" "alpha"

# --- 7. concurrency: fleet up lock ------------------------------------------
section "7. concurrency lock"
flock -x "$WS2/.fleet/run/up.lock" -c 'sleep 3' &
holder=$!; sleep 0.3
"$FLEET" up --no-supervisor --no-pairs alpha > "$TMP/lock.out" 2>&1
has "second concurrent 'fleet up' is skipped" "$TMP/lock.out" "another 'fleet up' is in progress"
wait "$holder" 2>/dev/null || true

"$FLEET" down >/dev/null 2>&1; sleep 0.3
export FLEET_STUB_LOG="$TMP/alpha.autopair.claude.log"; : > "$FLEET_STUB_LOG"
export FLEET_CODEX_STUB_LOG="$TMP/alpha.autopair.codex.log"; : > "$FLEET_CODEX_STUB_LOG"
"$FLEET" up --no-supervisor alpha > "$TMP/up_pair.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_up_pair.out" 2>/dev/null
hasline "fleet up starts the base worker" "$TMP/wins_up_pair.out" "alpha"
hasline "fleet up starts opposite-provider companion by default" "$TMP/wins_up_pair.out" "alpha-codex"
has "auto-pair prompt identifies adversarial pair role" "$FLEET_CODEX_STUB_LOG" "ADVERSARIAL PAIR PROGRAMMER"
has "auto-pair codex twin is read-only" "$FLEET_CODEX_STUB_LOG" "read-only"
has "auto-pair state records base member" "$WS2/.fleet/state/alpha-codex.json" "\"companion_for\": \"alpha\""
has "auto-pair state records standby role" "$WS2/.fleet/state/alpha-codex.json" "\"role\": \"standby\""
has "auto-pair state records non-writer" "$WS2/.fleet/state/alpha-codex.json" "\"writer\": false"
"$FLEET" pairs alpha > "$TMP/pairs_alpha.out" 2>&1
has "pairs command shows logical base" "$TMP/pairs_alpha.out" "alpha"
has "pairs command shows companion lane" "$TMP/pairs_alpha.out" "alpha-codex"
has "pairs command shows standby role" "$TMP/pairs_alpha.out" "standby"
"$FLEET" pair-send alpha "PAIR-FYI" > "$TMP/pair_send.out" 2>&1 || true
has "pair-send writes base inbox" "$WS2/.fleet/inbox/alpha.jsonl" "PAIR-FYI"
has "pair-send writes companion inbox" "$WS2/.fleet/inbox/alpha-codex.jsonl" "PAIR-FYI"
"$FLEET" supervise > "$TMP/supervise_pair.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_supervisor_pair.out" 2>/dev/null
hasline "supervise starts primary supervisor" "$TMP/wins_supervisor_pair.out" "supervisor"
hasline "supervise starts supervisor provider companion" "$TMP/wins_supervisor_pair.out" "supervisor-codex"
"$FLEET" down >/dev/null 2>&1; sleep 0.3

# --- 8. mixed-provider launch, pair, handoff, and refute --------------------
section "8. mixed-provider launch / pair / handoff / refute"
export FLEET_CODEX_STUB_LOG="$TMP/codex.mixed.log"; : > "$FLEET_CODEX_STUB_LOG"
FLEET_TMUX_ARG_MAX=1 "$FLEET" dispatch --provider codex gamma "codex dispatch task" repoA > "$TMP/dispatch_codex.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_mixed.out" 2>/dev/null
hasline "dispatch --provider codex creates gamma window" "$TMP/wins_mixed.out" "gamma"
assert "dispatch can launch via argv file for long prompts" test -f "$WS2/.fleet/run/gamma.argv"
hasline "codex dispatch uses --cd" "$FLEET_CODEX_STUB_LOG" "--cd"
hasline "codex managed worker bypasses interaction by default" "$FLEET_CODEX_STUB_LOG" "--dangerously-bypass-approvals-and-sandbox"
has "codex dispatch receives task prompt" "$FLEET_CODEX_STUB_LOG" "codex dispatch task"
"$FLEET" remote gamma > "$TMP/remote_codex.out" 2>&1
has "remote status labels Codex provider" "$TMP/remote_codex.out" "codex"
has "remote status marks Codex remote-control n/a" "$TMP/remote_codex.out" "n/a"
"$FLEET" remote-control on gamma > "$TMP/remote_control_codex.out" 2>&1
has "remote-control skips Codex windows" "$TMP/remote_control_codex.out" "unavailable for provider 'codex'"

FLEET_RESUME_CHECK=on "$FLEET" doctor --quiet > "$TMP/doctor_resume_missing.out" 2>/dev/null || true
has "doctor flags missing repo-local RESUME.md" "$TMP/doctor_resume_missing.out" "missing RESUME.md"
"$FLEET" init-resume --force alpha > "$TMP/init_resume.out" 2>&1
assert "init-resume scaffolds repo RESUME.md" test -f "$WS2/repoA/RESUME.md"
has "RESUME.md template has takeover fields" "$WS2/repoA/RESUME.md" "## Next Actions"
FLEET_RESUME_CHECK=on "$FLEET" doctor --quiet > "$TMP/doctor_resume_todo.out" 2>/dev/null || true
has "doctor flags unfilled RESUME.md placeholders" "$TMP/doctor_resume_todo.out" "TODO placeholders"
printf '\nHANDOFF-SENTINEL: repo-local state wins over private transcript.\n' >> "$WS2/repoA/RESUME.md"

"$FLEET" pair --provider codex --id alpha-duet alpha > "$TMP/pair.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_pair.out" 2>/dev/null
hasline "pair creates per-repo companion window" "$TMP/wins_pair.out" "alpha-duet"
has "pair prompt identifies adversarial pair role" "$FLEET_CODEX_STUB_LOG" "ADVERSARIAL PAIR PROGRAMMER"
has "pair state records base member" "$WS2/.fleet/state/alpha-duet.json" "\"companion_for\": \"alpha\""
has "pair state records standby role" "$WS2/.fleet/state/alpha-duet.json" "\"role\": \"standby\""
"$FLEET" failover --all --dry-run alpha > "$TMP/failover_dry.out" 2>&1
has "failover dry-run can plan codex takeover" "$TMP/failover_dry.out" "would handoff 'alpha' (claude) -> codex"
"$FLEET" failover --dry-run alpha > "$TMP/failover_explicit_dry.out" 2>&1
has "explicit failover id bypasses live-exhausted auto-discovery gate" "$TMP/failover_explicit_dry.out" "would handoff 'alpha' (claude) -> codex"

: > "$FLEET_CODEX_STUB_LOG"
"$FLEET" handoff alpha > "$TMP/handoff_live.out" 2>&1
sleep 0.2
has "handoff can promote read-only standby" "$TMP/handoff_live.out" "handoff: 'alpha' (claude) -> 'alpha-duet' (codex)"
has "promoted standby handoff prompt includes repo-local RESUME.md" "$FLEET_CODEX_STUB_LOG" "HANDOFF-SENTINEL"
hasline "promoted standby handoff relaunches Codex with bypass" "$FLEET_CODEX_STUB_LOG" "--dangerously-bypass-approvals-and-sandbox"
lacks "promoted standby handoff drops read-only sandbox flag" "$FLEET_CODEX_STUB_LOG" "--sandbox"
lacks "promoted standby handoff drops approval prompt flag" "$FLEET_CODEX_STUB_LOG" "--ask-for-approval"
has "live handoff promotes companion role" "$WS2/.fleet/state/alpha-duet.json" "\"role\": \"takeover\""
has "live handoff promotes companion to writer" "$WS2/.fleet/state/alpha-duet.json" "\"writer\": true"
has "live handoff state records source" "$WS2/.fleet/state/alpha-duet.json" "\"handoff_from\": \"alpha\""

"$FLEET" handoff --provider codex alpha alpha-codex > "$TMP/handoff.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_handoff.out" 2>/dev/null
hasline "handoff creates target provider window" "$TMP/wins_handoff.out" "alpha-codex"
has "handoff prompt names cross-provider handoff" "$FLEET_CODEX_STUB_LOG" "CROSS-PROVIDER HANDOFF"
has "handoff prompt includes repo-local RESUME.md" "$FLEET_CODEX_STUB_LOG" "HANDOFF-SENTINEL"
has "handoff state records source" "$WS2/.fleet/state/alpha-codex.json" "\"handoff_from\": \"alpha\""

"$FLEET" refute --provider codex --id alpha-review alpha "attack the current alpha work" > "$TMP/refute.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_refute.out" 2>/dev/null
hasline "refute creates reviewer window" "$TMP/wins_refute.out" "alpha-review"
has "refute forces codex read-only sandbox" "$FLEET_CODEX_STUB_LOG" "--sandbox"
hasline "refute uses read-only sandbox" "$FLEET_CODEX_STUB_LOG" "read-only"
has "refute prompt is adversarial" "$FLEET_CODEX_STUB_LOG" "REFUTATION"
has "refute state records target" "$WS2/.fleet/state/alpha-review.json" "\"refutes\": \"alpha\""

# --- 9. forked responder (fleet ask plumbing) -------------------------------
section "9. forked responder"
# a stub claude that prints a fixed answer and logs its argv
RSTUB="$TMP/claude-responder"
cat > "$RSTUB" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TMP/responder.args"
echo "FORKED-ANSWER: the registry lives in lib/registry.sh"
EOF
chmod +x "$RSTUB"
echo "sid-TARGET-99" > "$WS2/.fleet/run/alpha.session"   # pretend alpha has a live Claude session
mkdir -p "$WS2/repoB"
TOOL_ROOT="$ROOT" FLEET_WORKSPACE="$WS2" FLEET_TMUX_SOCKET="$SOCK" FLEET_CLAUDE_BIN="$RSTUB" \
  bash "$ROOT/lib/responder.sh" alpha beta "where does the registry live?" 1 >/dev/null 2>&1
has "responder forked the target session (--fork-session)" "$TMP/responder.args" "--fork-session"
hasline "responder resumed the target's session id"        "$TMP/responder.args" "sid-TARGET-99"
has "full answer stored in asker's inbox"     "$WS2/.fleet/inbox/beta.jsonl" "FORKED-ANSWER"
has "one-line summary queued for the asker"   "$WS2/.fleet/inbox/beta.jsonl" "answered"
has "brief no-action FYI queued for target"   "$WS2/.fleet/inbox/alpha.jsonl"  "no action needed"
has   "target gets a fyi-kind note"                 "$WS2/.fleet/inbox/alpha.jsonl" "\"kind\":\"fyi\""
lacks "target is NOT handed an 'ask' to answer"     "$WS2/.fleet/inbox/alpha.jsonl" "\"kind\":\"ask\""

# --- 10. auto-approve PreToolUse hook ---------------------------------------
section "10. auto-approve hook"
APHOOK="$ROOT/hooks/auto-approve.sh"
# run the hook with a payload (+ optional env=val args); pass/fail on whether it
# emitted an "allow" decision.
ap_allow()  { local d="$1" pay="$2"; shift 2
  if printf '%s' "$pay" | env "$@" bash "$APHOOK" 2>/dev/null | grep -q '"permissionDecision":"allow"'; then ok "$d"; else no "$d"; fi; }
ap_prompt() { local d="$1" pay="$2"; shift 2
  if [ -z "$(printf '%s' "$pay" | env "$@" bash "$APHOOK" 2>/dev/null)" ]; then ok "$d"; else no "$d"; fi; }
mkp() { jq -nc --arg t "$1" --arg cwd "$WS2" --arg cmd "$2" --arg fp "$3" \
  '{tool_name:$t, cwd:$cwd, tool_input:({} + (if $cmd!="" then {command:$cmd} else {} end) + (if $fp!="" then {file_path:$fp} else {} end))}'; }

ap_allow  "Read is auto-allowed"                 "$(mkp Read '' "$WS2/x")"
ap_allow  "Bash 'git status' is auto-allowed"    "$(mkp Bash 'git status' '')"
ap_allow  "Bash 'ls -la src' is auto-allowed"    "$(mkp Bash 'ls -la src' '')"
ap_allow  "in-workspace Edit is auto-allowed"    "$(mkp Edit '' "$WS2/repoA/file.txt")"
ap_prompt "Bash 'rm -rf build' prompts"          "$(mkp Bash 'rm -rf build' '')"
ap_allow  "Bash 'git push' is auto-allowed"      "$(mkp Bash 'git push origin main' '')"
ap_prompt "Bash 'git push --force' prompts"      "$(mkp Bash 'git push --force origin main' '')"
ap_prompt "Bash with a pipe prompts"             "$(mkp Bash 'cat x | tee y' '')"
ap_prompt "Bash redirection prompts"             "$(mkp Bash 'echo hi > f' '')"
ap_prompt "edit outside the workspace prompts"   "$(mkp Edit '' '/etc/hosts')"
ap_prompt "unknown tool prompts"                 "$(mkp Frobnicate '' '')"
ap_prompt "FLEET_AUTOCONFIRM=off disables it"    "$(mkp Read '' "$WS2/x")"     FLEET_AUTOCONFIRM=off
ap_prompt "FLEET_AUTOCONFIRM_EDITS=off keeps edit prompts" "$(mkp Edit '' "$WS2/a")" FLEET_AUTOCONFIRM_EDITS=off
# outside any .fleet workspace → never acts
ap_prompt "outside a fleet workspace it stays silent" "$(jq -nc '{tool_name:"Read",cwd:"/tmp",tool_input:{file_path:"/tmp/x"}}')"

# --- summary ----------------------------------------------------------------
printf '\n%s\n' "------------------------------------------"
printf 'smoke: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
