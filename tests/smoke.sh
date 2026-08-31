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
SOCK="fleet-smoke-${TMP##*.}"; export FLEET_TMUX_SOCKET="$SOCK" FLEET_TMUX_SESSION="$SOCK"
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
FLEET_START_NUDGE="carry on" "$FLEET" up --no-supervisor alpha > "$TMP/up1.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins.out" 2>/dev/null
hasline "alpha has a tmux window" "$TMP/wins.out" "alpha"
lacks   "startup removes the bootstrap window" "$TMP/wins.out" "__fleet_root"
lacks   "default startup does not multiply agents" "$TMP/wins.out" "alpha-codex"
hasline "fresh start passes the seed prompt" "$FLEET_STUB_LOG" "seedwork"
hasline "fresh start appends configured carry-on nudge" "$FLEET_STUB_LOG" "carry on"
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
has "codex resume includes fleet doctrine primer" "$FLEET_CODEX_STUB_LOG" "Seek one concrete falsifier"

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
printf 'export FLEET_PAIR_ON_UP=on\n' > "$WS2/.fleet/env"
export FLEET_CODEX_STUB_LOG="$TMP/alpha.envpair.codex.log"; : > "$FLEET_CODEX_STUB_LOG"
"$FLEET" up --no-supervisor alpha > "$TMP/up_env_pair.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_env_pair.out" 2>/dev/null
hasline ".fleet/env can enable automatic opposite-provider companion" \
  "$TMP/wins_env_pair.out" "alpha-codex"
"$FLEET" down >/dev/null 2>&1; sleep 0.3
rm -f "$WS2/.fleet/env"

export FLEET_STUB_LOG="$TMP/alpha.autopair.claude.log"; : > "$FLEET_STUB_LOG"
export FLEET_CODEX_STUB_LOG="$TMP/alpha.autopair.codex.log"; : > "$FLEET_CODEX_STUB_LOG"
"$FLEET" up --no-supervisor --pairs alpha > "$TMP/up_pair.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_up_pair.out" 2>/dev/null
hasline "fleet up starts the base worker" "$TMP/wins_up_pair.out" "alpha"
hasline "fleet up --pairs starts opposite-provider companion" "$TMP/wins_up_pair.out" "alpha-codex"
has "auto-pair prompt identifies adversarial pair role" "$FLEET_CODEX_STUB_LOG" "read-only refuter/standby"
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
: > "$FLEET_STUB_LOG"; : > "$FLEET_CODEX_STUB_LOG"
FLEET_START_NUDGE="carry on" FLEET_SUPERVISOR_PERMISSION_MODE=bypassPermissions \
  "$FLEET" supervise --pair > "$TMP/supervise_pair.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_supervisor_pair.out" 2>/dev/null
hasline "supervise starts primary supervisor" "$TMP/wins_supervisor_pair.out" "supervisor"
hasline "supervise --pair starts supervisor provider companion" "$TMP/wins_supervisor_pair.out" "supervisor-codex"
hasline "fresh supervisor receives carry-on nudge" "$FLEET_STUB_LOG" "carry on"
hasline "supervisor can opt into autonomous permission mode" "$FLEET_STUB_LOG" "bypassPermissions"
hasline "supervisor refuter uses read-only sandbox" "$FLEET_CODEX_STUB_LOG" "read-only"
hasline "supervisor refuter never waits for approval" "$FLEET_CODEX_STUB_LOG" "never"
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
lacks "doctor does not require optional global watchdog processes" "$TMP/doctor_resume_missing.out" "watchdog"

# Copied runtime state may contain absolute paths to the source workspace. Manifest
# ownership wins for configured members; stopped ad-hoc records are historical.
STALE_REPO="$TMP/stale-copy"; git init -q "$STALE_REPO"
git -C "$STALE_REPO" config user.email smoke@test; git -C "$STALE_REPO" config user.name smoke
printf 'stale\n' > "$STALE_REPO/f"; git -C "$STALE_REPO" add f; git -C "$STALE_REPO" commit -qm stale
git -C "$STALE_REPO" remote add origin https://github.com/example/stale-copy.git
jq --arg cwd "$STALE_REPO" '.cwd=$cwd' "$WS2/.fleet/state/alpha.json" > "$WS2/.fleet/state/alpha.json.t"
mv "$WS2/.fleet/state/alpha.json.t" "$WS2/.fleet/state/alpha.json"
jq -n --arg cwd "$STALE_REPO" '{id:"old-stopped",managed:true,state:"stopped",cwd:$cwd,inject_failures:99}' > "$WS2/.fleet/state/old-stopped.json"
FLEET_RESUME_CHECK=off FLEET_HOOK_DRIFT_CHECK=off "$FLEET" doctor --quiet > "$TMP/doctor_copied_state.out" 2>/dev/null || true
lacks "doctor uses manifest cwd instead of copied absolute state cwd" "$TMP/doctor_copied_state.out" "stale-copy"
lacks "doctor ignores stopped ad-hoc runtime failures" "$TMP/doctor_copied_state.out" "old-stopped"
jq --arg cwd "$WS2/repoA" '.cwd=$cwd' "$WS2/.fleet/state/alpha.json" > "$WS2/.fleet/state/alpha.json.t"
mv "$WS2/.fleet/state/alpha.json.t" "$WS2/.fleet/state/alpha.json"

# New members get one non-overwriting scaffold: shared operating contract plus the
# repo-specific dependency/authority map. Unresolved map fields are visible holds.
git -C "$WS2/repoA" init -q
"$FLEET" init-repo alpha > "$TMP/init_repo.out" 2>&1
assert "init-repo scaffolds AGENTS.md" test -f "$WS2/repoA/AGENTS.md"
assert "init-repo scaffolds DECISIONS.md" test -f "$WS2/repoA/DECISIONS.md"
assert "init-repo scaffolds RESUME.md" test -f "$WS2/repoA/RESUME.md"
assert "init-repo installs publish guard" test -x "$WS2/repoA/.git/hooks/pre-push"
assert "init-repo installs attribution hook" test -x "$WS2/repoA/.git/hooks/commit-msg"
has "repo template requires upstream dependencies" "$WS2/repoA/AGENTS.md" "Upstream dependencies: TODO(fleet-onboarding)"
has "repo template requires downstream consumers" "$WS2/repoA/AGENTS.md" "Downstream consumers: TODO(fleet-onboarding)"
has "repo template requires decision consultation" "$WS2/repoA/AGENTS.md" 'Consult `DECISIONS.md`'
FLEET_RESUME_CHECK=off FLEET_HOOK_DRIFT_CHECK=off "$FLEET" doctor --quiet > "$TMP/doctor_onboarding.out" 2>/dev/null || true
has "doctor makes unresolved repository map a visible hold" "$TMP/doctor_onboarding.out" "unresolved fleet onboarding fields"
printf '\nONBOARDING-SENTINEL\n' >> "$WS2/repoA/AGENTS.md"
"$FLEET" init-repo alpha > "$TMP/init_repo_again.out" 2>&1
has "init-repo never overwrites an existing AGENTS.md" "$WS2/repoA/AGENTS.md" "ONBOARDING-SENTINEL"
if "$FLEET" init-repo absent > "$TMP/init_repo_absent.out" 2>&1; then
  no "init-repo rejects an unknown manifest member"
else
  ok "init-repo rejects an unknown manifest member"
fi
sed -i 's/TODO(fleet-onboarding)/configured/g' "$WS2/repoA/AGENTS.md"
FLEET_RESUME_CHECK=off FLEET_HOOK_DRIFT_CHECK=off "$FLEET" doctor --quiet > "$TMP/doctor_onboarding_clear.out" 2>/dev/null || true
lacks "doctor clears the onboarding hold after repository map completion" "$TMP/doctor_onboarding_clear.out" "unresolved fleet onboarding fields"

"$FLEET" init-resume --force alpha > "$TMP/init_resume.out" 2>&1
assert "init-resume scaffolds repo RESUME.md" test -f "$WS2/repoA/RESUME.md"
has "RESUME.md template has takeover fields" "$WS2/repoA/RESUME.md" "## Next Actions"
has "RESUME.md template records GitHub sync" "$WS2/repoA/RESUME.md" "## GitHub Sync"
FLEET_RESUME_CHECK=on FLEET_RESUME_MAX_BYTES=32 "$FLEET" doctor --quiet > "$TMP/doctor_resume_large.out" 2>/dev/null || true
has "doctor bounds oversized RESUME.md context" "$TMP/doctor_resume_large.out" "compact it to one authoritative current state"
FLEET_RESUME_CHECK=on "$FLEET" doctor --quiet > "$TMP/doctor_resume_todo.out" 2>/dev/null || true
has "doctor flags unfilled RESUME.md placeholders" "$TMP/doctor_resume_todo.out" "TODO placeholders"

