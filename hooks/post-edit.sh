#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit|NotebookEdit) — record the edited file
# as a claim for conflict detection. Keeps the most recent 50 claims.
# shellcheck source-path=SCRIPTDIR source=hook-common.sh
source "$(cd "$(dirname "$0")" && pwd)/hook-common.sh"

FP="$(hjq '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // .input.file_path // .input.path // .params.file_path // .params.path // .file_path // .path')"
[[ -z "$FP" ]] && FP="$(printf '%s' "$HOOK_JSON" | jq -r '[.. | objects | .file_path? // .path? // empty] | map(select(type=="string")) | .[0] // empty' 2>/dev/null)"
[[ -z "$FP" ]] && exit 0
# normalise to absolute
[[ "$FP" != /* ]] && FP="$CWD/$FP"

fleet_state_jq "$CHILD_ID" --arg p "$FP" --argjson now "$NOW" '
    .claims = ((.claims // []) + [$p] | unique)
  | (if (.claims | length) > 50 then .claims |= .[-50:] else . end)
  | .heartbeat = $now | .state = "running"' >/dev/null 2>&1 || true
exit 0
