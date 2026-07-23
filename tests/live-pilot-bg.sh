#!/usr/bin/env bash
# Live pilot: mount ONE throwaway worker via the claude-bg adapter, prove the full
# lifecycle (durable-session start + controller-in-tmux-window + keystroke-free
# delivery). Isolated: private socket/workspace; does not touch the real fleet.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TOOL_ROOT="$ROOT"
export FLEET_FACULTY_ADAPTER=claude-bg
export FLEET_TMUX_USER_SCOPE=off FLEET_SKIP_PERMISSIONS=on FLEET_BG_POLL=5
S="bgpilot$$"; export FLEET_TMUX_SOCKET="$S" FLEET_TMUX_SESSION="$S"
WS="$(mktemp -d)"; export FLEET_WORKSPACE="$WS"
mkdir -p "$WS/.fleet" "$WS/repo" && ( cd "$WS/repo" && git init -q )
cat > "$WS/.fleet/fleet.toml" <<TOML
[supervisor]
strategy = "one_for_one"
[[child]]
id   = "pilot"
cwd  = "repo"
seed = "Reply with exactly: READY"
TOML
cleanup(){ command tmux -L "$S" kill-server 2>/dev/null; rm -rf "$WS"; }
trap cleanup EXIT

# shellcheck disable=SC1090
for lib in common manifest registry provider tmux comms transport faculty faculty-bg; do source "$ROOT/lib/$lib.sh"; done
fleet_load_paths; fleet_manifest_load "$MANIFEST"

echo "=== faculty_mount pilot (claude-bg) ==="
faculty_mount pilot
sleep 2
echo "window present (unified view)? : $(fleet_tmux_has_window pilot && echo YES || echo NO)"

echo "=== wait for the controller to establish a durable session… ==="
for i in $(seq 1 24); do
  sid="$(fleet_state_get pilot '.session_id' '')"
  [[ -n "$sid" && "$sid" != null ]] && break; sleep 5
done
echo "session_id = [$(fleet_state_get pilot '.session_id' '')]"

echo "=== deliver a message keystroke-free (enqueue → controller drains as a turn) ==="
fleet_enqueue pilot supervisor "What is 2+2? Reply with just the number."
echo "enqueued; waiting for the controller to drain it…"
for i in $(seq 1 18); do
  undel="$(jq -s '[.[]|select(.delivered==false)]|length' "$(fleet_inbox_file pilot)" 2>/dev/null || echo 1)"
  [[ "$undel" == "0" ]] && break; sleep 5
done
echo "undelivered remaining = $undel  (0 = delivered keystroke-free)"

echo "=== controller window render (last lines) ==="
fleet_tmux capture-pane -p -t "$FLEET_TMUX_SESSION:pilot" 2>/dev/null | grep -vE '^[[:space:]]*$' | tail -12

echo "=== VERDICT ==="
sid="$(fleet_state_get pilot '.session_id' '')"
[[ -n "$sid" && "$sid" != null && "$undel" == "0" ]] && echo "PASS: claude-bg lifecycle — session established + message delivered keystroke-free, worker visible as a tmux window" || echo "INCOMPLETE (sid=$sid undel=$undel)"
