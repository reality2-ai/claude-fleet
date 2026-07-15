#!/usr/bin/env bash
# window-alloc.sh — regression guard for #66: fleet spawns must never collide with a
# window whose NAME resembles the tmux SESSION name.
#
# GROUND TRUTH of the bug (reproduced live 2026-07-15 against tmux 3.7b):
#   `fleet refute --provider codex --id X supervisor "probe"`
#     -> create window failed: index 11 in use
#   ...where 11 was the index of the window named `fleet-fix`. The error index TRACKED
#   that window as it moved (12 earlier, 11 later) — it was never a base-index, a
#   renumber-windows, a phantom-member, or a member-count effect.
#
# MECHANISM: `tmux new-window -t "fleet"` parses `fleet` as a target-WINDOW and resolves
# it by window-NAME match, which PREFIX-matches the window `fleet-fix`. new-window then
# tries to create AT that window's index -> "index N in use". Adding the explicit EMPTY
# window component (`-t "fleet:"`) forces session-only resolution -> next unused index.
#
# The collision needs a window named like the session, so a fixture with generic window
# names (w0, w1, ...) CANNOT reproduce it and will pass against the broken code. That is
# precisely how this bug survived an earlier fix round — every assertion below therefore
# names a window after the session.
#
# Requires: bash >= 4, tmux.  Usage: tests/window-alloc.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }

SOCK="walloc$$"
SESSION="fleet"
cleanup() { command tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tm() { command tmux -L "$SOCK" "$@"; }

# Build a session named `fleet` holding a window named `fleet-fix` — the live topology
# that triggers #66. `fleet-fix` is deliberately NOT the last window, so "next free
# index" and "the colliding index" are different numbers and the assertions can tell a
# real fix from an accident of ordering.
build() {
  cleanup
  # kill-server returns before the server has finished exiting; creating a session against
  # a dying server yields "server exited unexpectedly". Wait for it to actually go away.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    tm list-sessions >/dev/null 2>&1 || break
    sleep 0.2
  done
  tm new-session -d -s "$SESSION" -n supervisor 'sleep 300'
  local n
  for n in supervisor-codex core hive fleet-fix website-merge; do
    tm new-window -t "$SESSION:" -n "$n" 'sleep 300' >/dev/null
  done
}

section "A. the bug reproduces with a session-named window (guards the fixture itself)"
build
FIX_IDX="$(tm display-message -p -t "$SESSION:fleet-fix" '#{window_index}')"
if [[ "$FIX_IDX" == "4" ]]; then ok "fixture: window 'fleet-fix' sits at index 4 (not last)"
else no "fixture: expected fleet-fix at index 4, got '$FIX_IDX'"; fi

# The BROKEN shape must still fail — if this ever starts passing, tmux's target
# resolution changed and the rest of this file is no longer testing anything.
err="$(tm new-window -t "$SESSION" -n probe-broken 'sleep 300' 2>&1)"
if [[ "$err" == *"index $FIX_IDX in use"* ]]; then
  ok "bare '-t \$SESSION' collides with the fleet-* window (index $FIX_IDX in use)"
else
  no "bare '-t \$SESSION' no longer reproduces the collision (got: ${err:-<success>})"
fi

# The FIXED shape must allocate the next unused index instead.
if tm new-window -t "$SESSION:" -n probe-fixed 'sleep 300' 2>/dev/null; then
  ok "'-t \$SESSION:' allocates a free index despite the fleet-* window"
else
  no "'-t \$SESSION:' failed to allocate"
fi
tm kill-window -t "$SESSION:probe-fixed" 2>/dev/null

section "B. every production spawn site targets \"\$FLEET_TMUX_SESSION:\""
# Static guard: a bare -t "$FLEET_TMUX_SESSION" in any new-window is the bug.
bare="$(grep -rn 'new-window -t "\$FLEET_TMUX_SESSION"' "$ROOT/bin/fleet" "$ROOT/lib" 2>/dev/null)"
if [[ -z "$bare" ]]; then
  ok "no production new-window uses a bare '-t \$FLEET_TMUX_SESSION'"
else
  no "bare session target still present:"; printf '       %s\n' "$bare"
fi

for site in "bin/fleet:cmd_ask" "lib/tmux.sh:fleet_tmux_new_agent_window" "lib/faculty-bg.sh:bg spawn"; do
  f="${site%%:*}"; what="${site##*:}"
  if grep -q 'new-window -t "\$FLEET_TMUX_SESSION:"' "$ROOT/$f" 2>/dev/null; then
    ok "$f ($what) targets \"\$FLEET_TMUX_SESSION:\""
  else
    no "$f ($what) does NOT target \"\$FLEET_TMUX_SESSION:\""
  fi
done

section "C. end-to-end: a real spawn survives a session-named window"
# Drive the REAL fleet_tmux_new_agent_window against the triggering topology, rather
# than asserting on the source text alone.
build
TMP="$(mktemp -d)"; trap 'cleanup; rm -rf "$TMP"' EXIT
export FLEET_TMUX_SOCKET="$SOCK" FLEET_TMUX_SESSION="$SESSION"
export TOOL_ROOT="$ROOT" RUN_DIR="$TMP/run"; mkdir -p "$RUN_DIR"
# common.sh FIRST: tmux.sh's spawn guard calls fleet_valid_member_id/fleet_run_path/warn,
# which live there. (Production always sources common first — bin/fleet, the hooks, and
# bg-controller all do; tmux.sh itself sources nothing.)
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=../lib/tmux.sh
source "$ROOT/lib/tmux.sh"
STUB="$TMP/stub"; printf '#!/usr/bin/env bash\nexec sleep 300\n' > "$STUB"; chmod +x "$STUB"
declare -a cargs=("$STUB")
out="$(fleet_tmux_new_agent_window "spawned-worker" "$TMP" "$TMP/exit" claude cargs 2>&1)"
if [[ "$out" != *"in use"* ]]; then
  ok "fleet_tmux_new_agent_window spawns without an index collision"
else
  no "fleet_tmux_new_agent_window still collides: $out"
fi
if tm list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "spawned-worker"; then
  ok "the spawned window actually exists"
else
  no "the spawned window was not created"
fi
# the pre-existing fleet-* window must be untouched by the allocation
if tm list-windows -t "$SESSION" -F '#{window_index} #{window_name}' 2>/dev/null | grep -qx "$FIX_IDX fleet-fix"; then
  ok "the fleet-fix window is preserved at its index"
else
  no "the fleet-fix window was displaced or killed"
fi

section "D. flag-like member ids are rejected at registration (phantom-member guard)"
# Live .fleet/state held --help.json and --.json: misparsed flags registered as members.
export CHILDSTATE_DIR="$TMP/state"; mkdir -p "$CHILDSTATE_DIR"
# shellcheck source=../lib/registry.sh
source "$ROOT/lib/registry.sh"
for bad in "--help" "-x" "--" "" "a/b" ".." "x/../y"; do
  if fleet_valid_member_id "$bad"; then
    no "id '$bad' should be rejected but was accepted"
  else
    ok "id '${bad:-<empty>}' rejected"
  fi
done
for good in "specs" "core-codex" "fleet-fix" "supervisor" "a_b.c"; do
  if fleet_valid_member_id "$good"; then ok "id '$good' accepted"; else no "id '$good' should be valid"; fi
done
# and the guard must actually fire through fleet_state_ensure (subshell: die exits)
if ( fleet_state_ensure "--help" "$TMP" false ) >/dev/null 2>&1; then
  no "fleet_state_ensure registered a flag-like id"
else
  ok "fleet_state_ensure refuses a flag-like id"
fi
if [[ ! -f "$CHILDSTATE_DIR/--help.json" ]]; then ok "no phantom state doc written"; else no "phantom --help.json was created"; fi

section "E. an invalid id fails CLOSED at every path/boundary primitive"
# GROUND TRUTH (all reproduced against 0ab4a0e on 2026-07-15, before this fix):
#   fleet_state_jq '../victim' '.state="pwned"'      -> rewrote a doc OUTSIDE CHILDSTATE_DIR
#   fleet_journal_append '../../escaped'             -> wrote a journal outside the state dir
#   fleet_write_agent_argv_file '../../pwned'        -> wrote an argv file outside RUN_DIR
#   rm -f "$RUN_DIR/../keepme.exit"  (start_child)   -> DELETED an out-of-tree file
# Section D proves REGISTRATION rejects a bad id. That was never sufficient: registration
# is not a boundary an ALREADY-EXISTING file has to cross (fleet_state_jq short-circuits
# fleet_state_ensure when the doc exists), and the launch path reached registration only
# AFTER creating/destroying artifacts. So E asserts on the ARTIFACTS, not on the validator.
E_TMP="$TMP/e"; mkdir -p "$E_TMP"
export WORKSPACE="$E_TMP/ws"; mkdir -p "$WORKSPACE"
export STATE_DIR="$E_TMP/.fleet"
# CHILDSTATE_DIR one level DOWN, so '../victim' names a real sibling doc — the exact
# shape of the reported falsifier. A test rooted at the top of the tree cannot see this.
export CHILDSTATE_DIR="$STATE_DIR/state/subdir" RUN_DIR="$E_TMP/run"
export LOG_FILE="$STATE_DIR/log/fleet.log"
mkdir -p "$CHILDSTATE_DIR" "$RUN_DIR" "$STATE_DIR/inbox" "$(dirname "$LOG_FILE")"
# The libs fleet_tmux_start_child resolves at call time (fleet_child_get, provider
# lookup, fleet_peer_primer, fleet_enqueue). Without these, start_child aborts on an
# unbound `primer` long before it reaches the `rm -f` E6 is about — i.e. E6 would pass
# against the BROKEN code for the wrong reason. Verified: with them sourced, E6 fails
# against 0ab4a0e ("RESULT: DELETED") and passes here.
# shellcheck disable=SC1091
for _lib in manifest provider comms transport faculty; do source "$ROOT/lib/$_lib.sh"; done

VICTIM="$STATE_DIR/state/victim.json"
printf '{"id":"victim","state":"running","secret":"ORIGINAL"}\n' > "$VICTIM"

# E1 — the falsifier itself: an existing doc outside CHILDSTATE_DIR must be untouchable.
fleet_state_jq '../victim' '.state="pwned" | .secret="MUTATED"' >/dev/null 2>&1
if grep -q 'ORIGINAL' "$VICTIM" && ! grep -q 'MUTATED' "$VICTIM"; then
  ok "fleet_state_jq '../victim' cannot mutate a state doc outside CHILDSTATE_DIR"
else
  no "fleet_state_jq '../victim' MUTATED an out-of-tree state doc: $(cat "$VICTIM")"
fi
if fleet_state_jq '../victim' '.x=1' >/dev/null 2>&1; then
  no "fleet_state_jq returned success for an invalid id"
else
  ok "fleet_state_jq reports failure for an invalid id"
fi

# E2 — the path primitives print nothing and fail, rather than yielding an escaping path.
for bad in "../victim" "a/b" "--help" ".." ""; do
  if p="$(fleet_state_path "$bad" 2>/dev/null)"; then
    no "fleet_state_path accepted '$bad' -> $p"
  elif [[ -n "$p" ]]; then
    no "fleet_state_path printed a path for '$bad' despite failing: $p"
  else
    ok "fleet_state_path refuses '${bad:-<empty>}' (no path, non-zero)"
  fi
done

# E3 — journal must not escape the state dir.
FLEET_JOURNAL=on fleet_journal_append '../../escaped' "INJECTED" 2>/dev/null || true
if [[ -e "$STATE_DIR/escaped.journal" || -e "$E_TMP/escaped.journal" ]]; then
  no "fleet_journal_append escaped the state dir"
else
  ok "fleet_journal_append cannot escape the state dir"
fi

# E4 — read primitives answer the default instead of reading an out-of-tree file.
got="$(fleet_state_get '../victim' '.secret' 'DEFAULT')"
if [[ "$got" == "DEFAULT" ]]; then ok "fleet_state_get returns the default for an invalid id"
else no "fleet_state_get read an out-of-tree doc (got '$got')"; fi

# E5 — run-file paths cannot escape RUN_DIR, and the argv writer creates nothing.
declare -a eargs=("$STUB")
fleet_write_agent_argv_file '../../pwned' eargs >/dev/null 2>&1 || true
if [[ -e "$E_TMP/pwned.argv" || -e "$TMP/pwned.argv" ]]; then
  no "fleet_write_agent_argv_file escaped RUN_DIR"
else
  ok "fleet_write_agent_argv_file cannot escape RUN_DIR"
fi
if fleet_run_path '../../pwned' .argv >/dev/null 2>&1; then no "fleet_run_path accepted a traversal id"
else ok "fleet_run_path refuses a traversal id"; fi

# E6 — the launch path must not DESTROY an out-of-tree file. This is the ORDERING bug,
# and it is the sharpest one: against 0ab4a0e this call printed "invalid member id
# '../keepme'" AND deleted the file anyway — it refused the id only at
# fleet_state_ensure, long after `rm -f "$RUN_DIR/$id.exit"` had already run. Rejecting
# an id is worthless if the artifacts are gone by the time you reject it.
printf 'PRECIOUS\n' > "$E_TMP/keepme.exit"
( fleet_tmux_start_child '../keepme' ) >/dev/null 2>&1 || true
if [[ -f "$E_TMP/keepme.exit" ]] && grep -q PRECIOUS "$E_TMP/keepme.exit"; then
  ok "fleet_tmux_start_child does not rm an out-of-tree file before validating"
else
  no "fleet_tmux_start_child DELETED an out-of-tree file via '../keepme'"
fi

# E7 — no window is ever created for an invalid id (the artifact boundary).
declare -a wargs=("$STUB")
fleet_tmux_new_agent_window '../evil' "$TMP" "$TMP/exit" claude wargs >/dev/null 2>&1
rc=$?
if [[ "$rc" -ne 0 ]]; then ok "fleet_tmux_new_agent_window refuses an invalid id (rc=$rc)"
else no "fleet_tmux_new_agent_window accepted an invalid id"; fi
if tm list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -q 'evil'; then
  no "a window was created for an invalid id"
else
  ok "no window exists for an invalid id"
fi

# E8 — mail: --from/--to are argv-supplied, so the inbox writer must fail closed.
# shellcheck source=../lib/comms.sh
source "$ROOT/lib/comms.sh" 2>/dev/null || true
if declare -F fleet_enqueue >/dev/null 2>&1; then
  fleet_enqueue '../../mailbox' 'attacker' 'payload' 1 msg true >/dev/null 2>&1 || true
  if [[ -e "$STATE_DIR/mailbox.jsonl" || -e "$E_TMP/mailbox.jsonl" ]]; then
    no "fleet_enqueue wrote an inbox outside STATE_DIR/inbox"
  else
    ok "fleet_enqueue cannot write an inbox outside STATE_DIR/inbox"
  fi
fi

# E9 — the charset is the boundary, not just the path. An id also becomes a tmux window
# name and a `pkill -f` REGEX (fleet_bg_unmount), where '.*' turns the supposedly
# anchored pattern into match-everything and reaps every controller in the fleet. A
# denylist that only bans '/' and '..' lets all of these through.
for bad in ".*" "a*b" "x;y" 'a$b' 'a b' 'a|b' '`id`' '$(id)' "a'b" 'a"b' "a&b" "-x" "a
b"; do
  if fleet_valid_member_id "$bad"; then
    no "id '$bad' should be rejected by the allowlist but was accepted"
  else
    ok "id '$(printf '%q' "$bad")' rejected by the allowlist"
  fi
done

# E10 — REAL ids must still work. These are live member-id shapes taken from the running
# fleet on 2026-07-15; if the allowlist ever rejects one of these it is too tight.
for good in "core" "supervisor" "android-codex" "core-codex-claude-refute" "api-watchdog" \
            "composer-merge" "a_b.c" "fleet-fix" "id-hardening" "web2"; do
  if fleet_valid_member_id "$good"; then ok "live id shape '$good' still accepted"
  else no "live id shape '$good' was rejected — the allowlist is too tight"; fi
done
# and a valid id must still round-trip through the path helpers
if p="$(fleet_state_path "core")" && [[ "$p" == "$CHILDSTATE_DIR/core.json" ]]; then
  ok "a valid id still yields its state path"
else
  no "a valid id no longer yields its state path (got '${p:-<none>}')"
fi
if p="$(fleet_run_path "core" .exit)" && [[ "$p" == "$RUN_DIR/core.exit" ]]; then
  ok "a valid id still yields its run path"
else
  no "a valid id no longer yields its run path (got '${p:-<none>}')"
fi

# E11 — fail-closed must not become fail-FATAL. bin/fleet runs `set -euo pipefail`, so a
# BARE `x="$(fleet_inbox_file "$id")"` aborts the entire command the moment the helper
# starts returning non-zero for a junk id. Live state dirs really do contain such ids —
# '--help' is in the running fleet right now — so hardening the helper silently killed
# `fleet doctor` outright (no output, rc=1) until every call site handled the status.
# That is strictly worse than the traversal being guarded against, and only two unrelated
# RESUME assertions in smoke.sh caught it. This asserts it directly.
E11_WS="$TMP/e11ws"
mkdir -p "$E11_WS/repo" "$E11_WS/.fleet/state" "$E11_WS/.fleet/run" "$E11_WS/.fleet/log" "$TMP/e11home"
cat > "$E11_WS/.fleet/fleet.toml" <<'TOML'
[supervisor]
strategy="one_for_one"
[[child]]
id="alpha"
cwd="repo"
TOML
jq -n --arg cwd "$E11_WS/repo" '{id:"alpha",managed:true,provider:"claude",session_id:null,
  cwd:$cwd,pid:null,state:"running",current_task:null,claims:[],started_at:null,
  heartbeat:null,reason:null,restarts:[]}' > "$E11_WS/.fleet/state/alpha.json"