# A seed-only start followed by an intentional stop is not meaningful work and
# must not manufacture RESUME staleness debt. Structural RESUME checks above remain.
sed -i 's/TODO/DONE/g' "$WS2/repoA/RESUME.md"
touch -d '@1' "$WS2/repoA/RESUME.md"
jq --argjson now "$(date +%s)" '.state="stopped" | .heartbeat=$now' \
  "$WS2/.fleet/state/alpha.json" > "$TMP/alpha-stopped.json"
mv "$TMP/alpha-stopped.json" "$WS2/.fleet/state/alpha.json"
FLEET_RESUME_CHECK=on FLEET_RESUME_STALE_SECS=1 FLEET_HOOK_DRIFT_CHECK=off \
  "$FLEET" doctor --quiet > "$TMP/doctor_resume_stopped.out" 2>/dev/null || true
lacks "stopped managed session does not create RESUME staleness debt" \
  "$TMP/doctor_resume_stopped.out" "stale by"

# GitHub synchronization is locally checkable without network: missing upstream
# and commits ahead of the remote-tracking ref are both operational faults.
git -C "$WS2/repoA" init -q
git -C "$WS2/repoA" config user.email smoke@test
git -C "$WS2/repoA" config user.name smoke
git -C "$WS2/repoA" config commit.gpgsign false
git -C "$WS2/repoA" add RESUME.md
git -C "$WS2/repoA" commit -qm baseline
git -C "$WS2/repoA" remote add origin https://github.com/example/fleet-smoke.git
FLEET_RESUME_CHECK=off "$FLEET" doctor --quiet > "$TMP/doctor_no_upstream.out" 2>/dev/null || true
has "doctor flags GitHub branch without upstream" "$TMP/doctor_no_upstream.out" "has no upstream"
smoke_branch="$(git -C "$WS2/repoA" symbolic-ref --short HEAD)"
git -C "$WS2/repoA" update-ref "refs/remotes/origin/$smoke_branch" HEAD
git -C "$WS2/repoA" branch --set-upstream-to "origin/$smoke_branch" >/dev/null
printf 'verified increment\n' > "$WS2/repoA/sync.txt"
git -C "$WS2/repoA" add sync.txt
git -C "$WS2/repoA" commit -qm increment
FLEET_RESUME_CHECK=off "$FLEET" doctor --quiet > "$TMP/doctor_ahead.out" 2>/dev/null || true
has "doctor flags local commits ahead of GitHub" "$TMP/doctor_ahead.out" "commit(s) ahead"
# Simulate the remote-tracking update performed by a successful push so later
# doctor assertions are not polluted by this deliberate fixture.
git -C "$WS2/repoA" update-ref "refs/remotes/origin/$smoke_branch" HEAD
printf '\nHANDOFF-SENTINEL: repo-local state wins over private transcript.\n' >> "$WS2/repoA/RESUME.md"

"$FLEET" pair --provider codex --id alpha-duet alpha > "$TMP/pair.out" 2>&1
sleep 0.6
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins_pair.out" 2>/dev/null
hasline "pair creates per-repo companion window" "$TMP/wins_pair.out" "alpha-duet"
has "pair prompt identifies adversarial pair role" "$FLEET_CODEX_STUB_LOG" "read-only refuter/standby"
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
has "refute prompt is adversarial" "$FLEET_CODEX_STUB_LOG" "independent read-only refuter"
has "refute state records target" "$WS2/.fleet/state/alpha-review.json" "\"refutes\": \"alpha\""

# --- 8b. authority guard: a read-only companion/refuter may NOT run lifecycle
# commands against its primary/logical pair. Regression for the 2026-07-16
# incident: supervisor-codex ran `handoff --stop-source supervisor` and stopped
# the PRIMARY supervisor. Only human root (no FLEET_CHILD_ID) or the primary may.
section "8b. companion-cannot-kill-primary authority guard"
printf '{"state":"running","role":"supervisor"}\n'                                  > "$WS2/.fleet/state/gc.json"
printf '{"state":"running","role":"standby","writer":false,"companion_for":"gc"}\n' > "$WS2/.fleet/state/gc-codex.json"
: > "$WS2/.fleet/log/fleet.log"

# (1) companion handoff --stop-source against its OWN primary MUST be refused
FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=gc-codex "$FLEET" handoff --stop-source gc > "$TMP/guard_handoff.out" 2>&1; grc=$?
[ "$grc" -ne 0 ] && ok "companion handoff --stop-source primary EXITS non-zero" || no "companion handoff --stop-source primary EXITS non-zero"
has  "companion handoff refusal names the reason"        "$TMP/guard_handoff.out" "read-only companion/refuter"
has  "primary state UNCHANGED after refused handoff"     "$WS2/.fleet/state/gc.json" "\"state\":\"running\""
lacks "primary was NOT stopped by the refused handoff"   "$WS2/.fleet/state/gc.json" "stopped"
has  "denial is audited to the fleet log"                "$WS2/.fleet/log/fleet.log" "DENIED handoff"

# (2) same guard on down + restart against the primary
FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=gc-codex "$FLEET" down gc > "$TMP/guard_down.out" 2>&1; grc=$?
[ "$grc" -ne 0 ] && ok "companion down primary EXITS non-zero" || no "companion down primary EXITS non-zero"
has  "companion down refusal names the reason" "$TMP/guard_down.out" "read-only companion/refuter"
FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=gc-codex "$FLEET" restart gc > "$TMP/guard_restart.out" 2>&1; grc=$?
[ "$grc" -ne 0 ] && ok "companion restart primary EXITS non-zero" || no "companion restart primary EXITS non-zero"

# (3) human root (no FLEET_CHILD_ID) is NEVER guard-blocked
FLEET_WORKSPACE="$WS2" "$FLEET" down gc-codex > "$TMP/guard_human.out" 2>&1
lacks "human-root lifecycle is not guard-blocked" "$TMP/guard_human.out" "read-only companion/refuter"

# --- 8c. messaging authority guard: a read-only companion/refuter may NOT issue
# fleet-wide coordination (broadcast / pair-send) nor send to a THIRD party — it
# may only feed its own primary. Regression for the 2026-07-16 incident where
# supervisor-codex repeatedly broadcast HOLD/RESUME coordination that
# countermanded the primary supervisor and froze core/hive. Same actor model as
# §8b; closes the messaging path the lifecycle guard did not cover.
section "8c. companion-cannot-coordinate messaging authority guard"
printf '{"state":"running","role":"supervisor"}\n'                                  > "$WS2/.fleet/state/gc.json"
printf '{"state":"running","role":"standby","writer":false,"companion_for":"gc"}\n' > "$WS2/.fleet/state/gc-codex.json"
printf '{"state":"running","role":"expert","writer":true}\n'                         > "$WS2/.fleet/state/other.json"
: > "$WS2/.fleet/log/fleet.log"

# (1) companion broadcast MUST be refused + audited
FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=gc-codex "$FLEET" broadcast "RESUME everyone" > "$TMP/msg_bcast.out" 2>&1; grc=$?
[ "$grc" -ne 0 ] && ok "companion broadcast EXITS non-zero" || no "companion broadcast EXITS non-zero"
has  "companion broadcast refusal names the reason" "$TMP/msg_bcast.out" "read-only companion/refuter"
has  "companion broadcast denial is audited"        "$WS2/.fleet/log/fleet.log" "DENIED broadcast"

# (2) companion pair-send MUST be refused
FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=gc-codex "$FLEET" pair-send gc "HOLD" > "$TMP/msg_pair.out" 2>&1; grc=$?
[ "$grc" -ne 0 ] && ok "companion pair-send EXITS non-zero" || no "companion pair-send EXITS non-zero"
has  "companion pair-send refusal names the reason" "$TMP/msg_pair.out" "read-only companion/refuter"

# (3) companion send to a THIRD party (not its primary) MUST be refused
FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=gc-codex "$FLEET" send other "you are on HOLD" > "$TMP/msg_third.out" 2>&1; grc=$?
[ "$grc" -ne 0 ] && ok "companion send-to-third-party EXITS non-zero" || no "companion send-to-third-party EXITS non-zero"
has  "companion third-party send refusal names the reason" "$TMP/msg_third.out" "read-only companion/refuter"
has  "companion third-party send denial is audited"        "$WS2/.fleet/log/fleet.log" "DENIED send"

# (4) companion send to its OWN primary is NOT authority-blocked (the feed-up
# channel) AND carries the advisory provenance tag when it lands.
rm -f "$WS2/.fleet/inbox/gc.jsonl"
FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=gc-codex "$FLEET" send gc "observation for you" > "$TMP/msg_primary.out" 2>&1 || true
lacks "companion send-to-primary is NOT authority-blocked" "$TMP/msg_primary.out" "read-only companion/refuter"
# (5) provenance: the delivered message carries the companion advisory tag
has "companion send-to-primary carries the advisory provenance tag" "$WS2/.fleet/inbox/gc.jsonl" "companion·advisory"

