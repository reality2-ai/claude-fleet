#!/usr/bin/env bash
# liveness.sh — refutation tests for tmux-native liveness (#{pane_dead} + the
# remain-on-exit hardening). Each test states a CONJECTURE and a falsifying setup.
#
# Hermetic: a private tmux socket, throwaway dirs. Requires: bash >= 4, jq, tmux.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }
eq()      { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got '$2' want '$3')"; fi; }
istrue()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
isfalse() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then no "$d"; else ok "$d"; fi; }

command -v tmux >/dev/null 2>&1 || { echo "tmux missing — skipping"; exit 0; }

# --- hermetic env -----------------------------------------------------------
TMP="$(mktemp -d)"
export TOOL_ROOT="$ROOT"
export FLEET_TMUX_USER_SCOPE=off
export FLEET_TMUX_SOCKET="livetest$$" FLEET_TMUX_SESSION="livetest$$"
export WORKSPACE="$TMP/ws"; export STATE_DIR="$WORKSPACE/.fleet"
export CHILDSTATE_DIR="$STATE_DIR/state" RUN_DIR="$STATE_DIR/run" LOG_FILE="$STATE_DIR/log/fleet.log"
export MANIFEST="$STATE_DIR/fleet.toml"
mkdir -p "$CHILDSTATE_DIR" "$RUN_DIR" "$(dirname "$LOG_FILE")"
cleanup(){ command tmux -L "$FLEET_TMUX_SOCKET" kill-server 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

# shellcheck disable=SC1091
for lib in common manifest registry provider tmux comms transport faculty; do
  source "$ROOT/lib/$lib.sh" || { echo "cannot source lib/$lib.sh"; exit 1; }
done

# helper: start a window running a given command, give it an id + a running state doc
mkwin() {  # mkwin <id> <cmd...>
  local id="$1"; shift
  fleet_tmux_ensure_session
  fleet_tmux new-window -t "$FLEET_TMUX_SESSION" -n "$id" -c "$TMP" "$@" 2>/dev/null
  fleet_state_ensure "$id" "$TMP" true
  fleet_state_jq "$id" '.state="running"' >/dev/null
}

# --- 1. helper sees a dead pane only when it lingers -------------------------
section "1. #{pane_dead} ground truth"
# CONJECTURE: a window whose command has EXITED, kept alive by remain-on-exit, is
# reported pane_dead; a live one is not.
mkwin live_one "sleep 60"
sleep 0.3
isfalse "live pane is NOT dead" fleet_tmux_pane_dead live_one
mkwin dead_one "sleep 30"       # start ALIVE so the option lands first
sleep 0.2
fleet_tmux set-option -w -t "$FLEET_TMUX_SESSION:dead_one" remain-on-exit on 2>/dev/null
# now respawn into a command that exits — remain-on-exit keeps the pane as a corpse
fleet_tmux respawn-window -k -t "$FLEET_TMUX_SESSION:dead_one" "true" 2>/dev/null
sleep 0.5
istrue "exited pane (remain-on-exit) IS dead" fleet_tmux_pane_dead dead_one
istrue "dead pane's window still exists"       fleet_tmux_has_window dead_one

# --- 2. fleet_liveness reports the dead pane as dead -------------------------
section "2. fleet_liveness native dead-detection"
# CONJECTURE: with native liveness on (default), a present-but-dead pane → 'dead'.
eq "dead lingering pane → liveness 'dead'" "$(fleet_liveness dead_one)" "dead"
# Refute the false-positive: a live pane must still read live/idle, never dead.
got="$(fleet_liveness live_one)"
if [[ "$got" == "live" || "$got" == "idle" ]]; then ok "live pane → live/idle (not dead)"; else no "live pane misread as '$got'"; fi
# Disable flag → the old answer (no dead-from-pane), even for a dead lingering pane.
got_off="$(FLEET_TMUX_NATIVE_LIVENESS=off fleet_liveness dead_one)"
if [[ "$got_off" != "dead" ]]; then ok "FLEET_TMUX_NATIVE_LIVENESS=off restores old behaviour"; else no "flag=off still returned dead"; fi

# --- 3. capability reflects the opt-in --------------------------------------
section "3. native_liveness capability is dynamic"
( unset FLEET_TMUX_REMAIN_ON_EXIT; faculty_capability native_liveness cli-tmux ) && no "default should be false" || ok "cli-tmux native_liveness FALSE by default"
( FLEET_TMUX_REMAIN_ON_EXIT=on; faculty_capability native_liveness cli-tmux ) && ok "native_liveness TRUE when remain-on-exit on" || no "should be true when opted in"

# --- 4. default config is a no-op (safety) ----------------------------------
section "4. default-config safety (no behaviour change)"
# CONJECTURE: without remain-on-exit, a window whose command exits VANISHES, so the
# native path never fires — liveness falls through to the existing logic.
mkwin gone_one "true"
sleep 0.4
isfalse "exited pane WITHOUT remain-on-exit leaves no window" fleet_tmux_has_window gone_one
eq "vanished worker → liveness 'dead' (unchanged path)" "$(fleet_liveness gone_one)" "dead"

# --- 5. set-hook pane-died → event-driven reap -------------------------------
section "5. pane-died death hook (functional; show-hooks doesn't list pane-died in 3.6)"
# CONJECTURE: with the hook ON + remain-on-exit, a dying pane runs `<FLEET_BIN> reap`
# (instant event-driven recovery); with it OFF, a dying pane does NOT.
MARKER="$TMP/reap-called"
STUB="$TMP/fleetstub"; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$MARKER" > "$STUB"; chmod +x "$STUB"
die_pane() {  # spawn a window, make it linger dead under remain-on-exit
  local w="$1"
  fleet_tmux new-window -t "$FLEET_TMUX_SESSION" -n "$w" -c "$TMP" "sleep 30" 2>/dev/null
  sleep 0.2; fleet_tmux set-option -w -t "$FLEET_TMUX_SESSION:$w" remain-on-exit on 2>/dev/null
  fleet_tmux respawn-window -k -t "$FLEET_TMUX_SESSION:$w" "true" 2>/dev/null
  sleep 0.8
}
# gated OFF → hook removed → a dying pane does NOT invoke reap
FLEET_TMUX_DEATH_HOOK=off fleet_tmux_install_server_hooks
rm -f "$MARKER"; die_pane dyer_off
[[ ! -f "$MARKER" ]] && ok "gated off → pane death does NOT reap" || no "off: reap fired unexpectedly"
# gated ON → hook installed → a dying pane invokes reap (our stub)
FLEET_TMUX_DEATH_HOOK=on FLEET_BIN="$STUB" fleet_tmux_install_server_hooks
rm -f "$MARKER"; die_pane dyer_on
if [[ -f "$MARKER" ]] && grep -q reap "$MARKER"; then ok "gated on → pane death invokes reap"; else no "on: death hook did not invoke reap"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