# the phantom, verbatim as it appears in a live state dir
printf '{"id":"--help","managed":true,"cwd":"/nonexistent","state":"running"}\n' \
  > "$E11_WS/.fleet/state/--help.json"
e11_out="$(HOME="$TMP/e11home" FLEET_WORKSPACE="$E11_WS" FLEET_RESUME_CHECK=on \
           FLEET_TMUX_SOCKET="$SOCK" FLEET_TMUX_SESSION="$SESSION" \
           "$ROOT/bin/fleet" doctor 2>&1)" || true
if [[ "$e11_out" == *"missing RESUME.md"* ]]; then
  ok "doctor still reports real problems alongside a '--help' phantom (no set -e abort)"
else
  no "doctor was ABORTED by a phantom id (set -e + failing path helper): ${e11_out:-<no output>}"
fi

section "F. bg-controller reap matches by EXACT argv identity, not an id-interpolated regex"
# CONFIRMED 2026-07-15 against 6d19957: fleet_bg_unmount built pkill -f 'bg-controller\.sh <id>$'.
# The allowlist admits '.', which in that regex matches ANY char, so reaping the VALID id
# 'a.b' matched a DIFFERENT controller running for 'aXb'. The fix compares the last argv
# token byte-for-byte via /proc. These assertions are READ-ONLY — they never pkill/kill.
# shellcheck source=../lib/faculty-bg.sh
source "$ROOT/lib/faculty-bg.sh" 2>/dev/null || true
# F0 — deterministic falsifier that goes RED against the unfixed source: the id-
# interpolated `pkill -f "bg-controller...` regex must be GONE. (The read-only /proc
# checks below can only verify the NEW matcher; against 6d19957 they simply SKIP, so
# this source assertion is what fails there.)
if grep -q 'pkill -f "bg-controller' "$ROOT/lib/faculty-bg.sh"; then
  no "fleet_bg_unmount still interpolates the id into a pkill regex (collision defect present)"