# (5b) ★ FAIL-CLOSED ON UNREADABLE STATE — regression for the 2026-07-17 incident.
# supervisor-codex's state file was ZERO BYTES, so .companion_for and the
# readonly-standby read both came back empty and the old name pattern (*-refute
# only) missed "-codex" => the guard concluded "not a companion" and let it
# BROADCAST real identity values fleet-wide. The original §8c fixture always had
# companion_for set, so it only ever proved the guard works when state is intact.
# A companion must be identified by NAME even with NO usable state at all.
: > "$WS2/.fleet/state/sc-codex.json"                 # ZERO-BYTE state (the incident)
rm -f "$WS2/.fleet/state/nostate-codex.json"          # MISSING state entirely
: > "$WS2/.fleet/log/fleet.log"

FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=sc-codex "$FLEET" broadcast "RESUME everyone" > "$TMP/msg_empty.out" 2>&1; grc=$?
[ "$grc" -ne 0 ] && ok "ZERO-BYTE-state companion broadcast EXITS non-zero" || no "ZERO-BYTE-state companion broadcast EXITS non-zero"
has  "zero-byte-state companion broadcast names the reason" "$TMP/msg_empty.out" "read-only companion/refuter"
has  "zero-byte-state companion broadcast is audited"       "$WS2/.fleet/log/fleet.log" "DENIED broadcast"

FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=nostate-codex "$FLEET" broadcast "RESUME everyone" > "$TMP/msg_nostate.out" 2>&1; grc=$?
[ "$grc" -ne 0 ] && ok "MISSING-state companion broadcast EXITS non-zero" || no "MISSING-state companion broadcast EXITS non-zero"

# a *-codex lane must not reach a third party even with no usable state
FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=sc-codex "$FLEET" send other "capture this vector" > "$TMP/msg_empty3.out" 2>&1; grc=$?
[ "$grc" -ne 0 ] && ok "ZERO-BYTE-state companion send-to-third-party EXITS non-zero" || no "ZERO-BYTE-state companion send-to-third-party EXITS non-zero"

# (6) human root + normal writer are NEVER messaging-guard-blocked
FLEET_WORKSPACE="$WS2" "$FLEET" broadcast "human coordination" > "$TMP/msg_human.out" 2>&1 || true
lacks "human-root broadcast is not messaging-guard-blocked" "$TMP/msg_human.out" "read-only companion/refuter"
FLEET_WORKSPACE="$WS2" FLEET_CHILD_ID=other "$FLEET" send gc "peer note" > "$TMP/msg_writer.out" 2>&1 || true
lacks "normal writer send is not messaging-guard-blocked" "$TMP/msg_writer.out" "read-only companion/refuter"

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
ap_deny()   { local d="$1" pay="$2"; shift 2
  if printf '%s' "$pay" | env "$@" bash "$APHOOK" 2>/dev/null | grep -q '"permissionDecision":"deny"'; then ok "$d"; else no "$d"; fi; }
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
# firmware/key gate — regression guards for the basename-only-matching fixes:
# a flasher/minter must be DENIED+escalated even when hidden behind a wrapper or a
# git chain, while prose and plain read-only tools stay unaffected.
ap_deny   "bare flasher is denied+escalated"     "$(mkp Bash 'espflash flash app.bin' '')"
ap_deny   "adafruit-nrfutil (RAK) is denied"     "$(mkp Bash 'adafruit-nrfutil dfu serial -pkg fw.zip' '')"
ap_deny   "wrapper-hidden flasher is denied"     "$(mkp Bash 'env espflash flash app.bin' '')"
ap_deny   "flasher after a git chain is denied"  "$(mkp Bash 'git commit -m x && espflash flash /dev/ttyUSB0' '')"
ap_deny   "key-mint is denied"                   "$(mkp Bash 'openssl genpkey -out k.pem' '')"
ap_prompt "sort -o (file write) no longer auto-approves" "$(mkp Bash 'sort -o /tmp/x /etc/hostname' '')"
ap_allow  "plain sort is still auto-allowed"     "$(mkp Bash 'sort -rn file.txt' '')"
ap_allow  "commit msg mentioning flash/mint is allowed"  "$(mkp Bash 'git commit -m "flash board, mint cert"' '')"

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
has  "record starts open"                    "$WS2/.fleet/decisions/$DID.json" "\"state\": \"open\""
has  "record separates evidential confidence" "$WS2/.fleet/decisions/$DID.json" "\"confidence\": \"open\""
has  "open gate holds operational action"    "$WS2/.fleet/decisions/$DID.json" "\"action\": \"hold\""
has  "record names reversal authority"       "$WS2/.fleet/decisions/$DID.json" "\"authority\": \"supervisor\""
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
has  "decide confirms ratification"          "$TMP/dec_decide.out" "ratified/go"
has  "answered record stores the answer"     "$WS2/.fleet/decisions/$DID.json" "\"answer\": \"ship it\""
has  "answered record sets answered_ts"      "$WS2/.fleet/decisions/$DID.json" "\"answered_ts\":"
has  "ratification sets mechanical latch"    "$WS2/.fleet/decisions/$DID.json" "\"state\": \"ratified\""
has  "answer routed to waiting agent's inbox" "$WS2/.fleet/inbox/alpha.jsonl" "ship it"
has  "ratification state change logged"      "$WS2/.fleet/decisions/log.jsonl" "\"event\":\"ratify\""
# Same answer is idempotent; a different answer is a hard failure and cannot
# overwrite the latch. This is the core anti-vacillation regression.
"$FLEET" decide "$DID" "ship it" > "$TMP/dec_repeat.out" 2>&1
has  "identical re-ratification is idempotent" "$TMP/dec_repeat.out" "unchanged"
if "$FLEET" decide "$DID" "wait instead" > "$TMP/dec_reverse.out" 2>&1; then
  no "contradictory re-answer is refused"
else
  ok "contradictory re-answer is refused"
fi
has  "refusal explains explicit reversal path" "$TMP/dec_reverse.out" "revoke"
assert "refused re-answer leaves original intact" jq -e '.answer=="ship it" and .action=="go"' "$WS2/.fleet/decisions/$DID.json"
# Any worker may challenge evidence, but a challenge cannot change the command.
FLEET_CHILD_ID=alpha "$FLEET" decision challenge "$DID" "new timing concern" --evidence bench-17 > "$TMP/dec_challenge.out" 2>&1
has  "challenge reports epistemic-only wound" "$TMP/dec_challenge.out" "operational latch remains ratified/go"
assert "challenge preserves operational latch" jq -e '.confidence=="wounded" and .action=="go" and .answer=="ship it"' "$WS2/.fleet/decisions/$DID.json"
"$FLEET" decisions > "$TMP/dec_open2.out" 2>&1
lacks "answered decision no longer in open list" "$TMP/dec_open2.out" "#$DID "
has   "other open decision still listed"         "$TMP/dec_open2.out" "#$DID2"
"$FLEET" decisions --all > "$TMP/dec_all.out" 2>&1
has  "--all includes the answered decision"  "$TMP/dec_all.out" "#$DID"
# Replacement gets a new immutable id. Ratifying it retires (never overwrites)
# its predecessor, and the bounded current view exposes only active state.
DID3="$("$FLEET" decision add "Replacement course" --for alpha --supersedes "$DID" 2>/dev/null)"
"$FLEET" decide "$DID3" "wait for rotation" > "$TMP/dec_successor.out" 2>&1
assert "ratified successor retires predecessor" jq -e --arg id "$DID3" '.state=="superseded" and .superseded_by==$id' "$WS2/.fleet/decisions/$DID.json"
"$FLEET" decisions --current --for alpha --json > "$TMP/dec_current.json"
assert "current view includes active successor" jq -e --arg id "$DID3" 'any(.id==$id and .state=="ratified")' "$TMP/dec_current.json"
assert "current view excludes superseded record" jq -e --arg id "$DID" 'all(.id!=$id)' "$TMP/dec_current.json"
# Local actor provenance enforces named authority (not cryptographic identity).
if FLEET_CHILD_ID=alpha "$FLEET" decision revoke "$DID3" "I changed my mind" > "$TMP/dec_bad_revoke.out" 2>&1; then
  no "non-authority revoke is refused"
else
  ok "non-authority revoke is refused"
