#!/usr/bin/env bash
# Live codex-worker pilot: a provider=codex worker on the claude-bg controller.
# Proves the controller's codex dispatch end-to-end (establish codex session +
# keystroke-free delivery, in a tmux window). Isolated; codex is slow → generous waits.
set -u
ROOT="/home/roycdavies/Development/R2/claude-fleet"
export TOOL_ROOT="$ROOT" FLEET_TMUX_USER_SCOPE=off FLEET_SKIP_PERMISSIONS=on FLEET_BG_POLL=15 FLEET_BG_AUTONOMY=off
S="cxpilot$$"; export FLEET_TMUX_SOCKET="$S" FLEET_TMUX_SESSION="$S"
WS="$(mktemp -d)"; export FLEET_WORKSPACE="$WS"; mkdir -p "$WS/.fleet" "$WS/repo" && ( cd "$WS/repo" && git init -q )
cat > "$WS/.fleet/fleet.toml" <<TOML
[supervisor]
strategy = "one_for_one"
[[child]]
id       = "cxpilot"
cwd      = "repo"
provider = "codex"
adapter  = "claude-bg"
seed     = "Reply with exactly: READY"
TOML
cleanup(){ command tmux -L "$S" kill-server 2>/dev/null; rm -rf "$WS"; }; trap cleanup EXIT
# shellcheck disable=SC1090
for lib in common manifest registry provider tmux comms transport faculty faculty-bg; do source "$ROOT/lib/$lib.sh"; done
fleet_load_paths; fleet_manifest_load "$MANIFEST"

echo "=== faculty_mount cxpilot (provider=codex, adapter=claude-bg) ==="
faculty_mount cxpilot; sleep 2
echo "window present? $(fleet_tmux_has_window cxpilot && echo YES || echo NO); faculty=$(fleet_state_get cxpilot '.faculty' -); provider=$(fleet_state_get cxpilot '.provider' -)"
echo "=== wait for codex durable session (slow)… ==="
for i in $(seq 1 40); do sid="$(fleet_state_get cxpilot '.session_id' '')"; [[ -n "$sid" && "$sid" != null ]] && break; sleep 15; done
echo "session=[$(fleet_state_get cxpilot '.session_id' '')]"
echo "=== deliver a message keystroke-free (controller drains via codex exec resume) ==="
fleet_enqueue cxpilot supervisor "Reply in ONE short line: what is 7 times 6?"
for i in $(seq 1 40); do u="$(jq -s '[.[]|select(.delivered==false)]|length' "$(fleet_inbox_file cxpilot)" 2>/dev/null||echo 1)"; [[ "$u" == 0 ]] && break; sleep 15; done
echo "undelivered=$u"
echo "=== controller window render ==="
fleet_tmux capture-pane -p -t "$FLEET_TMUX_SESSION:cxpilot" 2>/dev/null | grep -vE '^[[:space:]]*$' | tail -12
echo "=== verdict ==="
sid="$(fleet_state_get cxpilot '.session_id' '')"
[[ -n "$sid" && "$sid" != null && "$u" == 0 ]] && echo "PASS: codex worker on claude-bg — session established + keystroke-free delivery via controller" || echo "INCOMPLETE (sid=$sid undel=$u)"
