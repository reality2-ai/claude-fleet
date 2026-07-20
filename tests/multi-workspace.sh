#!/usr/bin/env bash
# End-to-end proof that two folders can host independent fleets with identical ids.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLEET="$ROOT/bin/fleet"
TMP="$(mktemp -d)"
pass=0; fail=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

unset FLEET_WORKSPACE FLEET_TMUX_SOCKET FLEET_TMUX_SESSION FLEET_TMUX_UNIT FLEET_SERVICE_NAME
export HOME="$TMP/home" FLEET_TMUX_USER_SCOPE=off
mkdir -p "$HOME"

STUB="$TMP/claude"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >> "$FLEET_STUB_LOG"\nexec sleep 300\n' > "$STUB"
chmod +x "$STUB"
export FLEET_CLAUDE_BIN="$STUB"

WA="$TMP/a/project"; WB="$TMP/b/project"
for ws in "$WA" "$WB"; do
  mkdir -p "$ws/.fleet/state" "$ws/.fleet/run" "$ws/.fleet/log" "$ws/repo"
done
printf '[[child]]\nid="worker"\ncwd="repo"\nrestart="temporary"\nseed="seed-a"\n' > "$WA/.fleet/fleet.toml"
printf '[[child]]\nid="worker"\ncwd="repo"\nrestart="temporary"\nseed="seed-b"\n' > "$WB/.fleet/fleet.toml"

identity_value() {
  FLEET_WORKSPACE="$1" "$FLEET" identity | sed -n "s/^$2=//p"
}
SA="$(identity_value "$WA" socket)"; SB="$(identity_value "$WB" socket)"
NA="$(identity_value "$WA" session)"; NB="$(identity_value "$WB" session)"
cleanup() {
  [[ -n "$SA" ]] && command tmux -L "$SA" kill-server 2>/dev/null || true
  [[ -n "$SB" ]] && command tmux -L "$SB" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

[[ "$SA" != "$SB" && "$NA" != "$NB" ]] && ok "folders derive different tmux identities" || no "tmux identities collided"

export FLEET_STUB_LOG="$TMP/a.log"; : > "$FLEET_STUB_LOG"
FLEET_WORKSPACE="$WA" "$FLEET" up --no-supervisor --no-pairs worker >/dev/null
export FLEET_STUB_LOG="$TMP/b.log"; : > "$FLEET_STUB_LOG"
FLEET_WORKSPACE="$WB" "$FLEET" up --no-supervisor --no-pairs worker >/dev/null
sleep 0.5

command tmux -L "$SA" has-session -t "$NA" 2>/dev/null && \
  command tmux -L "$SA" list-windows -t "$NA" -F '#W' | grep -qxF worker && \
  ok "workspace A owns its worker" || no "workspace A worker missing"
command tmux -L "$SB" has-session -t "$NB" 2>/dev/null && \
  command tmux -L "$SB" list-windows -t "$NB" -F '#W' | grep -qxF worker && \
  ok "workspace B owns its worker" || no "workspace B worker missing"
grep -qxF seed-a "$TMP/a.log" && grep -qxF seed-b "$TMP/b.log" && \
  ok "each worker received only its workspace seed" || no "workspace prompts crossed"

FLEET_WORKSPACE="$WA" "$FLEET" down >/dev/null
if command tmux -L "$SA" has-session -t "$NA" 2>/dev/null; then no "workspace A survived its own down"
else ok "workspace A stopped independently"; fi
command tmux -L "$SB" has-session -t "$NB" 2>/dev/null && \
  command tmux -L "$SB" list-windows -t "$NB" -F '#W' | grep -qxF worker && \
  ok "stopping A leaves workspace B running" || no "stopping A affected workspace B"
FLEET_WORKSPACE="$WB" "$FLEET" down >/dev/null

printf '\nmulti-workspace: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