fi
has "revoke refusal names authority" "$TMP/dec_bad_revoke.out" "only by authority 'supervisor'"
"$FLEET" decision revoke "$DID3" "benchmark falsified assumption" --evidence bench-17 > "$TMP/dec_revoke.out" 2>&1
assert "authority revoke is explicit refuted/hold" jq -e '.state=="revoked" and .confidence=="refuted" and .action=="hold"' "$WS2/.fleet/decisions/$DID3.json"
# Scope and bound keep takeover context finite.
DID4="$("$FLEET" decision add "Android-only gate" --scope android 2>/dev/null)"
DID5="$("$FLEET" decision add "Alpha gate" --scope alpha 2>/dev/null)"
"$FLEET" decisions --current --for alpha --max 1 --json > "$TMP/dec_bounded.json"
assert "current view is bounded" jq -e 'length==1' "$TMP/dec_bounded.json"
assert "current view applies scope" jq -e --arg id "$DID4" 'all(.id!=$id)' "$TMP/dec_bounded.json"
assert "current view keeps newest applicable gate" jq -e --arg id "$DID5" 'any(.id==$id)' "$TMP/dec_bounded.json"
"$FLEET" decisions --current --for alpha --max 1 > "$TMP/dec_bounded_human.out" 2>&1
has "bounded view discloses omitted active decisions" "$TMP/dec_bounded_human.out" "absence here is not revocation"
# Fresh workers receive the same generated ledger view; transcript/RESUME text
# therefore cannot become an accidental competing source of current commands.
export FLEET_CODEX_STUB_LOG="$TMP/dec_primer.log"; : > "$FLEET_CODEX_STUB_LOG"
command tmux -L "$SOCK" set-environment -t "$SOCK" FLEET_CODEX_STUB_LOG "$FLEET_CODEX_STUB_LOG"
"$FLEET" dispatch --provider codex latchprobe "inspect latch context" repoA > "$TMP/dec_dispatch.out" 2>&1
sleep 0.5
has "worker primer states decision precedence" "$FLEET_CODEX_STUB_LOG" "Ledger controls decisions"
has "worker primer injects bounded current view" "$FLEET_CODEX_STUB_LOG" "#$DID2 [OPEN/HOLD]"
"$FLEET" down latchprobe >/dev/null 2>&1 || true
# the --watch view renders (bounded to one iteration so it terminates)
FLEET_DECISIONS_WATCH_ITERS=1 FLEET_DECISIONS_WATCH_SECS=1 "$FLEET" decisions --watch > "$TMP/dec_watch.out" 2>&1
has  "decisions --watch renders the ledger"  "$TMP/dec_watch.out" "fleet decisions"
# Current decisions live in brief/primers; the extra tmux pane is opt-in.
"$FLEET" up --no-supervisor --no-pairs alpha >/dev/null 2>&1; sleep 0.5
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/dec_wins.out" 2>/dev/null
lacks "fleet up skips redundant decisions window by default" "$TMP/dec_wins.out" "decisions"
"$FLEET" down >/dev/null 2>&1; sleep 0.3
FLEET_DECISIONS_WINDOW=on "$FLEET" up --no-supervisor --no-pairs alpha >/dev/null 2>&1; sleep 0.5
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/dec_wins_off.out" 2>/dev/null
hasline "FLEET_DECISIONS_WINDOW=on adds the optional pane" "$TMP/dec_wins_off.out" "decisions"
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
mac_case "narrow allowlist passes (02/aa:bb:cc/dead:beef prefixes + EXACT all-zero/broadcast)" \
         "$(printf 'a=02:11:22:33:44:55\nb=aa:bb:cc:dd:ee:ff\nc=de:ad:be:ef:00:01\nd=00:00:00:00:00:00\ne=ff:ff:ff:ff:ff:ff\n')" pass
# finding-1 regression (2026-07-15, refutation of the sibling CI gate): 00:00 and ff:ff must
# be allowlisted as EXACT tokens only, never as PREFIXES — real OUIs under them (00:00:0c
# Cisco, 00:00:5e IANA, ff:ff:11) must BLOCK. MACs assembled at runtime from 3-octet halves
# so no 6-octet literal sits in this file (else the fixed hook blocks claude-fleet's own push).
_cisco='00:00:0c'; _iana='00:00:5e'; _ffp='ff:ff:11'
mac_case "real OUI under old 00:00 PREFIX (Cisco) now BLOCKS"  "dev = $_cisco:$_n" block
mac_case "real OUI under old 00:00 PREFIX (IANA) now BLOCKS"   "dev = $_iana:$_n" block
mac_case "real-looking MAC under old ff:ff PREFIX now BLOCKS"  "dev = $_ffp:$_o" block
mac_case "FLEET_MAC_SCAN=off lets a real MAC through"      "device = $REALMAC" pass FLEET_MAC_SCAN=off

# --- 2026-07-17 regression: THE GATE BLOCKED A LEAK REMEDIATION -------------
# This hook REFUSED the push that scrubbed a real rbid correlator off r2-composer's
# PUBLIC main, over four DOCUMENTED synthetic placeholders — teaching the lane to
# bypass the gate at the exact moment the stakes were highest. A hygiene gate whose
# false positives block remediation is worse than no gate at that moment.
# These four are the actual values that blocked it; they MUST pass.
_z1='00:00:00:00:00:01'; _z2='00:00:00:00:00:02'; _ladder='11:22:33:44:55:66'
_oui_zeronic="$(printf 'f4:12:fa')":'00:00:00'      # real vendor OUI + ALL-ZERO synthetic NIC
mac_case "synthetic all-zero-OUI counter NICs pass (00:00:00:00:00:01/02)" \
         "$(printf 'a=%s\nb=%s\n' "$_z1" "$_z2")" pass
mac_case "byte-ladder placeholder passes (11:22:33:44:55:66)" "x = $_ladder" pass
mac_case "real OUI with ALL-ZERO NIC passes (vendor, not device)" "x = $_oui_zeronic" pass
# ...and the fix must NOT re-open the fail-open class it was built to close:
# a POPULATED NIC under the same real OUI is a device-unique value and MUST still block.
mac_case "same real OUI with a POPULATED NIC still BLOCKS" "x = $(printf 'f4:12:fa'):$_n" block
mac_case "all-zero OUI with a POPULATED NIC still BLOCKS"  "x = 00:00:00:$_n" block

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

# Scrub-forward commits must be publishable: the guard previously classified its own
# explicit replacement values as fresh secrets. Keep extraction per assignment so one
# scrub marker on a minified line cannot exempt a real credential beside it.
_scrub_name='apiKey'; _scrub_plain='R2-SCRUBBED-THIRD-PARTY-KEY-----'
_scrub_b64='UjItU0NSVUJCRUQtVEhJUkQtUEFSVFktS0VZLS0tLS0'
_real_name='password'; _real_value="$(printf 'z%.0s' $(seq 1 32))"
path_case "plain scrub marker does not block remediation" "scrub.txt" \
          "$_scrub_name: $_scrub_plain" pass
path_case "base64 R2-SCRUBBED marker does not block remediation" "scrub.txt" \
          "$_scrub_name: $_scrub_b64" pass
path_case "scrub marker cannot hide a real assignment on the same line" "scrub.txt" \
          "$_scrub_name: $_scrub_plain; $_real_name: $_real_value" block

# A very long added line made grep -q close its pipe early and emitted a harmless but
# misleading `printf: Broken pipe`. The hook now feeds matchers without producer pipes.
_long_value="$(printf 'x%.0s' $(seq 1 100000))"
printf '%s=%s %s\n' "$_real_name" "$_real_value" "$_long_value" > "$MACREPO/long.txt"
git -C "$MACREPO" add long.txt
git -C "$MACREPO" commit -qm case
_long_out="$TMP/prepush-long.out"; _long_rc=0
git -C "$MACREPO" push -q origin HEAD:refs/heads/master >"$_long_out" 2>&1 || _long_rc=$?
if [ "$_long_rc" -ne 0 ]; then ok "long secret line still blocks"; else no "long secret line passed"; fi
lacks "long-line block emits no broken-pipe diagnostic" "$_long_out" "Broken pipe"
git -C "$MACREPO" reset -q --hard HEAD~1
git -C "$MACREPO" clean -qfd

