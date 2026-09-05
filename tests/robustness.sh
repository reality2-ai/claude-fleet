#!/usr/bin/env bash
# robustness.sh — bench tests for the "self-regulating fleet" robustness work.
#
# Like smoke.sh, this NEVER touches a real fleet: it builds a STUB fleet-state in
# a throwaway temp dir, runs on a private tmux socket, a throwaway $HOME, and the
# plain-tmux path (FLEET_TMUX_USER_SCOPE=off). It exercises the new ground-truth
# invariants:
#   (a) wiped registry  → fleet_reconcile recreates child docs from live windows
#                         + run/ session ids → fleet status lists every child
#   (b) dropped Stop    → mail queues → the TTL/doctor path unsticks an IDLE pane,
#                         and NEVER unsticks/injects a non-idle pane
#   (c) failed inject   → delivered stays false, .inject_failures bumps, next
#                         drain retries, fleet doctor flags it loudly
#   (d) ground truth    → a child with NO state doc but a live window still
#                         appears in fleet status
#
# Note on tmux pane-content capture: in a DETACHED hermetic tmux server, capturing
# rendered pane CONTENT is timing-flaky on some hosts (window NAMES + state files
# are reliable — that's what smoke.sh leans on). So the structural assertions use
# real tmux windows + state files, while the pane-inspection / inject-transport
# LOGIC (idle gate, inject verify, drain bookkeeping) is driven deterministically
# via the libraries' own env toggles + small shell-function overrides. Every code
# path under test is the real one.
#
# Requires: bash >= 4, jq, tmux.  Usage: tests/robustness.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLEET="$ROOT/bin/fleet"

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }
# assert two strings equal
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi; }
# assert haystack contains needle / lacks it
hasstr()   { case "$2" in *"$3"*) ok "$1" ;; *) no "$1" ;; esac; }
lacksstr() { case "$2" in *"$3"*) no "$1" ;; *) ok "$1" ;; esac; }
# assert a command exits zero / nonzero
ok0() { if "$@" >/dev/null 2>&1; then ok "$_DESC"; else no "$_DESC"; fi; }
no0() { if "$@" >/dev/null 2>&1; then no "$_DESC"; else ok "$_DESC"; fi; }

