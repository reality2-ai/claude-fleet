#!/usr/bin/env bash
# config.sh — tests for the per-workspace .fleet/env mechanism + window_activity
# wiring into fleet_last_activity. Hermetic; requires bash >= 4, jq.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export TOOL_ROOT="$ROOT"
# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"

section "1. .fleet/env is sourced by fleet_load_paths"
WS="$TMP/ws"; mkdir -p "$WS/.fleet/state" "$WS/.fleet/run" "$WS/.fleet/log"
printf 'export FLEET_SENTINEL_XYZ=hello\nexport FLEET_TMUX_REMAIN_ON_EXIT=on\n' > "$WS/.fleet/env"
( export FLEET_WORKSPACE="$WS"; fleet_load_paths
  [[ "${FLEET_SENTINEL_XYZ:-}" == "hello" ]] ) && ok "custom var from .fleet/env is applied" || no "env not sourced"
# absent env file → no error, no var
WS2="$TMP/ws2"; mkdir -p "$WS2/.fleet/state"
( export FLEET_WORKSPACE="$WS2"; fleet_load_paths
  [[ -z "${FLEET_SENTINEL_ABC:-}" ]] ) && ok "absent .fleet/env is a clean no-op" || no "absent env errored"

section "2. workspace identity isolates concurrent fleets"
identity_for() {
  (
    unset FLEET_TMUX_SESSION FLEET_TMUX_SOCKET FLEET_TMUX_UNIT FLEET_SERVICE_NAME
    unset _FLEET_AUTO_TMUX_SESSION _FLEET_AUTO_TMUX_SOCKET _FLEET_AUTO_TMUX_UNIT _FLEET_AUTO_SERVICE_NAME
    export FLEET_WORKSPACE="$1"
    fleet_load_paths
    printf '%s|%s|%s|%s\n' "$FLEET_WORKSPACE_ID" "$FLEET_TMUX_SOCKET" "$FLEET_TMUX_SESSION" "$FLEET_SERVICE_NAME"
  )
}
WA="$TMP/a/project"; WB="$TMP/b/project"
mkdir -p "$WA/.fleet" "$WB/.fleet" "$WA/nested/.fleet"
: > "$WA/.fleet/fleet.toml"; : > "$WB/.fleet/fleet.toml"
IDA="$(identity_for "$WA")"; IDB="$(identity_for "$WB")"; IDA2="$(identity_for "$WA")"
[[ "$IDA" != "$IDB" ]] && ok "same-named workspaces get different fleet identities" || no "workspace identities collided"
[[ "$IDA" == "$IDA2" ]] && ok "one workspace keeps a stable fleet identity" || no "workspace identity was unstable"
[[ "${IDA%%|*}" =~ ^fleet-[a-z0-9-]+$ ]] && ok "derived identity is tmux/systemd safe" || no "unsafe derived identity: $IDA"
NESTED="$(cd "$WA/nested" && unset FLEET_WORKSPACE && fleet_find_workspace)"
[[ "$NESTED" == "$WA" ]] && ok "manifest-less nested .fleet does not shadow its parent fleet" || no "nested discovery chose '$NESTED'"
(
  unset _FLEET_AUTO_TMUX_SESSION _FLEET_AUTO_TMUX_SOCKET _FLEET_AUTO_TMUX_UNIT _FLEET_AUTO_SERVICE_NAME
  export FLEET_WORKSPACE="$WA" FLEET_TMUX_SESSION=custom-session FLEET_TMUX_SOCKET=custom-socket
  fleet_load_paths
  [[ "$FLEET_TMUX_SESSION" == custom-session && "$FLEET_TMUX_SOCKET" == custom-socket ]]
) && ok "explicit tmux identity overrides are preserved" || no "explicit tmux identity was replaced"

section "3. window_activity wiring into fleet_last_activity"
# shellcheck disable=SC1091
for lib in manifest registry provider tmux comms transport faculty; do source "$ROOT/lib/$lib.sh"; done
export WORKSPACE="$TMP/ws3" STATE_DIR="$TMP/ws3/.fleet"
export CHILDSTATE_DIR="$STATE_DIR/state" RUN_DIR="$STATE_DIR/run" LOG_FILE="$STATE_DIR/log/fleet.log" MANIFEST="$STATE_DIR/fleet.toml"
mkdir -p "$CHILDSTATE_DIR" "$RUN_DIR" "$(dirname "$LOG_FILE")"
fleet_state_ensure node1 "$TMP" true
fleet_state_jq node1 '.heartbeat=1000' >/dev/null   # known baseline activity

# stub fleet_tmux_window_activity to a known-larger epoch; with the flag on it must win
fleet_tmux_window_activity() { echo 5000; }
got_on="$( FLEET_TMUX_ACTIVITY=on  fleet_last_activity node1 )"
got_off="$( FLEET_TMUX_ACTIVITY=off fleet_last_activity node1 )"
[[ "$got_on"  == "5000" ]] && ok "FLEET_TMUX_ACTIVITY=on folds in window_activity" || no "on: got '$got_on' want 5000"
[[ "$got_off" == "1000" ]] && ok "FLEET_TMUX_ACTIVITY=off ignores window_activity"  || no "off: got '$got_off' want 1000"
# never DECREASES activity: a smaller window_activity must not lower best
fleet_tmux_window_activity() { echo 1; }
got_small="$( FLEET_TMUX_ACTIVITY=on fleet_last_activity node1 )"
[[ "$got_small" == "1000" ]] && ok "window_activity never lowers last-activity" || no "regressed: got '$got_small'"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