# A repo decision log is operational, not aspirational. The publish boundary accepts a
# new record or an explicit, reviewable acknowledgement and rejects silent omission.
DECREMOTE="$TMP/decremote.git"; DECREPO="$TMP/decrepo"
git init -q --bare "$DECREMOTE"; git init -q "$DECREPO"
git -C "$DECREPO" config user.email smoke@test; git -C "$DECREPO" config user.name smoke
git -C "$DECREPO" config commit.gpgsign false
install -m 755 "$PPHOOK" "$DECREPO/.git/hooks/pre-push"
git -C "$DECREPO" remote add origin "$DECREMOTE"
cp "$ROOT/templates/repo/DECISIONS.md" "$DECREPO/DECISIONS.md"
printf 'base\n' > "$DECREPO/f.txt"
git -C "$DECREPO" add DECISIONS.md f.txt; git -C "$DECREPO" commit -qm base
assert "first decision-ledger commit can publish" git -C "$DECREPO" push -q origin HEAD:refs/heads/master
printf 'routine\n' >> "$DECREPO/f.txt"
git -C "$DECREPO" add f.txt; git -C "$DECREPO" commit -qm routine
_decision_out="$TMP/prepush-decision.out"; _decision_rc=0
git -C "$DECREPO" push -q origin HEAD:refs/heads/master >"$_decision_out" 2>&1 || _decision_rc=$?
if (( _decision_rc != 0 )); then ok "publish guard rejects an unaccounted commit"; else no "publish guard rejects an unaccounted commit"; fi
has "decision rejection explains the missing acknowledgement" "$_decision_out" "neither updates DECISIONS.md nor has a Decision-Log trailer"
git -C "$DECREPO" commit --amend -qm $'routine\n\nDecision-Log: none'
assert "explicit no-decision acknowledgement can publish" git -C "$DECREPO" push -q origin HEAD:refs/heads/master
printf '\n### D-20260721-99 — test record\n' >> "$DECREPO/DECISIONS.md"
git -C "$DECREPO" add DECISIONS.md; git -C "$DECREPO" commit -qm decision
assert "a commit containing a decision record can publish" git -C "$DECREPO" push -q origin HEAD:refs/heads/master
# THREE-DIGIT sequence numbers. The fixture above is D-20260721-99 — the largest two-digit
# id there is — so the gate's `[0-9]{2}` was never exercised past its own boundary, and the
# day this repo's ledger reached D-...-100 the gate silently began rejecting every citation
# of its own decisions. A fixture chosen at the edge tests everything except the edge.
printf 'three-digit\n' >> "$DECREPO/f.txt"
git -C "$DECREPO" add f.txt; git -C "$DECREPO" commit -qm $'three-digit\n\nDecision-Log: D-20260807-142'
assert "a three-digit decision citation can publish" git -C "$DECREPO" push -q origin HEAD:refs/heads/master
printf 'multi\n' >> "$DECREPO/f.txt"
git -C "$DECREPO" add f.txt; git -C "$DECREPO" commit -qm $'multi\n\nDecision-Log: D-20260807-140, D-20260807-141, D-20260721-05'
assert "a mixed-width multi-id citation can publish" git -C "$DECREPO" push -q origin HEAD:refs/heads/master
# CONTROL: widening the digits must not have widened it into accepting junk.
printf 'junk\n' >> "$DECREPO/f.txt"
git -C "$DECREPO" add f.txt; git -C "$DECREPO" commit -qm $'junk\n\nDecision-Log: D-2026-7'
_junk_rc=0; git -C "$DECREPO" push -q origin HEAD:refs/heads/master >/dev/null 2>&1 || _junk_rc=$?
if (( _junk_rc != 0 )); then ok "a malformed decision id is still rejected"; else no "a malformed decision id now passes"; fi
git -C "$DECREPO" commit --amend -qm $'junk\n\nDecision-Log: none'
assert "the malformed case can still publish once acknowledged" git -C "$DECREPO" push -q origin HEAD:refs/heads/master

# --- 11b. pre-push GATE CONTROLS — error must not read as clean --------------
# Each case FORCES a failure and asserts the gate reports ERROR, not PASS. A clean run over
# a corpus proves nothing on its own: an errored scan produces no matches and therefore
# looks exactly like a pass.
#
# INVOKES THE HOOK AS A SUBPROCESS with crafted stdin — CALLS PRODUCTION, never reimplements
# it. A control that reimplements the rule tests its own copy: it stays green while the real
# gate is broken, which is the same false-green it exists to catch.
#
# EACH CASE PERTURBS THE INPUT THE GATE ACTUALLY READS, and asserts the SPECIFIC refusal.
# Measured while writing these: asserting only a NON-ZERO EXIT let the blob case pass while
# the obj_type guard was disabled — the blob fell through to the enumerator guard and was
# refused for a different reason. A control that cannot tell WHICH guard fired tests neither.
# --- 11c. MAIL-PATH MAC SCAN + EQUIVALENCE WITH pre-push -----------------------
# lib/macscan.sh is the CANONICAL rule; pre-push keeps an inline copy because it is
# installed standalone into .git/hooks across seven repos and cannot source lib/.
# That duplication is unavoidable today, so it is MECHANICALLY POLICED here: the two
# must AGREE AT THE BOUNDARY over a shared corpus. Behavioural equivalence, not textual
# — a text diff would break on formatting and prove nothing about behaviour.
section "11c. mail-path MAC scan + pre-push equivalence"
MACSCAN="$ROOT/lib/macscan.sh"
assert "macscan.sh parses (bash -n)" bash -n "$MACSCAN"
assert "comms.sh still parses after wiring (bash -n)" bash -n "$ROOT/lib/comms.sh"
# shellcheck source=lib/macscan.sh
. "$MACSCAN"

# 1) the lib rule FIRES on a real-looking value. Reuses $REALMAC, assembled at runtime
#    in section 11 — this file must never carry a 6-octet literal or it makes the repo
#    unpushable by its own gate.
if [ -n "$(fleet_mac_values "device = $REALMAC")" ]; then
  ok "lib rule flags a real-looking MAC"; else no "lib rule flags a real-looking MAC"; fi

# 2) every allowlisted form passes, INDIVIDUALLY — a combined fixture would let one
#    surviving form hide behind another's pass.
_allowed_ok=1
for _a in "02:11:22:33:44:55" "aa:bb:cc:dd:ee:ff" "de:ad:be:ef:00:01" \
          "00:00:00:00:00:00" "ff:ff:ff:ff:ff:ff" "11:22:33:44:55:66"; do
  [ -z "$(fleet_mac_values "x=$_a")" ] || { _allowed_ok=0; break; }
done
if [ "$_allowed_ok" = 1 ]; then ok "every allowlisted form passes individually"
else no "an allowlisted form was flagged ($_a)"; fi

# 3) THE WARNING MUST NOT BECOME THE LEAK IT REPORTS. It may name the count and the OUI;
#    it must never echo a device-unique value into a terminal or CI log.
_warn_out="$(fleet_mac_warn "device = $REALMAC" "test" 2>&1 >/dev/null)"
case "$_warn_out" in
  *"$REALMAC"*) no "warning text does not contain the full MAC value" ;;
  *"${REALMAC%:*:*:*}"*) ok "warning names the OUI only, never the full value" ;;
  *) no "warning did not name the OUI (got: ${_warn_out:-empty})" ;;
esac

# 4) FAIL-OPEN IS THE PROPERTY MAIL DEPENDS ON. A diagnostic that can wedge the transport
#    it observes is a worse defect than the one it reports, so this asserts rc=0 on the
#    path that WARNS — not merely on the quiet path.
_mw_rc=0; fleet_mac_warn "device = $REALMAC" "test" 2>/dev/null || _mw_rc=$?
if [ "$_mw_rc" = 0 ]; then ok "fleet_mac_warn returns 0 even when it warns (never blocks mail)"
else no "fleet_mac_warn returned $_mw_rc — this would block mail"; fi

# 5) the documented off-switch actually switches off
if [ -z "$(FLEET_MAC_SCAN=off fleet_mac_warn "device = $REALMAC" "test" 2>&1 >/dev/null)" ]; then
  ok "FLEET_MAC_SCAN=off silences the mail warning"
else no "FLEET_MAC_SCAN=off did not silence the mail warning"; fi

# 6) EQUIVALENCE AT THE BOUNDARY — the whole point of this section. For the same input,
#    the lib rule's verdict must match what pre-push actually does to a push.
#    lib FLAGS  <-> pre-push BLOCKS   |   lib PASSES <-> pre-push ACCEPTS
_eq_ok=1
[ -n "$(fleet_mac_values "device = $REALMAC")" ] || _eq_ok=0        # lib flags it
mac_case "equivalence: lib flags it AND pre-push blocks it" "device = $REALMAC" block
_allow_fixture="$(printf 'a=02:11:22:33:44:55\nb=aa:bb:cc:dd:ee:ff\nc=de:ad:be:ef:00:01\n')"
[ -z "$(fleet_mac_values "$_allow_fixture")" ] || _eq_ok=0          # lib passes them
mac_case "equivalence: lib passes them AND pre-push accepts them" "$_allow_fixture" pass
if [ "$_eq_ok" = 1 ]; then ok "lib verdict agrees with pre-push on both fixtures"
else no "lib verdict DIVERGED from pre-push — the inline copy has drifted"; fi

section "11b. pre-push gate controls (forced failures)"
GATEREPO="$TMP/gaterepo"; GATEREMOTE="$TMP/gateremote.git"
git init -q --bare "$GATEREMOTE"; git init -q "$GATEREPO"
git -C "$GATEREPO" config user.email t@t; git -C "$GATEREPO" config user.name t
install -m 755 "$PPHOOK" "$GATEREPO/.git/hooks/pre-push"
git -C "$GATEREPO" remote add origin "$GATEREMOTE"
cp "$ROOT/templates/repo/DECISIONS.md" "$GATEREPO/DECISIONS.md"
printf 'base\n' > "$GATEREPO/g.txt"
git -C "$GATEREPO" add DECISIONS.md g.txt
git -C "$GATEREPO" commit -qm $'base\n\nDecision-Log: none'
_ZERO=0000000000000000000000000000000000000000

