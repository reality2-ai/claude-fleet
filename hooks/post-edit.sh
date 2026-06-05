#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit|NotebookEdit) — record the edited file
# as a claim for conflict detection. Keeps the most recent 50 claims.
# shellcheck source-path=SCRIPTDIR source=hook-common.sh
source "$(cd "$(dirname "$0")" && pwd)/hook-common.sh"

FP="$(hjq '.tool_input.file_path')"
[[ -z "$FP" ]] && FP="$(hjq '.tool_input.notebook_path')"
[[ -z "$FP" ]] && exit 0
# normalise to absolute
[[ "$FP" != /* ]] && FP="$CWD/$FP"

fleet_state_jq "$CHILD_ID" --arg p "$FP" --argjson now "$NOW" '
    .claims = ((.claims // []) + [$p] | unique)
  | (if (.claims | length) > 50 then .claims |= .[-50:] else . end)
  | .heartbeat = $now | .state = "running"' >/dev/null 2>&1 || true
exit 0
