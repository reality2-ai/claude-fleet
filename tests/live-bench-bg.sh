#!/usr/bin/env bash
# live-bench-bg.sh — LIVE bench for the claude-bg adapter (Model B, ADR-003).
# NOT a CI test: it makes real `claude` calls (costs tokens) and needs an
# authenticated claude. Run manually to (re)confirm the substrate:
#
#   tests/live-bench-bg.sh
#
# Proves: programmatic turn-by-turn delivery via `claude -p --resume` with context
# persisting across turns (the delivery fix), using the shipped fleet_bg_deliver_turn.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TOOL_ROOT="$ROOT"
# shellcheck disable=SC1091
for lib in common manifest registry provider tmux comms transport faculty faculty-bg; do
  source "$ROOT/lib/$lib.sh"
done
command -v claude >/dev/null 2>&1 || { echo "claude not on PATH — skipping"; exit 0; }

DIR="$(mktemp -d)"; ( cd "$DIR" && git init -q 2>/dev/null ); trap 'rm -rf "$DIR"' EXIT
export FLEET_SKIP_PERMISSIONS=on

# Turn 1: create a durable session (capture its id from json), via raw claude -p.
out1="$( cd "$DIR" && claude -p --output-format json --dangerously-skip-permissions \
  "Remember the number 42. Reply with exactly: OK" 2>/dev/null )"
SID="$(jq -r '.session_id // empty' <<<"$out1")"
echo "session=[$SID] turn1=[$(jq -r '.result // empty' <<<"$out1")]"
[ -n "$SID" ] || { echo "FAIL: no session id"; exit 1; }

# Turn 2: deliver programmatically through the SHIPPED primitive.
R2="$(fleet_bg_deliver_turn "$SID" "$DIR" "What number did I ask you to remember? Reply with just the number.")"
echo "turn2 (via fleet_bg_deliver_turn)=[$R2]"
case "$R2" in
  *42*) echo "PASS: programmatic delivery + persistence via the shipped adapter primitive";;
  *)    echo "FAIL: expected 42, got [$R2]"; exit 1;;
esac