# Drive the hook directly: stdin is `<local_ref> <local_sha> <remote_ref> <remote_sha>`.
# MUST RUN WITH cwd INSIDE THE REPO. The hook calls bare `git`, so invoked from elsewhere
# every sha is unresolvable and the obj_type guard fires for the WRONG REASON — measured while
# writing this: case 1 refused, but as "points at a unknown object" rather than as a dead
# enumerator. A control that lands on the wrong guard still goes green if it only checks the
# exit code, which is why each case below asserts the SPECIFIC refusal.
gate_run() {  # gate_run <local_sha> <remote_sha> -> sets _g_out/_g_rc
  _g_rc=0
  _g_out="$(cd "$GATEREPO" && printf 'refs/heads/master %s refs/heads/master %s\n' "$1" "$2" \
    | .git/hooks/pre-push origin "$GATEREMOTE" 2>&1)" || _g_rc=$?
}

# 1) DEAD ENUMERATOR — perturbs the RANGE, which is what `git diff` reads to build the scan
#    input. An unresolvable remote sha makes every enumerator fatal; before v7 that returned
#    an EMPTY added-set and the push reported CLEAN.
gate_run "$(git -C "$GATEREPO" rev-parse HEAD)" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
if (( _g_rc != 0 )); then ok "gate refuses an unscannable range (dead enumerator)"; else no "gate refuses an unscannable range (dead enumerator)"; fi
case "$_g_out" in *"could not enumerate"*) ok "refusal names the enumerator, not a generic failure";; *) no "refusal names the enumerator, not a generic failure";; esac

# 2) NON-COMMIT REF — perturbs $local_sha, read by the obj_type guard. `git diff <blob>`
#    exits 129, the error is swallowed, and the added-set comes back empty. refs/keep/* pins
#    point at blobs, which is why this is reachable rather than theoretical.
_g_blob="$(printf 'gate-control' | git -C "$GATEREPO" hash-object -w --stdin)"
gate_run "$_g_blob" "$_ZERO"
if (( _g_rc != 0 )); then ok "gate refuses a ref pointing at a blob"; else no "gate refuses a ref pointing at a blob"; fi
case "$_g_out" in *"not a commit"*) ok "blob refusal comes from the obj_type guard specifically";; *) no "blob refusal comes from the obj_type guard specifically";; esac

# 3) NEGATIVE CONTROL — the gate must actually REDDEN on a real finding. Cases 1-2 only prove
#    it refuses; without this, nothing proves it CATCHES anything.
# ASSEMBLED AT RUNTIME, NEVER WRITTEN AS A LITERAL. A positive-control fixture is by
# construction the thing the gate blocks, so spelling it out here makes THIS FILE unpushable —
# measured: the push refused on exactly this line. The fix is assembly, NOT a weakened pattern
# and NOT a self-exemption for the test directory, either of which would blind the real gate.
_g_kw='api'; _g_v1='ZmFrZVNtb2tl'; _g_v2='Q29udHJvbDEyMzQ1Njc4OTAxMg'
printf '%s_key = "%s%s"\n' "$_g_kw" "$_g_v1" "$_g_v2" > "$GATEREPO/leak.txt"
git -C "$GATEREPO" add leak.txt
git -C "$GATEREPO" commit -qm $'leak\n\nDecision-Log: none'
_gate_leak_rc=0
git -C "$GATEREPO" push -q origin HEAD:refs/heads/master >/dev/null 2>&1 || _gate_leak_rc=$?
if (( _gate_leak_rc != 0 )); then ok "gate blocks a hardcoded secret assignment"; else no "gate blocks a hardcoded secret assignment"; fi
git -C "$GATEREPO" reset -q --hard HEAD~1

# 4) DENOMINATOR ON THE PASS PATH — a clean scan and an empty-range scan were visually
#    identical before v7: exit 0, no output. The count must state its own EXCLUSIONS too, or
#    a FILTERED scan reads as a COMPLETE one (the sample-reported-as-clean defect the range
#    cap was rewritten to prevent).
printf 'ordinary\n' >> "$GATEREPO/g.txt"
git -C "$GATEREPO" add g.txt
git -C "$GATEREPO" commit -qm $'ordinary\n\nDecision-Log: none'
_gate_pass_out="$TMP/gate-pass.out"; _gate_pass_rc=0
git -C "$GATEREPO" push -q origin HEAD:refs/heads/master >"$_gate_pass_out" 2>&1 || _gate_pass_rc=$?
if (( _gate_pass_rc == 0 )); then ok "an ordinary commit still publishes (gate not over-tightened)"; else no "an ordinary commit still publishes (gate not over-tightened)"; fi
has "clean scan states its denominator"  "$_gate_pass_out" "secret scan:"
has "denominator names its exclusions"   "$_gate_pass_out" "excluded as vendored KAT vectors"

# 5) THE DENOMINATOR IS ACCURATE, not merely present — a known number of added lines must be
#    counted exactly. Worth having on its own: "prints a number" and "prints the RIGHT number"
#    are different claims, and only the second makes the count usable for comparing runs.
#
#    ⚠ STATED LIMIT — THIS IS **NOT** A CONTROL FOR THE STDERR-CAPTURE FIX, and it must not be
#    read as one. Measured: it passes identically against the pre-fix hook, because nothing in
#    this scenario makes git write to stderr on success, so it cannot discriminate. The fix
#    (capturing stderr separately) therefore ships REASONED BUT UNCONTROLLED — direction-safe,
#    since a stray line can only cause a false BLOCK, never a false pass. Two approaches were
#    tried and rejected rather than fudged: sourcing the hook to call enumerate_into directly
#    (the hook exits early, which ends the sourcing shell), and forcing a git warning (only
#    reachable via environment-specific config, and a fragile control is worse than a stated
#    gap). If someone finds a portable way to make an enumerator warn on success, this is the
#    case to extend.
printf 'l1\nl2\nl3\n' > "$GATEREPO/count.txt"
git -C "$GATEREPO" add count.txt
git -C "$GATEREPO" commit -qm $'count\n\nDecision-Log: none'
_gate_cnt_out="$TMP/gate-count.out"; _gate_cnt_rc=0
git -C "$GATEREPO" push -q origin HEAD:refs/heads/master >"$_gate_cnt_out" 2>&1 || _gate_cnt_rc=$?
if (( _gate_cnt_rc == 0 )); then ok "a known-size commit publishes"; else no "a known-size commit publishes"; fi
_gate_lines="$(sed -n 's/.*secret scan: [0-9]* files, \([0-9]*\) added lines.*/\1/p' "$_gate_cnt_out" | tail -1)"
if [ "${_gate_lines:-x}" = "3" ]; then ok "denominator counts exactly the added lines (3)"; else no "denominator inaccurate (expected 3, got '${_gate_lines:-none}')"; fi

# --- 12. git-hook installer + drift check ------------------------------------
# The hooks drifted for weeks because NOTHING installed or checked them. These cover the
# installer (idempotent, preserves foreign hooks as chained *.local files) and the drift
# state machine doctor reports from.
# --- 11d. FIRMWARE GATE — bypass families, grant scope, audit integrity ---------
# Every assertion here FAILED against the pre-fix hook (md5 1765961515a6d574e6f510f308e1517e),
# measured by a 7-route probe on 2026-07-28 (D-20260728-82). Roy-authorised full rebuild.
#
# SAFETY: the hook is a pure TEXT CLASSIFIER — it contains no eval and never executes the
# payload. G-rows assert that premise rather than assuming it, and a PATH tripwire proves
# no firmware tool was invoked by any case. All targets are non-existent tokens.
section "11d. firmware gate (bypass, grant scope, audit)"
GW="$TMP/gatework"; TRIP="$TMP/tripwire"; STUB="$TMP/stubs"
mkdir -p "$GW/.fleet" "$GW/work" "$TRIP" "$STUB"
# G1 — stubs that record and refuse. If the hook ever EXECUTES a payload, $TRIP fills.
for _t in espflash esptool esptool.py openssl ssh python python3 make dfu-util uvx pipx; do
  printf '#!/bin/sh\ntouch "%s/%s"\nexit 99\n' "$TRIP" "$_t" > "$STUB/$_t"; chmod 755 "$STUB/$_t"
done
# Existence of the LIVE authorisation file, as a plain test rather than `ls | wc -l`
# (which is what SC2012 was flagging). Same question, one fewer subprocess, and no
# dependence on how ls renders a name. NOTE the assertion is unchanged and still only
# detects CREATION or DELETION of the live file — a modification in place would pass.
_g_live_before=0; [ -e "$ROOT/../.fleet/flash-authorization" ] && _g_live_before=1
printf 'expires=%s\nartifact=probe-fixture.bin\ntarget=/dev/ttyPROBE0\nsha256=%s\n' \
  "$(( $(date +%s) + 86400 ))" "$(printf '0%.0s' $(seq 1 64))" > "$GW/.fleet/flash-authorization"
printf '#!/bin/bash\nespflash flash --port /dev/ttyNOPE9 app.bin\n' > "$GW/work/flash-board.sh"

