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
for lib in common manifest registry provider tmux comms transport faculty faculty-bg; do
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

# --- 4b. claude-bg adapter slice (Model B delivery primitive) ----------------
section "4b. claude-bg adapter (delivery primitive)"
for v in fleet_bg_deliver_turn fleet_bg_drain; do
  if declare -F "$v" >/dev/null 2>&1; then ok "claude-bg fn defined: $v"; else no "claude-bg fn MISSING: $v"; fi
done
istrue  "claude-bg: durable_body"    faculty_capability durable_body claude-bg
istrue  "claude-bg: native_delivery" faculty_capability native_delivery claude-bg
# faculty_deliver routes to the bg drain under the claude-bg adapter
if declare -f faculty_deliver | grep -q 'claude-bg'; then ok "faculty_deliver has claude-bg branch"; else no "no claude-bg deliver branch"; fi
# claude-bg is CLAUDE-ONLY (codex = refuter, not a per-worker brain): the drain delivers
# via the claude primitive and must NOT dispatch to codex.
if declare -f fleet_bg_drain | grep -q 'fleet_bg_deliver_turn' && ! declare -f fleet_bg_drain | grep -q 'fleet_codex_deliver_turn'; then ok "fleet_bg_drain is claude-only (no codex dispatch)"; else no "drain still dispatches codex"; fi
# fleet_bg_mount diverts a codex worker to the cli-tmux path (refuter-only on bg)
if declare -f fleet_bg_mount | grep -q 'fleet_tmux_start_child'; then ok "fleet_bg_mount diverts codex → cli-tmux"; else no "mount has no codex divert"; fi
# unmount reaps the controller (orphaned/duplicate-controller fix)
if declare -F fleet_bg_unmount >/dev/null 2>&1 && declare -f fleet_bg_unmount | grep -q 'pkill'; then ok "fleet_bg_unmount reaps controller"; else no "no controller-reaping unmount"; fi
if declare -f faculty_unmount | grep -q '_faculty_adapter_for'; then ok "faculty_unmount resolves adapter per-worker"; else no "faculty_unmount uses global adapter"; fi
for v in fleet_bg_start_session fleet_bg_mount fleet_bg_unmount fleet_bg_has_mail; do
  if declare -F "$v" >/dev/null 2>&1; then ok "claude-bg lifecycle fn: $v"; else no "missing: $v"; fi
done
# codex primitives retained but DORMANT (proven building block for a future codex-bg adapter)
for v in fleet_codex_start_session fleet_codex_deliver_turn; do
  if declare -F "$v" >/dev/null 2>&1; then ok "codex primitive retained (dormant): $v"; else no "missing: $v"; fi
done
if declare -f faculty_mount | grep -q 'fleet_bg_mount'; then ok "faculty_mount has claude-bg branch"; else no "no claude-bg mount branch"; fi
# no durable session id → drain keeps mail queued (returns non-zero), never crashes
mkdir -p "$STATE_DIR/inbox"; printf '{"from":"x","to":"node9","text":"hi","delivered":false}\n' > "$STATE_DIR/inbox/node9.jsonl"
fleet_state_ensure node9 "$TMP" true   # no session_id
isfalse "bg_drain with no session id keeps mail queued" fleet_bg_drain node9
# mixed-adapter guard: the cli-tmux mail path must SKIP a claude-bg worker
fleet_state_ensure bgw "$TMP" true; fleet_state_jq bgw '.faculty="claude-bg"' >/dev/null
printf '{"from":"x","to":"bgw","text":"hi","delivered":false}\n' > "$(fleet_inbox_file bgw)"
isfalse "fleet_drain_inbox skips a claude-bg worker"  fleet_drain_inbox bgw
isfalse "fleet_inject skips a claude-bg worker"        fleet_inject bgw x "hi"
# per-worker adapter resolution (mixable claude-bg + cli-tmux in one fleet)
eq "adapter from state .faculty"      "$(_faculty_adapter_for bgw)" "claude-bg"
eq "adapter falls back to global"     "$(FLEET_FACULTY_ADAPTER=cli-tmux _faculty_adapter_for ghostX)" "cli-tmux"
cat > "$STATE_DIR/m.toml" <<TOML
[[child]]
id = "mw"
adapter = "claude-bg"
TOML
fleet_manifest_load "$STATE_DIR/m.toml"
eq "adapter from manifest field wins" "$(_faculty_adapter_for mw)" "claude-bg"
if declare -f faculty_mount | grep -q '_faculty_adapter_for'; then ok "faculty_mount routes per-worker"; else no "faculty_mount not per-worker"; fi

# --- 5. honest unimplemented verbs ------------------------------------------
section "5. unimplemented verbs fail honestly"
isfalse "spawn_tool returns non-zero (unimplemented)" faculty_spawn_tool x "task"
isfalse "stream returns non-zero (unimplemented)"     faculty_stream x

# --- summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
