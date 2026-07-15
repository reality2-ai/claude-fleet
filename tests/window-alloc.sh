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
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh" 2>/dev/null || true
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

printf '\n----------------------------------------\n'
printf 'window-alloc: %s%d passed%s, %s%d failed%s\n' "$_grn" "$pass" "$_rst" \
  "$([[ "$fail" -gt 0 ]] && printf '%s' "$_red" || printf '%s' "$_grn")" "$fail" "$_rst"
[[ "$fail" -eq 0 ]]