else
  ok "fleet_bg_unmount no longer interpolates the id into a pkill regex"
fi
if declare -F _fleet_bg_controller_pids >/dev/null 2>&1 && [[ -r /proc/self/cmdline ]]; then
  mkdir -p "$TMP/f"; F_SH="$TMP/f/bg-controller.sh"
  printf '#!/bin/bash\nsleep 30\n' > "$F_SH"; chmod +x "$F_SH"
  # a decoy controller for id 'aXb'; its cmdline retains '.../bg-controller.sh aXb'
  "$F_SH" aXb & F_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -r "/proc/$F_PID/cmdline" ]] && tr '\0' ' ' < "/proc/$F_PID/cmdline" | grep -q 'bg-controller.sh aXb' && break
    sleep 0.1
  done
  # (a) the collision is REAL: the old-style regex for 'a.b' matches the 'aXb' decoy
  if pgrep -f "bg-controller\.sh a.b\$" >/dev/null 2>&1; then
    ok "id-interpolated regex 'a.b' collides with the 'aXb' controller (this is the defect)"
  else
    no "expected the regex collision to reproduce but it did not (decoy not visible?)"
  fi
  # (b) the fix does NOT collide: exact identity for 'a.b' returns no pid
  if [[ -z "$(_fleet_bg_controller_pids 'a.b')" ]]; then
    ok "exact-identity reap for 'a.b' does NOT match the 'aXb' controller"
  else
    no "exact-identity reap for 'a.b' WRONGLY matched the 'aXb' controller"
  fi
  # (c) the fix still reaps the RIGHT controller: exact identity for 'aXb' -> the decoy pid
  if [[ "$(_fleet_bg_controller_pids 'aXb')" == "$F_PID" ]]; then
    ok "exact-identity reap for 'aXb' returns exactly its own controller pid"
  else
    no "exact-identity reap for 'aXb' did not return the decoy pid (got '$(_fleet_bg_controller_pids 'aXb')', want $F_PID)"
  fi
  kill "$F_PID" 2>/dev/null || true
