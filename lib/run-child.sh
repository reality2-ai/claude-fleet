#!/usr/bin/env bash
# run-child.sh — thin wrapper a tmux window runs so the supervisor can learn a
# child's exit code. Usage: run-child.sh <exitfile> -- <cmd> [args...]
exitfile="$1"; shift
[[ "${1:-}" == "--" ]] && shift
"$@"
rc=$?
printf '%s\n' "$rc" >"$exitfile" 2>/dev/null || true
exit "$rc"
