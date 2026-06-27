#!/usr/bin/env bash
# run-argv-file.sh — exec a NUL-delimited argv stored on disk.
#
# This keeps very large agent prompts out of tmux's command argument, avoiding
# tmux's lower "command too long" ceiling while preserving provider argv exactly.
set -euo pipefail

argv_file="${1:?usage: run-argv-file.sh <argv-file>}"
args=()
while IFS= read -r -d '' arg; do
  args+=("$arg")
done <"$argv_file"

(( ${#args[@]} > 0 )) || exit 127
exec "${args[@]}"
