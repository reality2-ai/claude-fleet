#!/usr/bin/env bash
# live-bench-codex.sh — LIVE bench for the Codex Model-B primitives (ADR-003).
# NOT a CI test: real `codex` calls (slow + costs), needs an authenticated codex.
# Proves codex exec resume delivers a turn programmatically with context persisting,
# through the shipped fleet_codex_start_session / fleet_codex_deliver_turn.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; export TOOL_ROOT="$ROOT"
# shellcheck disable=SC1091
for lib in common manifest registry provider tmux comms transport faculty faculty-bg; do source "$ROOT/lib/$lib.sh"; done
command -v "${FLEET_CODEX_BIN:-codex}" >/dev/null 2>&1 || { echo "codex not on PATH — skipping"; exit 0; }
export FLEET_SKIP_PERMISSIONS=on
DIR="$(mktemp -d)"; ( cd "$DIR" && git init -q 2>/dev/null ); trap 'rm -rf "$DIR"' EXIT

SID="$(fleet_codex_start_session "$DIR" "Remember the number 42. Reply with exactly: OK")"
echo "codex session=[$SID]"
[ -n "$SID" ] || { echo "FAIL: no session id captured"; exit 1; }
R="$(fleet_codex_deliver_turn "$SID" "$DIR" "What number did I ask you to remember? Reply with just the number.")"
echo "resume reply=[$R]"
case "$R" in *42*) echo "PASS: codex programmatic delivery + persistence via shipped primitive";; *) echo "FAIL: expected 42"; exit 1;; esac
