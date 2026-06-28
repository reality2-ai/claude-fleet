#!/usr/bin/env bash
# faculty.sh — unit tests for the faculty-adapter seam (lib/faculty.sh).
#
# Verifies the contract surface exists, the capability matrix is correct, the action
# verbs delegate to the pre-existing functions (zero behaviour change), recall reads
# the durable head, and the not-yet-implemented verbs fail honestly.
#
# Hermetic: no real fleet, a throwaway workspace, an unused tmux socket (so liveness
# resolves to "dead" without touching anything). Requires: bash >= 4, jq.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }
# assert exit status: want 0 (true) / non-0 (false)
true_()  { if "$@" >/dev/null 2>&1; then ok "$1 [delegated]"; else no "$1"; fi; }   # unused placeholder
istrue() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
isfalse(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then no "$d"; else ok "$d"; fi; }
eq()     { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got '$2' want '$3')"; fi; }

# --- hermetic env -----------------------------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export TOOL_ROOT="$ROOT"
export FLEET_TMUX_USER_SCOPE=off
export FLEET_TMUX_SOCKET="facultytest$$" FLEET_TMUX_SESSION="facultytest$$"
# path globals (what fleet_load_paths would set), pointed into the temp dir
export WORKSPACE="$TMP/ws"; export STATE_DIR="$WORKSPACE/.fleet"
export CHILDSTATE_DIR="$STATE_DIR/state" RUN_DIR="$STATE_DIR/run" LOG_FILE="$STATE_DIR/log/fleet.log"
export MANIFEST="$STATE_DIR/fleet.toml"
mkdir -p "$CHILDSTATE_DIR" "$RUN_DIR" "$(dirname "$LOG_FILE")" "$STATE_DIR/memory"

# source the libs the way bin/fleet does (functions resolve at call time)
# shellcheck disable=SC1091
for lib in common manifest registry provider tmux comms transport faculty; do
  source "$ROOT/lib/$lib.sh" || { echo "cannot source lib/$lib.sh"; exit 1; }
done

# --- 1. syntax + contract surface -------------------------------------------
section "1. syntax + contract surface"
if bash -n "$ROOT/lib/faculty.sh" 2>/dev/null; then ok "bash -n clean"; else no "bash -n clean"; fi
for v in faculty_capability faculty_capabilities faculty_mount faculty_resume \
         faculty_unmount faculty_liveness faculty_deliver faculty_headless_answer \
         faculty_spawn_tool faculty_attach faculty_stream faculty_recall; do
  if declare -F "$v" >/dev/null 2>&1; then ok "verb defined: $v"; else no "verb MISSING: $v"; fi
done

# --- 2. capability matrix (verified 2026-06-29) -----------------------------
section "2. capability matrix"
istrue  "cli-tmux: durable_body"        faculty_capability durable_body cli-tmux
istrue  "cli-tmux: attachable"          faculty_capability attachable cli-tmux
istrue  "cli-tmux: native_tui"          faculty_capability native_tui cli-tmux
isfalse "cli-tmux: NOT native_delivery" faculty_capability native_delivery cli-tmux
isfalse "cli-tmux: NOT event_stream"    faculty_capability event_stream cli-tmux
istrue  "claude-bg: native_delivery"    faculty_capability native_delivery claude-bg
istrue  "codex-daemon: event_stream"    faculty_capability event_stream codex-daemon
isfalse "unknown cap is false"          faculty_capability no_such_cap cli-tmux
isfalse "unknown adapter is all-false"  faculty_capability durable_body no-such-adapter
eq "default adapter is cli-tmux" "$FLEET_FACULTY_ADAPTER" "cli-tmux"

# --- 3. delegation (zero behaviour change) ----------------------------------
section "3. delegation"
# liveness of an unknown id must equal fleet_liveness's answer ("dead": no doc, no window)
got_f="$(faculty_liveness ghost 2>/dev/null)"; got_l="$(fleet_liveness ghost 2>/dev/null)"
eq "liveness delegates to fleet_liveness" "$got_f" "$got_l"
eq "liveness of unknown id is dead" "$got_f" "dead"
# the verb bodies call the pre-existing functions verbatim
if declare -f faculty_mount   | grep -q 'fleet_tmux_start_child'; then ok "mount → fleet_tmux_start_child"; else no "mount delegation"; fi
if declare -f faculty_unmount | grep -q 'fleet_tmux_stop_child';  then ok "unmount → fleet_tmux_stop_child"; else no "unmount delegation"; fi
if declare -f faculty_deliver | grep -q 'transport_deliver';      then ok "deliver → transport_deliver"; else no "deliver delegation"; fi
if declare -f faculty_headless_answer | grep -q 'fleet_agent_headless_answer'; then ok "headless_answer → fleet_agent_headless_answer"; else no "headless_answer delegation"; fi

# --- 4. recall reads the durable head ---------------------------------------
section "4. recall (durable head)"
printf 'HEAD-MEMORY-MARKER\n' > "$STATE_DIR/memory/alpha.md"
out="$(faculty_recall alpha 2>/dev/null)"
if [[ "$out" == *HEAD-MEMORY-MARKER* ]]; then ok "recall returns the entity-memory head"; else no "recall head"; fi
isfalse "recall of an entity with no head fails" faculty_recall nobody
# RESUME.md fallback via the state doc's cwd
mkdir -p "$WORKSPACE/repoB"
printf 'RESUME-FALLBACK-MARKER\n' > "$WORKSPACE/repoB/RESUME.md"
fleet_state_ensure beta "$WORKSPACE/repoB" true
out="$(faculty_recall beta 2>/dev/null)"
if [[ "$out" == *RESUME-FALLBACK-MARKER* ]]; then ok "recall falls back to repo RESUME.md"; else no "recall RESUME fallback"; fi

# --- 5. honest unimplemented verbs ------------------------------------------
section "5. unimplemented verbs fail honestly"
isfalse "spawn_tool returns non-zero (unimplemented)" faculty_spawn_tool x "task"
isfalse "stream returns non-zero (unimplemented)"     faculty_stream x

# --- summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
