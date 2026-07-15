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

# --- 11. decision ledger ----------------------------------------------------
section "11. decision ledger"
# add/list/decide must work with just bash+jq (no tmux dependency for the core).
DID="$("$FLEET" decision add "Ship simple USB pairing or wait?" --for alpha --options "ship|wait" --raised-by supervisor 2>/dev/null)"
case "$DID" in d0*) ok "decision add prints a short sortable id ($DID)";; *) no "decision add prints a short sortable id (got '$DID')";; esac
assert "decision record persisted as <id>.json" test -f "$WS2/.fleet/decisions/$DID.json"
has  "record carries provenance (raised_by)" "$WS2/.fleet/decisions/$DID.json" "\"raised_by\": \"supervisor\""
has  "record carries waiting agent"          "$WS2/.fleet/decisions/$DID.json" "\"waiting\": \"alpha\""
has  "record starts open"                    "$WS2/.fleet/decisions/$DID.json" "\"status\": \"open\""
has  "state change appended to log.jsonl"    "$WS2/.fleet/decisions/log.jsonl" "\"event\":\"add\""
"$FLEET" decisions > "$TMP/dec_open.out" 2>&1
has  "decisions lists the open decision"     "$TMP/dec_open.out" "#$DID"
has  "open line shows the waiting agent"      "$TMP/dec_open.out" "waiting: alpha"
"$FLEET" decisions --json > "$TMP/dec_json.out" 2>&1
assert "decisions --json is valid JSON array" jq -e 'type=="array"' "$TMP/dec_json.out"
# a second open decision, then answer the first
DID2="$("$FLEET" decision add "Second open gate" 2>/dev/null)"
: > "$WS2/.fleet/inbox/alpha.jsonl" 2>/dev/null || true
"$FLEET" decide "$DID" "ship it" > "$TMP/dec_decide.out" 2>&1
has  "decide confirms the answer"            "$TMP/dec_decide.out" "answered"
has  "answered record stores the answer"     "$WS2/.fleet/decisions/$DID.json" "\"answer\": \"ship it\""
has  "answered record sets answered_ts"      "$WS2/.fleet/decisions/$DID.json" "\"answered_ts\":"
has  "answer routed to waiting agent's inbox" "$WS2/.fleet/inbox/alpha.jsonl" "ship it"
has  "answer state change logged"            "$WS2/.fleet/decisions/log.jsonl" "\"event\":\"answer\""
"$FLEET" decisions > "$TMP/dec_open2.out" 2>&1
lacks "answered decision no longer in open list" "$TMP/dec_open2.out" "#$DID "
has   "other open decision still listed"         "$TMP/dec_open2.out" "#$DID2"
"$FLEET" decisions --all > "$TMP/dec_all.out" 2>&1
has  "--all includes the answered decision"  "$TMP/dec_all.out" "#$DID"
# the --watch view renders (bounded to one iteration so it terminates)
FLEET_DECISIONS_WATCH_ITERS=1 FLEET_DECISIONS_WATCH_SECS=1 "$FLEET" decisions --watch > "$TMP/dec_watch.out" 2>&1
has  "decisions --watch renders the ledger"  "$TMP/dec_watch.out" "fleet decisions"
# the persistent tmux window is spawned by 'up' and is non-fatal / toggleable
"$FLEET" up --no-supervisor --no-pairs alpha >/dev/null 2>&1; sleep 0.5
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/dec_wins.out" 2>/dev/null
hasline "fleet up spawns the decisions window (default on)" "$TMP/dec_wins.out" "decisions"
"$FLEET" down >/dev/null 2>&1; sleep 0.3
FLEET_DECISIONS_WINDOW=off "$FLEET" up --no-supervisor --no-pairs alpha >/dev/null 2>&1; sleep 0.5
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/dec_wins_off.out" 2>/dev/null
lacks "FLEET_DECISIONS_WINDOW=off skips the window" "$TMP/dec_wins_off.out" "decisions"
"$FLEET" down >/dev/null 2>&1; sleep 0.3