else
  ok "SKIP section F — no _fleet_bg_controller_pids or no /proc on this host"
fi

section "G. a valid id + a pre-planted SYMLINK must not read or write out of tree"
# CONFIRMED 2026-07-15 against 6d19957 (the id is VALID; the attack is the symlink):
#   inbox/<id>.jsonl.lock -> `exec 9>` FOLLOWED it and TRUNCATED an out-of-tree victim.
# Same class: inbox append, journal >>, argv :>, and state read/write via jq. G asserts on
# the out-of-tree VICTIM (untouched) and on the in-tree path (link dropped / refused).
G_TMP="$TMP/g"; mkdir -p "$G_TMP/outside"
export STATE_DIR="$G_TMP/.fleet" CHILDSTATE_DIR="$G_TMP/.fleet/state" RUN_DIR="$G_TMP/run"
mkdir -p "$CHILDSTATE_DIR" "$STATE_DIR/inbox" "$RUN_DIR"
GID=core   # a perfectly valid id — validation cannot help here

# G1 — inbox LOCK symlink must not be followed and truncated.
printf 'PRECIOUS\n' > "$G_TMP/outside/lock_victim"
ln -s "$G_TMP/outside/lock_victim" "$STATE_DIR/inbox/$GID.jsonl.lock"
fleet_enqueue "$GID" attacker payload 1 msg true >/dev/null 2>&1 || true
if [[ -s "$G_TMP/outside/lock_victim" ]] && grep -q PRECIOUS "$G_TMP/outside/lock_victim"; then
  ok "fleet_enqueue lock does not follow a symlink to truncate an out-of-tree file"