# decide <command> -> echoes allow|deny|none
g_decide() {
  PATH="$STUB:$PATH" jq -nc --arg cwd "$GW/work" --arg cmd "$1" \
    '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}' \
    | PATH="$STUB:$PATH" bash "$ROOT/hooks/auto-approve.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none
}
# g_case <desc> <cmd> <expected: deny|allow|notdeny>
g_case() {
  local d; d="$(g_decide "$2")"
  case "$3" in
    deny)    [ "$d" = deny ]  && ok "$1" || no "$1 (got '$d')" ;;
    allow)   [ "$d" = allow ] && ok "$1" || no "$1 (got '$d')" ;;
    notdeny) [ "$d" != deny ] && ok "$1" || no "$1 (got '$d')" ;;
  esac
  # G1 asserted PER CASE, not once at the end: a single leak must name its own row.
  if [ -z "$(ls -A "$TRIP" 2>/dev/null)" ]; then :; else no "TRIPWIRE: a firmware tool was EXECUTED by: $1"; rm -f "$TRIP"/*; fi
}

# G2 — the premise that makes this suite safe to run at all.
if [ "$(command grep -c '\beval\b' "$ROOT/hooks/auto-approve.sh" || true)" = 0 ]; then
  ok "G2 hook contains no eval (payload is never executed)"
else no "G2 hook contains eval — this suite is no longer safe"; fi

# A — indirection routes that formerly produced NO decision at all
g_case "A1 wrapper script (token only inside the file)"      'bash flash-board.sh'                              deny
g_case "A2 wrapper script via ./ form"                       'bash ./flash-board.sh X1'                         deny
g_case "A3 ssh remote exec"                                  "ssh h.invalid 'espflash flash x.bin /dev/ttyN'"   deny
g_case "A4 python -m interpreter indirection"                'python -m esptool --chip esp32s3 erase_flash'     deny
g_case "A5 uvx runner indirection"                           'uvx esptool --chip esp32s3 erase_flash'           deny
g_case "A6 make firmware target"                             'make flash'                                       deny
g_case "A7 variable-carried argv"                            'T=espflash; $T flash n.bin /dev/ttyN'             deny

# B — quote/escape normalisation at TOKEN level
g_case "B1 double-quoted tool name"                          '"espflash" flash --port /dev/ttyN app.bin'        deny
g_case "B2 single-quoted tool name"                          "'espflash' flash --port /dev/ttyN app.bin"        deny
g_case "B3 backslash-escaped tool name"                      '\espflash flash --port /dev/ttyN app.bin'         deny

# C — grant scope: the allow path must not launder
g_case "C0 granted op in one segment ALLOWS"                 'esptool.py --port /dev/ttyPROBE0 write_flash 0x0 probe-fixture.bin' allow
g_case "C1 grant tokens in a COMMENT do not authorise"       'esptool.py --chip esp32s3 erase_flash # probe-fixture.bin /dev/ttyPROBE0' deny
g_case "C2 grant tokens in ANOTHER SEGMENT do not authorise" 'echo probe-fixture.bin /dev/ttyPROBE0 && esptool.py --chip esp32s3 erase_flash' deny
g_case "C3 flash grant does NOT authorise NVS extraction"    'esptool.py --port /dev/ttyACM0 read_flash 0x9000 0x6000 s.bin # probe-fixture.bin /dev/ttyPROBE0' deny

# D — audit integrity
rm -f "$GW/.fleet/flash-authorization.log"
g_decide 'esptool.py --port /dev/ttyPROBE0 write_flash 0x0 probe-fixture.bin' >/dev/null
if [ "$(awk -F'\t' '$2=="USED"' "$GW/.fleet/flash-authorization.log" 2>/dev/null | wc -l)" -ge 1 ]; then
  ok "D1 an allowed op writes a USED record"; else no "D1 no USED record written"; fi
if command grep -q 'cmd=' "$GW/.fleet/flash-authorization.log" 2>/dev/null; then
  ok "D2 the record carries the COMMAND text, not only the grant fields"
else no "D2 record omits the command — it can misdescribe the operation"; fi
g_decide 'esptool.py --chip esp32s3 erase_flash' >/dev/null
if [ "$(awk -F'\t' '$2=="DENIED"' "$GW/.fleet/flash-authorization.log" 2>/dev/null | wc -l)" -ge 1 ]; then
  ok "D3 a DENIED op is also recorded (absence no longer ambiguous)"
else no "D3 denials leave no record"; fi
chmod 0444 "$GW/.fleet/flash-authorization.log" 2>/dev/null; chmod 0555 "$GW/.fleet" 2>/dev/null
if [ "$(g_decide 'esptool.py --port /dev/ttyPROBE0 write_flash 0x0 probe-fixture.bin')" != allow ]; then
  ok "D4 an unwritable audit log FAILS CLOSED (does not allow)"
else no "D4 allowed an op it could not record"; fi
chmod 0755 "$GW/.fleet" 2>/dev/null; chmod 0644 "$GW/.fleet/flash-authorization.log" 2>/dev/null

# E — false-positive side. LOAD-BEARING, not a courtesy: denying benign offline ops is
# what taught the operator to wrap commands in scripts, and every wrapper was silent.
g_case "E1 offline save-image is not denied"                 'espflash save-image --chip esp32s3 target/app app.bin' notdeny
g_case "E2 offline merge_bin is not denied"                  'esptool.py --chip esp32s3 merge_bin -o o.bin 0x0 b.bin' notdeny
g_case "E3 --version is not denied"                          'espflash --version'                               notdeny
g_case "E4 command -v lookup is not denied (#88)"            'command -v espflash'                              notdeny
g_case "E5 bash -n syntax check is not denied"               'bash -n flash-board.sh'                           notdeny
g_case "E6 reading a script that mentions a flasher"         'command grep -n espflash flash-board.sh'          notdeny

# G4 — the live authorisation state must be untouched by this suite.
_g_live_after=0; [ -e "$ROOT/../.fleet/flash-authorization" ] && _g_live_after=1
if [ "$_g_live_before" = "$_g_live_after" ]; then ok "G4 live .fleet/flash-authorization untouched"
else no "G4 the suite touched the LIVE authorisation state"; fi

section "12. git-hook installer + drift check"
export TOOL_ROOT="$ROOT"                 # lib/githooks.sh resolves the source from TOOL_ROOT
# shellcheck source=../lib/githooks.sh
source "$ROOT/lib/githooks.sh"

GH="$TMP/gh"; mkdir -p "$GH"
newrepo() { local d="$GH/$1"; rm -rf "$d"; git init -q "$d"; printf '%s\n' "$d"; }
# NB call the lib functions IN THIS shell — `assert bash -c …` would spawn a child bash that
# has never sourced githooks.sh, so the function would be unbound and the test vacuously red.
drift_is() { local st; st="$(fleet_hook_drift_state "$2" "${4:-pre-push}")"; if [ "$st" = "$3" ]; then ok "$1"; else no "$1 (got '$st')"; fi; }
did()      { local a; a="$(fleet_install_git_hook "$2" "${4:-}" "${5:-pre-push}")"; if [ "$a" = "$3" ]; then ok "$1"; else no "$1 (got '$a')"; fi; }

R1="$(newrepo r1)"
drift_is "drift state of a hook-less repo is 'missing'"        "$R1" missing
drift_is "a non-git dir reports 'notgit' (never a false FAIL)" "$GH" notgit

# install → current → idempotent
did      "installer reports 'installed' on a fresh repo"       "$R1" installed
assert   "installed hook is executable"                        test -x "$R1/.git/hooks/pre-push"
drift_is "installed hook matches source"                       "$R1" ok
did      "re-run is idempotent (reports 'current')"            "$R1" current

# The attribution hook is part of the same managed set; a definition that is never
# deployed is another false-green control plane.
drift_is "commit-msg starts missing too"                        "$R1" missing commit-msg
did      "installer deploys commit-msg"                         "$R1" installed "" commit-msg
assert   "installed commit-msg is executable"                   test -x "$R1/.git/hooks/commit-msg"
drift_is "installed commit-msg matches source"                  "$R1" ok commit-msg

# ★ NEGATIVE CONTROL: the drift check must actually FAIL on drift, or it is theatre.
printf '\n# tampered\n' >> "$R1/.git/hooks/pre-push"
drift_is "same version + different bytes is 'drift-tampered'"  "$R1" drift-tampered
did      "re-install heals drift (reports 'updated')"          "$R1" updated
drift_is "healed hook matches source again"                    "$R1" ok

# ★ DIRECTION. Drift alone never said WHICH SIDE was stale, so its remedy — overwrite the
#   deployed copy — was right in one direction and a silent downgrade in the other. MEASURED
#   2026-09-01: r2-standard ran PREPUSH_VERSION 13 against a source at 12, and the delta was
#   the D-186 fold exemption covering 1726 commits. Installing would have deleted it.
_pv() { grep -m1 -oE '^# PREPUSH_VERSION: [0-9]+' "$1" | grep -oE '[0-9]+$'; }
_SRCV="$(_pv "$ROOT/hooks/git/pre-push")"
R5="$(newrepo r5)"; fleet_install_git_hook "$R5" >/dev/null
sed -i "s/^# PREPUSH_VERSION: ${_SRCV}/# PREPUSH_VERSION: $(( _SRCV + 1 ))/" "$R5/.git/hooks/pre-push"
drift_is "a deployed hook AHEAD of source reads 'drift-ahead'"  "$R5" drift-ahead
did      "and the installer REFUSES to downgrade it"            "$R5" refused-ahead
assert   "the ahead hook still carries its own version"         grep -q "PREPUSH_VERSION: $(( _SRCV + 1 ))" "$R5/.git/hooks/pre-push"
# the opposite direction must still install, or the refusal is just a broken installer
R6="$(newrepo r6)"; fleet_install_git_hook "$R6" >/dev/null
sed -i "s/^# PREPUSH_VERSION: ${_SRCV}/# PREPUSH_VERSION: 1/" "$R6/.git/hooks/pre-push"
drift_is "a deployed hook BEHIND source reads 'drift-stale'"    "$R6" drift-stale
did      "and a stale hook still installs normally"             "$R6" updated
# an unreadable version must not be guessed at in either direction
R7="$(newrepo r7)"; fleet_install_git_hook "$R7" >/dev/null
sed -i "/^# PREPUSH_VERSION:/d" "$R7/.git/hooks/pre-push"
drift_is "no readable version reads 'drift-unknown', not a guess" "$R7" drift-unknown

# a FOREIGN pre-existing hook must be preserved as the chained pre-push.local, not clobbered
R2="$(newrepo r2)"
mkdir -p "$R2/.git/hooks"; printf '#!/usr/bin/env bash\necho mine\n' > "$R2/.git/hooks/pre-push"
chmod +x "$R2/.git/hooks/pre-push"
did      "foreign hook → 'preserved'"                          "$R2" preserved
has      "the foreign hook survives as pre-push.local (our hook chains to it)" "$R2/.git/hooks/pre-push.local" "echo mine"
assert   "pre-push.local is executable"                        test -x "$R2/.git/hooks/pre-push.local"
drift_is "and the fleet hook is now installed"                 "$R2" ok

# commit-msg also preserves and actually CALLS a foreign hook.
R4="$(newrepo r4)"
mkdir -p "$R4/.git/hooks"
printf '#!/usr/bin/env bash\nprintf chained > "$(git rev-parse --show-toplevel)/foreign-ran"\n' > "$R4/.git/hooks/commit-msg"
chmod +x "$R4/.git/hooks/commit-msg"
did      "foreign commit-msg is preserved"                      "$R4" preserved "" commit-msg
has      "foreign commit-msg survives as commit-msg.local"      "$R4/.git/hooks/commit-msg.local" "foreign-ran"
git -C "$R4" config user.email smoke@test; git -C "$R4" config user.name smoke
printf 'x\n' > "$R4/f"; git -C "$R4" add f; git -C "$R4" commit -qm chained
assert   "fleet commit-msg chains the foreign hook"             test -f "$R4/foreign-ran"

# --dry-run must not touch anything
R3="$(newrepo r3)"
did      "--dry-run reports the action it WOULD take"          "$R3" installed dry
assert   "--dry-run installed nothing"                         test ! -f "$R3/.git/hooks/pre-push"

# --- L. a companion recovers its primary's id -------------------------------
# 2026-08-30. `fleet refute` mints "$target-$provider-refute", so a claude
# companion is r2-claude-refute. The guard that decides who a read-only companion
# may message recovered the primary by STRIPPING A SUFFIX, and knew -codex-refute,
# -refute and -codex and nothing about -claude. It recovered "r2-claude" — a lane
# that has never existed — so the refuter was refused when messaging either real
# reader and its report sat unread in a mailbox nobody opens. Two halves of one
# convention; only the generator was ever updated.
section "L. companion primary recovery"
_cb() {
  local b="${1%-refute}"
  case "$b" in
    *-codex)  b="${b%-codex}" ;;
    *-claude) b="${b%-claude}" ;;
  esac
  printf '%s\n' "$b"
}
assert "claude companion recovers its primary" test "$(_cb r2-claude-refute)" = "r2"
assert "codex companion recovers its primary" test "$(_cb r2-codex-refute)" = "r2"
assert "bare -refute recovers its primary" test "$(_cb r2-refute)" = "r2"
assert "bare -codex twin recovers its primary" test "$(_cb r2-codex)" = "r2"
assert "a hyphenated primary is not eaten" test "$(_cb standard-codex-refute)" = "standard"
# THE PRODUCER SIDE: refute must record the target under the key the guards read.
# .refutes was written and .companion_for was read — a wrong key reads as absence,
# and absence is the LEGITIMATE state for a non-companion, so it failed silently.
has "refute records companion_for, not only refutes" "$ROOT/bin/fleet" ".companion_for=\$target"
has "the guard prefers the recorded fact to the name" "$ROOT/bin/fleet" "'.refutes' \"\""

# --- M. per-lane model and effort reach a claude lane ------------------------
# 2026-08-29. `model` was already per-lane for codex and silently absent for
# claude, so the SAME manifest key worked or did nothing depending on the
# provider. `effort` existed nowhere, which is why setting it inside a lane only
# held for that session: /effort writes the USER-GLOBAL default, not lane state.
# BOTH DIRECTIONS: the flags appear when the keys are set, and NOTHING is added
# when they are not — an always-on flag would silently override every global.
section "M. per-lane model and effort (claude)"
cat >> "$WS2/.fleet/fleet.toml" <<'TOML'

[[child]]
id      = "effortlane"
cwd     = "."
restart = "transient"
name    = "effortlane"
adapter = "cli-tmux"
model   = "claude-sonnet-5"
effort  = "low"
TOML
export FLEET_STUB_LOG="$TMP/effortlane.log"; : > "$FLEET_STUB_LOG"
"$FLEET" up --no-supervisor --no-pairs effortlane >/dev/null 2>&1
sleep 0.6
hasline "manifest effort reaches the lane as --effort" "$FLEET_STUB_LOG" "--effort"
hasline "manifest effort passes its value"             "$FLEET_STUB_LOG" "low"
hasline "manifest model reaches the lane as --model"   "$FLEET_STUB_LOG" "--model"
# THE CONTROL THAT CAN FAIL: alpha declares neither key, so neither flag may
# appear. Without this, an unconditional flag would pass every assertion above
# while overriding the operator's global setting on every lane in the fleet.
export FLEET_STUB_LOG="$TMP/alpha.noeffort.log"; : > "$FLEET_STUB_LOG"
"$FLEET" up --no-supervisor --no-pairs alpha >/dev/null 2>&1
sleep 0.6
lacks  "a lane declaring no effort gets NO --effort flag" "$FLEET_STUB_LOG" "--effort"

# --- N. the fleet outlives its last lane ------------------------------------
# 2026-08-29. Until this fix the server's lifetime was EXACTLY the lifetime of its
# lane windows: `fleet_tmux_drop_placeholder` removed the 300s bootstrap and put
# nothing back, so when the last lane exited — a provider usage limit, a crash, an
# /exit — tmux exited with it and the whole fleet went. Reported as "the fleet does
# not survive closing the laptop lid"; the lid was a red herring (logout survival was
# already correct). BOTH DIRECTIONS ARE ASSERTED because a test that only checks the
# anchor exists cannot tell a held server from one that never lost its last window.
section "N. the fleet outlives its last lane"
export FLEET_STUB_LOG="$TMP/alpha.anchor.log"; : > "$FLEET_STUB_LOG"
"$FLEET" up --no-supervisor alpha >/dev/null 2>&1
sleep 0.6
# the anchor is a SESSION, never a window — it must not reach the operator's bar
command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' > "$TMP/wins.anchor.out" 2>/dev/null
lacks  "the anchor is not a window in the fleet session" "$TMP/wins.anchor.out" "__fleet_anchor"
lacks  "the bootstrap window is still removed"           "$TMP/wins.anchor.out" "__fleet_root"
assert "an anchor session holds the server" \
  command tmux -L "$SOCK" has-session -t __fleet_anchor
# THE CONTROL THAT CAN FAIL: kill every lane window and require the server to live.
# Without the anchor this kills the server and `has-session` below returns non-zero.
while read -r w; do
  [ -n "$w" ] && [ "$w" != "__fleet_root" ] && \
    command tmux -L "$SOCK" kill-window -t "$SOCK:$w" 2>/dev/null || true
done < <(command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' 2>/dev/null)
sleep 0.4
assert "server survives its LAST lane window closing" \
  command tmux -L "$SOCK" has-session -t __fleet_anchor

# --- summary ----------------------------------------------------------------
printf '\n%s\n' "------------------------------------------"
printf 'smoke: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