# --- 11. pre-push MAC-value scan --------------------------------------------
# Guards the fleet-wide leak class the old scanner missed: a MAC-shaped VALUE.
# Exercised end-to-end through a real `git push` against a throwaway bare remote,
# so it tests the hook exactly as git invokes it (stdin refs, not a hand-built range).
section "11. pre-push MAC-value scan"
PPHOOK="$ROOT/hooks/git/pre-push"
assert "pre-push hook parses (bash -n)" bash -n "$PPHOOK"

MACREMOTE="$TMP/macremote.git"; MACREPO="$TMP/macrepo"
git init -q --bare "$MACREMOTE"
git init -q "$MACREPO"
git -C "$MACREPO" config user.email smoke@test; git -C "$MACREPO" config user.name smoke
git -C "$MACREPO" config commit.gpgsign false
install -m 755 "$PPHOOK" "$MACREPO/.git/hooks/pre-push"
git -C "$MACREPO" remote add origin "$MACREMOTE"
printf 'base\n' > "$MACREPO/f.txt"
git -C "$MACREPO" add -A >/dev/null 2>&1; git -C "$MACREPO" commit -qm base >/dev/null 2>&1
git -C "$MACREPO" push -q origin HEAD:refs/heads/master >/dev/null 2>&1

# A real-looking MAC, assembled at RUNTIME from two halves. Neither half is a
# 6-octet literal, so THIS FILE never trips the very scanner it is testing —
# otherwise adding this test would make claude-fleet itself unpushable.
_o='12:34:56'; _n='78:9a:bc'; REALMAC="$_o:$_n"

# $1=desc $2=relpath $3=content $4=block|pass $5=optional env assignment (VAR=val)
path_case() {
  local rc=0
  mkdir -p "$MACREPO/$(dirname "$2")"
  printf '%s\n' "$3" > "$MACREPO/$2"
  git -C "$MACREPO" add -A >/dev/null 2>&1
  git -C "$MACREPO" commit -qm case >/dev/null 2>&1
  if [ -n "${5:-}" ]; then
    env "$5" git -C "$MACREPO" push -q origin HEAD:refs/heads/master >/dev/null 2>&1 || rc=$?
  else
    git -C "$MACREPO" push -q origin HEAD:refs/heads/master >/dev/null 2>&1 || rc=$?
  fi
  if [ "$4" = block ]; then
    if [ "$rc" -ne 0 ]; then ok "$1"; else no "$1"; fi
    git -C "$MACREPO" reset -q --hard HEAD~1    # drop it so the next case starts clean
    git -C "$MACREPO" clean -qfd                # and drop any file it introduced
  else
    if [ "$rc" -eq 0 ]; then ok "$1"; else no "$1"; fi
  fi
}
mac_case() { path_case "$1" f.txt "$2" "$3" "${4:-}"; }

mac_case "a real-looking MAC value BLOCKS the push"        "device = $REALMAC" block
mac_case "placeholder MACs do NOT block (02/aa:bb:cc/dead:beef/00:00/ff:ff)" \
         "$(printf 'a=02:11:22:33:44:55\nb=aa:bb:cc:dd:ee:ff\nc=de:ad:be:ef:00:01\nd=00:00:00:00:00:00\ne=ff:ff:ff:ff:ff:ff\n')" pass
mac_case "FLEET_MAC_SCAN=off lets a real MAC through"      "device = $REALMAC" pass FLEET_MAC_SCAN=off

# --- vectors/**.json allowlist: narrow by design -----------------------------
# The allowlist exempts synthetic KAT vectors from the secret-VALUE scan ONLY. It must NOT
# blind the filename scan or the MAC scan — otherwise vectors/ becomes a blind spot, which
# is precisely where a real MAC could hide while looking like test data.
#
# The fake KAT secret is assembled at RUNTIME: a literal `<word>": "<16+ chars>` in this file
# would trip the hook's own secret-assignment pattern and make claude-fleet unpushable.
# (`_katk` alone is inert — the pattern needs the word followed by :/= and 16+ chars.)
_katk='device_master_secret'; _katv="$(printf 'a%.0s' $(seq 1 40))"
FAKEKAT="{\"$_katk\": \"$_katv\"}"