else
  no "fleet_enqueue FOLLOWED the lock symlink and truncated an out-of-tree victim"
fi

# G2 — inbox APPEND through a symlinked mailbox must be refused.
# Clear G1's side effects first: its enqueue created a regular inbox/<id>.jsonl, which
# would make the `ln -s` below fail silently and never test the symlink case at all.
printf 'ORIGINAL\n' > "$G_TMP/outside/inbox_victim"
rm -f "$STATE_DIR/inbox/$GID.jsonl.lock" "$STATE_DIR/inbox/$GID.jsonl"
ln -s "$G_TMP/outside/inbox_victim" "$STATE_DIR/inbox/$GID.jsonl" || no "G2 setup: could not plant inbox symlink"
fleet_enqueue "$GID" attacker '{"pwn":1}' 1 msg true >/dev/null 2>&1 || true
if grep -q ORIGINAL "$G_TMP/outside/inbox_victim" && ! grep -q pwn "$G_TMP/outside/inbox_victim"; then
  ok "fleet_enqueue refuses to append through a symlinked inbox"
else
  no "fleet_enqueue appended through a symlinked inbox to an out-of-tree victim"
fi
rm -f "$STATE_DIR/inbox/$GID.jsonl"

# G3 — journal must not append through a symlink.
printf 'ORIGINAL\n' > "$G_TMP/outside/journal_victim"
ln -s "$G_TMP/outside/journal_victim" "$CHILDSTATE_DIR/$GID.journal"
FLEET_JOURNAL=on fleet_journal_append "$GID" "INJECT" 2>/dev/null || true
if grep -q ORIGINAL "$G_TMP/outside/journal_victim" && ! grep -q INJECT "$G_TMP/outside/journal_victim"; then
  ok "fleet_journal_append does not append through a symlink"