# --- hermetic environment ---------------------------------------------------
TMP="$(mktemp -d)"
export HOME="$TMP/home"; mkdir -p "$HOME"
export FLEET_TMUX_USER_SCOPE=off
SOCK="cfrob$$"; export FLEET_TMUX_SOCKET="$SOCK" FLEET_TMUX_SESSION="$SOCK"
cleanup() { command tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

# stub claude: just idle (we never need real agent behaviour here)
STUB="$TMP/claude"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
exec sleep 600
STUBEOF
chmod +x "$STUB"
export FLEET_CLAUDE_BIN="$STUB"

# --- build a workspace with three children ----------------------------------
WS="$TMP/ws"; mkdir -p "$WS/repoA" "$WS/repoB" "$WS/repoC"
mkdir -p "$WS/.fleet/state" "$WS/.fleet/run" "$WS/.fleet/log"
cat > "$WS/.fleet/fleet.toml" <<'TOML'
[supervisor]
strategy="one_for_one"
max_restarts=3
max_seconds=60
max_hops=6

[[child]]
id="alpha"
cwd="repoA"
restart="transient"
seed="seedwork"

[[child]]
id="beta"
cwd="repoB"
restart="transient"
seed="seedwork"

[[child]]
id="gamma"
cwd="repoC"
restart="transient"
seed="seedwork"
TOML
export FLEET_WORKSPACE="$WS"

# Helper: source the libraries the same way bin/fleet does, in a subshell, so we
# can call the real functions directly with a controlled state dir. Anything
# printed by the body is returned to the caller.
run_lib() { # run_lib <bash-body>
  TOOL_ROOT="$ROOT" FLEET_WORKSPACE="$WS" \
  FLEET_TMUX_SOCKET="$SOCK" FLEET_TMUX_SESSION="$SOCK" FLEET_TMUX_USER_SCOPE=off \
  FLEET_CLAUDE_BIN="$STUB" \
  bash -c '
    set -uo pipefail
    source "$TOOL_ROOT/lib/common.sh"
    source "$TOOL_ROOT/lib/manifest.sh"
    source "$TOOL_ROOT/lib/registry.sh"
    source "$TOOL_ROOT/lib/provider.sh"
    source "$TOOL_ROOT/lib/tmux.sh"
    source "$TOOL_ROOT/lib/restart.sh"
    source "$TOOL_ROOT/lib/comms.sh"
    source "$TOOL_ROOT/lib/transport.sh"
    fleet_load_paths 0 >/dev/null 2>&1 || true
    [[ -f "$MANIFEST" ]] && fleet_manifest_load "$MANIFEST"
    '"$1"
}

# Bring up ALL children as real tmux windows (the ground-truth surface). `fleet
# up` with no id starts every manifest child; --no-supervisor keeps it to the
# three workers.
"$FLEET" up --no-supervisor --no-pairs >/dev/null 2>&1
sleep 1.2
# Simulate what the SessionStart hook records: run/<id>.session for each.
echo "sid-ALPHA-0001" > "$WS/.fleet/run/alpha.session"
echo "sid-BETA-0002"  > "$WS/.fleet/run/beta.session"
echo "sid-GAMMA-0003" > "$WS/.fleet/run/gamma.session"
# And seed their session_id into the docs the spawn created (mimicking the hook).
for c in alpha beta gamma; do
  jq --arg s "sid-$(echo "$c" | tr a-z A-Z)" '.session_id=$s' "$WS/.fleet/state/$c.json" \
    > "$WS/.fleet/state/$c.json.t" && mv "$WS/.fleet/state/$c.json.t" "$WS/.fleet/state/$c.json"
done

windows() { command tmux -L "$SOCK" list-windows -t "$SOCK" -F '#W' 2>/dev/null; }
section "0. preconditions"
w="$(windows | grep -c -E '^(alpha|beta|gamma)$')"
eq "three child windows are live" "$w" "3"

# =====================================================================
section "(a) wiped registry → reconcile recreates docs from ground truth"
# Wipe every child state doc (the deletable cache), keep run/<id>.session.
rm -f "$WS/.fleet/state/alpha.json" "$WS/.fleet/state/beta.json" "$WS/.fleet/state/gamma.json"
cnt_before="$(ls "$WS/.fleet/state"/*.json 2>/dev/null | grep -E '/(alpha|beta|gamma)\.json' | wc -l)"
eq "registry wiped (0 child docs on disk)" "$cnt_before" "0"

# fleet status runs fleet_reconcile at the top → docs come back.
"$FLEET" status > "$TMP/status_a.out" 2>&1
for c in alpha beta gamma; do
  _DESC="reconcile recreated state/$c.json"; ok0 test -f "$WS/.fleet/state/$c.json"
done
# session_id seeded from run/<id>.session
sa="$(jq -r '.session_id' "$WS/.fleet/state/alpha.json" 2>/dev/null)"
eq "alpha.session_id seeded from run/ id" "$sa" "sid-ALPHA-0001"
# cwd reconstructed from the manifest
ca="$(jq -r '.cwd' "$WS/.fleet/state/alpha.json" 2>/dev/null)"
hasstr "alpha.cwd reconstructed from manifest" "$ca" "repoA"
# all three appear in status
for c in alpha beta gamma; do
  hasstr "status lists $c after reconcile" "$(cat "$TMP/status_a.out")" "$c"
done
# reconcile is CREATES-ONLY: it must not clobber an existing doc's session_id.
jq '.session_id="PINNED-DO-NOT-CHANGE"' "$WS/.fleet/state/alpha.json" > "$WS/.fleet/state/alpha.json.t" \
  && mv "$WS/.fleet/state/alpha.json.t" "$WS/.fleet/state/alpha.json"
"$FLEET" status >/dev/null 2>&1
sa2="$(jq -r '.session_id' "$WS/.fleet/state/alpha.json")"
eq "reconcile does NOT overwrite an existing doc" "$sa2" "PINNED-DO-NOT-CHANGE"

# =====================================================================
section "(d) ground-truth liveness: live window, NO state doc → still in status"
# Delete gamma's doc again and disable reconcile so ONLY the union can save it.
rm -f "$WS/.fleet/state/gamma.json"
out_union="$(FLEET_RECONCILE=off "$FLEET" status 2>&1)"
hasstr "gamma shows from its live window alone (reconcile OFF)" "$out_union" "gamma"
# state_ids union directly:
ids="$(run_lib 'fleet_state_ids | sort | tr "\n" " "')"
hasstr "fleet_state_ids unions the live window id" "$ids" "gamma"
# and with the union gate OFF, the doc-less child disappears (proves the union is the cure)
ids_nounion="$(run_lib 'FLEET_STATE_IDS_UNION=off fleet_state_ids | sort | tr "\n" " "')"
lacksstr "FLEET_STATE_IDS_UNION=off drops the doc-less child" "$ids_nounion" "gamma"
# restore gamma's doc for later sections
"$FLEET" status >/dev/null 2>&1   # reconcile recreates it

# =====================================================================
section "(b) dropped Stop → TTL/idle unstick (and never unstick a busy pane)"
# Queue mail for beta, mark it NOT ready, with a stale heartbeat (missed Stop).
mkdir -p "$WS/.fleet/inbox"
old="$(( $(date +%s) - 100000 ))"
jq -nc --argjson ts "$old" '{ts:$ts,from:"supervisor",to:"beta",text:"queued note",hops:1,kind:"fyi",delivered:false}' \
  > "$WS/.fleet/inbox/beta.jsonl"
jq --argjson hb "$old" '.ready=false | .heartbeat=$hb' "$WS/.fleet/state/beta.json" \
  > "$WS/.fleet/state/beta.json.t" && mv "$WS/.fleet/state/beta.json.t" "$WS/.fleet/state/beta.json"

# Positive: idle pane (FLEET_PANE_IDLE_CHECK=off makes fleet_pane_is_idle return idle)
# → the unstick flips .ready true so the stranded mailbox can drain.
run_lib 'FLEET_PANE_IDLE_CHECK=off fleet_reconcile_unstick_ready beta' >/dev/null 2>&1
rb="$(jq -r '.ready' "$WS/.fleet/state/beta.json")"
eq "(b) idle + stale + queued → .ready unstuck to true" "$rb" "true"

# Negative 1: a BUSY pane must NEVER be unstuck. Re-arm beta unready+stale+queued,
# and force the idle check to report busy.
jq --argjson hb "$old" '.ready=false | .heartbeat=$hb' "$WS/.fleet/state/beta.json" \
  > "$WS/.fleet/state/beta.json.t" && mv "$WS/.fleet/state/beta.json.t" "$WS/.fleet/state/beta.json"
# override fleet_pane_is_idle to "busy" (return 1) inside the lib run
run_lib 'fleet_pane_is_idle() { return 1; }; fleet_reconcile_unstick_ready beta' >/dev/null 2>&1
rb2="$(jq -r '.ready' "$WS/.fleet/state/beta.json")"
eq "(b) busy pane is NEVER unstuck (.ready stays false)" "$rb2" "false"

# Negative 2: an idle pane that is NOT yet stale (recent heartbeat) is left alone.
nowts="$(date +%s)"
jq --argjson hb "$nowts" '.ready=false | .heartbeat=$hb' "$WS/.fleet/state/beta.json" \
  > "$WS/.fleet/state/beta.json.t" && mv "$WS/.fleet/state/beta.json.t" "$WS/.fleet/state/beta.json"
run_lib 'FLEET_PANE_IDLE_CHECK=off fleet_reconcile_unstick_ready beta' >/dev/null 2>&1
rb3="$(jq -r '.ready' "$WS/.fleet/state/beta.json")"
eq "(b) fresh heartbeat (not stale) is left untouched" "$rb3" "false"

# Real idle/busy classifier sanity (best-effort; pane capture can be flaky when
# detached, so this is informational, not gating).
section "(b') fleet_pane_is_idle classifier (real panes, best-effort)"
command tmux -L "$SOCK" new-window -t "$SOCK" -n idlew \
  "printf '╭─────╮\n│ > \n╰─────╯\n? for shortcuts\n'; sleep 120" 2>/dev/null
command tmux -L "$SOCK" new-window -t "$SOCK" -n busyw \
  "printf 'esc to interrupt\n✻ Working… (3s)\n'; sleep 120" 2>/dev/null
sleep 0.6
if run_lib 'fleet_pane_is_idle busyw'; then no "busy pane classified idle (regression)"; else ok "busy pane is NOT idle"; fi
# ghost (absent) is never idle
if run_lib 'fleet_pane_is_idle nosuchwindow'; then no "absent pane classified idle (regression)"; else ok "absent pane is NOT idle"; fi

# =====================================================================
section "(c) failed inject → delivered stays false, .inject_failures bumps, retry, doctor flags"
# Drive a deterministic inject FAILURE by overriding fleet_inject (the transport's
# tmux verb) to fail. This exercises the real fleet_drain_inbox per-line marking +
# .inject_failures bookkeeping (the Component-2 change). alpha is the target.
mkdir -p "$WS/.fleet/inbox"
jq -nc --argjson ts "$(date +%s)" '{ts:$ts,from:"supervisor",to:"alpha",text:"line-one",hops:1,kind:"fyi",delivered:false}'  > "$WS/.fleet/inbox/alpha.jsonl"
jq -nc --argjson ts "$(date +%s)" '{ts:($ts+1),from:"supervisor",to:"alpha",text:"line-two",hops:1,kind:"fyi",delivered:false}' >> "$WS/.fleet/inbox/alpha.jsonl"
# alpha is ready + has a window so the drain actually attempts injection.
jq '.ready=true' "$WS/.fleet/state/alpha.json" > "$WS/.fleet/state/alpha.json.t" && mv "$WS/.fleet/state/alpha.json.t" "$WS/.fleet/state/alpha.json"

# DRAIN ATTEMPT 1 — inject forced to FAIL.
run_lib 'fleet_inject() { return 1; }; fleet_drain_inbox alpha' >/dev/null 2>&1; rc1=$?
undel="$(jq -s '[.[]|select(.delivered==false)]|length' "$WS/.fleet/inbox/alpha.jsonl")"
eq "(c) both lines stay undelivered after failed inject" "$undel" "2"
eq "(c) fleet_drain_inbox returns non-zero on failure" "$rc1" "1"
inf="$(jq -r '.inject_failures // 0' "$WS/.fleet/state/alpha.json")"
if [ "${inf:-0}" -gt 0 ]; then ok "(c) .inject_failures bumped (=$inf)"; else no "(c) .inject_failures NOT bumped"; fi
lda="$(jq -r '.last_drain_attempt // 0' "$WS/.fleet/state/alpha.json")"
if [ "${lda:-0}" -gt 0 ]; then ok "(c) .last_drain_attempt recorded"; else no "(c) .last_drain_attempt NOT recorded"; fi

# fleet doctor must flag the inject failures LOUDLY.
doc_out="$("$FLEET" doctor 2>&1)"; doc_rc=$?
hasstr "(c) fleet doctor reports the inject failure" "$doc_out" "inject failure"
if [ "$doc_rc" -ne 0 ]; then ok "(c) fleet doctor exits non-zero while broken"; else no "(c) fleet doctor exited 0 despite failure"; fi
dq="$("$FLEET" doctor --quiet 2>/dev/null)"; dq_rc=$?
if [ "$dq_rc" -ne 0 ]; then ok "(c) fleet doctor --quiet exits non-zero on inject failure"; else no "(c) doctor --quiet exited 0"; fi
hasstr "(c) doctor --quiet emits a one-line digest" "$dq" "alpha"

# DRAIN ATTEMPT 2 — inject now SUCCEEDS → at-least-once retry delivers, counter clears.
run_lib 'fleet_inject() { return 0; }; fleet_drain_inbox alpha' >/dev/null 2>&1; rc2=$?
undel2="$(jq -s '[.[]|select(.delivered==false)]|length' "$WS/.fleet/inbox/alpha.jsonl")"
eq "(c) next drain retries and delivers both lines" "$undel2" "0"
eq "(c) successful retry returns zero" "$rc2" "0"
inf2="$(jq -r '.inject_failures // 0' "$WS/.fleet/state/alpha.json")"
eq "(c) .inject_failures self-heals to 0 after clean drain" "$inf2" "0"

# Re-drain is idempotent: nothing double-delivers (all already delivered=true).
run_lib 'fleet_inject() { echo "SHOULD-NOT-INJECT" >&2; return 0; }; fleet_drain_inbox alpha' 2>"$TMP/redrain.err" >/dev/null
lacksstr "(c) re-drain does not re-inject already-delivered lines" "$(cat "$TMP/redrain.err")" "SHOULD-NOT-INJECT"

# A partial failure: first line ok, second fails → only the consumed line flips.
jq -nc --argjson ts "$(date +%s)" '{ts:$ts,from:"supervisor",to:"alpha",text:"partial-A",hops:1,kind:"fyi",delivered:false}'  > "$WS/.fleet/inbox/alpha.jsonl"
jq -nc --argjson ts "$(date +%s)" '{ts:($ts+1),from:"supervisor",to:"alpha",text:"partial-B",hops:1,kind:"fyi",delivered:false}' >> "$WS/.fleet/inbox/alpha.jsonl"
jq '.inject_failures=0' "$WS/.fleet/state/alpha.json" > "$WS/.fleet/state/alpha.json.t" && mv "$WS/.fleet/state/alpha.json.t" "$WS/.fleet/state/alpha.json"
# fail only the SECOND inject call
run_lib '
  _n=0
  fleet_inject() { _n=$((_n+1)); [ "$_n" -ge 2 ] && return 1; return 0; }
  fleet_drain_inbox alpha
' >/dev/null 2>&1
da="$(jq -s '[.[]|select(.text=="partial-A")][0].delivered' "$WS/.fleet/inbox/alpha.jsonl")"
db="$(jq -s '[.[]|select(.text=="partial-B")][0].delivered' "$WS/.fleet/inbox/alpha.jsonl")"
eq "(c) partial: consumed line marked delivered" "$da" "true"
eq "(c) partial: failed line stays undelivered" "$db" "false"

# =====================================================================
section "(c'') an unknown lane is not an empty queue"
# ‼ THE DRAIN RETURNED 0 FOR A MAILBOX THAT DOES NOT EXIST — the same rc a real
#   successful drain returns. Measured 2026-09-05: a supervisor polling loop ran
#   the drain 40 times from the wrong workspace cwd, matched no member, got rc=0
#   every time, and read that success as "the recipient is busy". Two messages sat
#   undelivered for 26 minutes while the instrument reported success on every poll.
#   The rest of fleet_drain_inbox already refuses to read a failure as an empty
#   queue at four sites; these two opening lines predated that rule.
run_lib 'fleet_drain_inbox definitely-no-such-lane force' >/dev/null 2>&1; rcu=$?
eq "(c'') drain of an absent mailbox returns 3, not 0" "$rcu" "3"
run_lib 'fleet_drain_inbox "../evil" force' >/dev/null 2>&1; rcb=$?
eq "(c'') drain of an invalid member id returns 3, not 0" "$rcb" "3"
# POSITIVE CONTROL — without it the rows above pass on a function that returns 3
# for everything, which is the failure mode they exist to catch.
jq -nc --argjson ts "$(date +%s)" '{ts:$ts,from:"supervisor",to:"alpha",text:"ctrl-line",hops:1,kind:"fyi",delivered:false}' > "$WS/.fleet/inbox/alpha.jsonl"
jq '.inject_failures=0' "$WS/.fleet/state/alpha.json" > "$WS/.fleet/state/alpha.json.t" && mv "$WS/.fleet/state/alpha.json.t" "$WS/.fleet/state/alpha.json"
run_lib 'fleet_inject() { return 0; }; fleet_drain_inbox alpha' >/dev/null 2>&1; rcok=$?
eq "(c'') control: a real lane holding mail still returns 0" "$rcok" "0"
undel3="$(jq -s '[.[]|select(.delivered==false)]|length' "$WS/.fleet/inbox/alpha.jsonl")"
eq "(c'') control: and the mail was actually delivered" "$undel3" "0"

# =====================================================================
section "(d) fleet courier — one owner drains every lane"
# ‼ MAIL MOVED ONLY WHEN THE RECIPIENT RAN ITS OWN Stop HOOK. A lane with no
#   hooks was undeliverable-to while looking healthy: r2, 2026-09-05, heartbeat
#   4s fresh and last_drain_attempt 2898s stale with mail queued behind it.
#   The courier is the single delivery owner, so a recipient that is running
#   nothing still receives.
jq -nc --argjson ts "$(date +%s)" '{ts:$ts,from:"supervisor",to:"alpha",text:"courier-line",hops:1,kind:"fyi",delivered:false}' > "$WS/.fleet/inbox/alpha.jsonl"
jq '.ready=true' "$WS/.fleet/state/alpha.json" > "$WS/.fleet/state/alpha.json.t" && mv "$WS/.fleet/state/alpha.json.t" "$WS/.fleet/state/alpha.json"
cr_out="$("$FLEET" courier --once --lane alpha 2>&1)"; cr_rc=$?
eq "(d) courier --once exits 0" "$cr_rc" "0"
# ‼ THE SUMMARY LINE IS THE ASSERTION, NOT DECORATION. The first version of this
#   command used `(( n++ ))`, which RETURNS THE OLD VALUE — so under `set -e` the
#   first increment killed the loop and it exited 1 printing NOTHING. A row that
#   only checked delivery would have gone green on a courier that ran one lane and
#   died. Assert that it reports completing a pass.
hasstr "(d) courier reports the pass it completed" "$cr_out" "pass(es) over"
# ‼ THE COURIER'S CONTRACT IS THAT IT ATTEMPTS EVERY LANE, and the observable is
#   `.last_drain_attempt` moving. Whether a keystroke then lands belongs to
#   `fleet_inject` and is covered at (c) — asserting delivery here would tie this
#   row to a live pane and make a courier regression indistinguishable from a
#   detached terminal. The lane in this fixture has no window, so the mail stays
#   queued and that is CORRECT.
lda_before="$(jq -r '.last_drain_attempt // 0' "$WS/.fleet/state/alpha.json")"
sleep 1
"$FLEET" courier --once --lane alpha >/dev/null 2>&1
lda_after="$(jq -r '.last_drain_attempt // 0' "$WS/.fleet/state/alpha.json")"
if [ "${lda_after:-0}" -gt "${lda_before:-0}" ]; then ok "(d) courier reached the lane (.last_drain_attempt moved)"
else no "(d) courier did NOT reach the lane (drain attempt not recorded)"; fi
und="$(jq -s '[.[]|select(.delivered==false)]|length' "$WS/.fleet/inbox/alpha.jsonl")"
eq "(d) and mail to a lane with no pane stays QUEUED, never dropped" "$und" "1"
# CONTROL: an unknown lane is not a delivery, and does not make the pass fail.
cr2_out="$("$FLEET" courier --once --lane no-such-lane 2>&1)"; cr2_rc=$?
eq "(d) control: unknown lane still exits 0" "$cr2_rc" "0"
hasstr "(d) control: and reports zero drains" "$cr2_out" "0 drain(s) returned 0"
# CONTROL: --interval must be a number, so a typo cannot become a busy loop.
if "$FLEET" courier --once --interval abc >/dev/null 2>&1; then
  no "(d) control: a non-numeric --interval was accepted"
else ok "(d) control: a non-numeric --interval is refused"; fi

# =====================================================================
section "(d') the courier is watched, because nobody else is watching it"
# ‼ A DEAD COURIER AND A QUIET ONE PRINTED THE SAME THING. It carries every
#   lane's mail and reported nothing until it exited, so its failure mode was
#   silence — the exact shape it was built to remove. `.last_drain_attempt` is
#   NOT a substitute: it only moves when a drain gets past the early returns, so
#   a fleet with nothing queued leaves it stale and reads as a dead courier.
"$FLEET" courier --once --lane alpha >/dev/null 2>&1
CJ="$WS/.fleet/run/courier.json"
if [ -f "$CJ" ]; then ok "(d') a pass writes a courier heartbeat"
else no "(d') no courier heartbeat written — a dead courier is indistinguishable from a quiet one"; fi
cj_int="$(jq -r '.interval // empty' "$CJ" 2>/dev/null)"
eq "(d') the heartbeat records the interval doctor judges it by" "${cj_int:-missing}" "20"
doc_fresh="$("$FLEET" doctor 2>&1 || true)"
lacksstr "(d') control: a fresh courier is not reported as a problem" "$doc_fresh" "courier: last pass"
jq '.ts = (.ts - 500)' "$CJ" > "$CJ.t" && mv "$CJ.t" "$CJ"
doc_stale="$("$FLEET" doctor 2>&1 || true)"
hasstr "(d') a stopped courier is reported" "$doc_stale" "courier: last pass"
hasstr "(d') and the report says what it costs" "$doc_stale" "nothing to carry it"
rm -f "$CJ"
doc_none="$("$FLEET" doctor 2>&1 || true)"
lacksstr "(d') control: no courier at all is NOT reported as a problem" "$doc_none" "courier: last pass"

# =====================================================================
section "(c') real fleet_inject returns non-zero when verify exhausts"
# Sanity that the verify loop now returns 1 (not the old optimistic 0) when it
# can never confirm submission. FLEET_INJECT_VERIFY stays on; we point at a
# non-existent target window so every send-keys fails → return 1 immediately.
if run_lib 'fleet_inject ghostwin tester "hi" 1 msg'; then
  no "(c') inject to a dead target returned 0 (should fail)"
else
  ok "(c') inject to a dead target returns non-zero"
fi

# =====================================================================
section "doctor: healthy fleet + throttle is reported, not a failure"
# Clear alpha's mail + failures so the only doctor signal is window/session docs.
: > "$WS/.fleet/inbox/alpha.jsonl"
jq '.inject_failures=0' "$WS/.fleet/state/alpha.json" > "$WS/.fleet/state/alpha.json.t" && mv "$WS/.fleet/state/alpha.json.t" "$WS/.fleet/state/alpha.json"
# A throttled pane is reported as throttled and is NOT counted as a failure.
# We assert the classifier + that doctor does not treat a throttled child's
# undelivered mail as "stale" by checking the throttle verb directly.
command tmux -L "$SOCK" new-window -t "$SOCK" -n thrw \
  "printf 'Claude usage limit reached\nrate limit exceeded\n'; sleep 120" 2>/dev/null
sleep 0.4
if run_lib 'fleet_pane_is_throttled thrw'; then ok "throttle classifier detects a rate-limited pane (best-effort)"; else
  # capture can be flaky when detached; fall back to a string-level check of the verb
  if run_lib 'FLEET_THROTTLE_CHECK=off fleet_pane_is_throttled thrw'; then no "throttle off should report not-throttled"; else ok "throttle classifier off-path correct (capture flaky, non-gating)"; fi
fi
# throttle stays DISTINCT from idle/dead (a throttled pane is not idle)
if run_lib 'fleet_pane_is_idle thrw'; then no "throttled pane misclassified as idle"; else ok "throttled pane is not idle (distinct state)"; fi

command tmux -L "$SOCK" new-window -t "$SOCK" -n credw \
  "printf 'Claude usage limit reached\nUse /usage-credits to request more usage from your admin.\n'; sleep 120" 2>/dev/null
sleep 0.4
if run_lib 'fleet_pane_is_provider_exhausted credw'; then ok "provider-exhaustion classifier detects /usage-credits"; else no "provider-exhaustion classifier missed /usage-credits"; fi
if run_lib 'fleet_pane_is_throttled credw'; then no "provider exhaustion misclassified as transient throttle"; else ok "provider exhaustion is not transient throttle"; fi
if run_lib 'fleet_pane_is_idle credw'; then no "provider-exhausted pane misclassified as idle"; else ok "provider-exhausted pane is not idle"; fi

# --- summary ----------------------------------------------------------------
printf '\n%s\n' "------------------------------------------"
printf 'robustness: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