path_case "synthetic KAT secret under vectors/ does NOT block (allowlist works)" \
          "vectors/kat.json" "$FAKEKAT" pass
path_case "a REAL MAC under vectors/ STILL blocks (allowlist must not blind the MAC scan)" \
          "vectors/kat.json" "{\"dev\": \"$REALMAC\"}" block
path_case "a secret-bearing FILENAME under vectors/ still blocks (filename scan not excluded)" \
          "vectors/id_rsa" "not-really-a-key" block

# --- 12. git-hook installer + drift check ------------------------------------
# The hooks drifted for weeks because NOTHING installed or checked them. These cover both:
# the installer (idempotent, preserves a foreign hook as the chained pre-push.local) and the
# drift state machine doctor reports from.
section "12. git-hook installer + drift check"
export TOOL_ROOT="$ROOT"                 # lib/githooks.sh resolves the source from TOOL_ROOT
# shellcheck source=../lib/githooks.sh
source "$ROOT/lib/githooks.sh"

GH="$TMP/gh"; mkdir -p "$GH"
newrepo() { local d="$GH/$1"; rm -rf "$d"; git init -q "$d"; printf '%s\n' "$d"; }
# NB call the lib functions IN THIS shell — `assert bash -c …` would spawn a child bash that
# has never sourced githooks.sh, so the function would be unbound and the test vacuously red.
drift_is() { local st; st="$(fleet_hook_drift_state "$2")"; if [ "$st" = "$3" ]; then ok "$1"; else no "$1 (got '$st')"; fi; }
did()      { local a; a="$(fleet_install_git_hook "$2" "${4:-}")"; if [ "$a" = "$3" ]; then ok "$1"; else no "$1 (got '$a')"; fi; }

R1="$(newrepo r1)"
drift_is "drift state of a hook-less repo is 'missing'"        "$R1" missing
drift_is "a non-git dir reports 'notgit' (never a false FAIL)" "$GH" notgit

# install → current → idempotent
did      "installer reports 'installed' on a fresh repo"       "$R1" installed
assert   "installed hook is executable"                        test -x "$R1/.git/hooks/pre-push"
drift_is "installed hook matches source"                       "$R1" ok
did      "re-run is idempotent (reports 'current')"            "$R1" current

# ★ NEGATIVE CONTROL: the drift check must actually FAIL on drift, or it is theatre.
printf '\n# tampered\n' >> "$R1/.git/hooks/pre-push"
drift_is "a TAMPERED deployed hook is detected as 'drift'"     "$R1" drift
did      "re-install heals drift (reports 'updated')"          "$R1" updated
drift_is "healed hook matches source again"                    "$R1" ok

# a FOREIGN pre-existing hook must be preserved as the chained pre-push.local, not clobbered
R2="$(newrepo r2)"
mkdir -p "$R2/.git/hooks"; printf '#!/usr/bin/env bash\necho mine\n' > "$R2/.git/hooks/pre-push"
chmod +x "$R2/.git/hooks/pre-push"
did      "foreign hook → 'preserved'"                          "$R2" preserved
has      "the foreign hook survives as pre-push.local (our hook chains to it)" "$R2/.git/hooks/pre-push.local" "echo mine"
assert   "pre-push.local is executable"                        test -x "$R2/.git/hooks/pre-push.local"
drift_is "and the fleet hook is now installed"                 "$R2" ok

# --dry-run must not touch anything
R3="$(newrepo r3)"
did      "--dry-run reports the action it WOULD take"          "$R3" installed dry
assert   "--dry-run installed nothing"                         test ! -f "$R3/.git/hooks/pre-push"

# --- summary ----------------------------------------------------------------
printf '\n%s\n' "------------------------------------------"
printf 'smoke: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