else
  no "fleet_journal_append appended through a symlink to an out-of-tree victim"
fi
rm -f "$CHILDSTATE_DIR/$GID.journal"

# G4 — argv writer must drop a squatted link and write a real file in place.
printf 'ORIGINAL\n' > "$G_TMP/outside/argv_victim"
ln -s "$G_TMP/outside/argv_victim" "$RUN_DIR/$GID.argv"
declare -a gargs=("$STUB" "--flag")
fleet_write_agent_argv_file "$GID" gargs >/dev/null 2>&1 || true
if grep -q ORIGINAL "$G_TMP/outside/argv_victim"; then
  ok "fleet_write_agent_argv_file did not write through the symlink (victim intact)"
else
  no "fleet_write_agent_argv_file wrote through a symlink to an out-of-tree victim"
fi
if [[ -f "$RUN_DIR/$GID.argv" && ! -L "$RUN_DIR/$GID.argv" ]]; then
  ok "argv path is a regular file after the squatted symlink was dropped"
else
  no "argv path is still a symlink (or missing) after write"
fi
rm -f "$RUN_DIR/$GID.argv"

# G5 — state READ through a symlink must return the default, not the out-of-tree secret.
printf '{"secret":"OUTOFTREE"}\n' > "$G_TMP/outside/state_victim"
ln -s "$G_TMP/outside/state_victim" "$CHILDSTATE_DIR/$GID.json"
got="$(fleet_state_get "$GID" '.secret' 'DEFAULT')"
if [[ "$got" == "DEFAULT" ]]; then
  ok "fleet_state_get refuses to read through a symlinked state doc"
else
  no "fleet_state_get READ an out-of-tree secret via a symlink (got '$got')"
fi

# G6 — state_jq must refuse the link, not read-through and replace it with a regular file
# carrying the leaked secret (what 6d19957 does: jq reads the target, mv replaces the link).
fleet_state_jq "$GID" '.mutated=true' >/dev/null 2>&1 || true
if [[ -L "$CHILDSTATE_DIR/$GID.json" ]]; then
  ok "fleet_state_jq refuses a symlinked doc (link intact, no read-through)"
elif grep -q OUTOFTREE "$CHILDSTATE_DIR/$GID.json" 2>/dev/null; then
  no "fleet_state_jq READ through the symlink and copied the out-of-tree secret in place"
else
  no "fleet_state_jq altered the symlinked doc path unexpectedly"
fi
rm -f "$CHILDSTATE_DIR/$GID.json"

printf '\n----------------------------------------\n'
printf 'window-alloc: %s%d passed%s, %s%d failed%s\n' "$_grn" "$pass" "$_rst" \
  "$([[ "$fail" -gt 0 ]] && printf '%s' "$_red" || printf '%s' "$_grn")" "$fail" "$_rst"
[[ "$fail" -eq 0 ]]
