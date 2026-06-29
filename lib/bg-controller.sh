#!/usr/bin/env bash
# bg-controller.sh <id> — the Model-B controller for one claude-bg worker (ADR-003).
#
# Runs INSIDE a tmux window named <id> (so the worker still appears in the unified
# fleet view + reuses window-based liveness/attach). It is the SOLE driver of the
# worker's durable session: it establishes the session on first run, then loops
# delivering queued mailbox messages as programmatic `claude -p --resume` turns —
# keystroke-free, so the stuck-message bug cannot occur. Output renders here, so
# attaching to this window shows the worker's activity.
# shellcheck source-path=SCRIPTDIR
set -uo pipefail

id="${1:?usage: bg-controller.sh <id>}"
: "${TOOL_ROOT:?bg-controller: TOOL_ROOT must be set}"
for lib in common manifest registry provider tmux comms transport faculty faculty-bg; do
  # shellcheck disable=SC1090
  source "$TOOL_ROOT/lib/$lib.sh"
done
fleet_load_paths
[[ -f "$MANIFEST" ]] && fleet_manifest_load "$MANIFEST"

rel="$(fleet_child_get "$id" cwd ".")"; cwd="$WORKSPACE/$rel"; [[ "$rel" == /* ]] && cwd="$rel"
primer=""; declare -F fleet_peer_primer >/dev/null 2>&1 && primer="$(fleet_peer_primer "$id" 2>/dev/null || true)"
poll="${FLEET_BG_POLL:-15}"

printf '[bg-controller %s] start · cwd=%s · adapter=claude-bg (keystroke-free delivery)\n' "$id" "$cwd"

sid="$(fleet_state_get "$id" '.session_id' "")"
if [[ -z "$sid" || "$sid" == "null" ]]; then
  seed="$(fleet_child_get "$id" seed "Resume work in this repo. Run 'git status' first and summarise where things stand.")"
  printf '[bg-controller %s] establishing durable session…\n' "$id"
  sid="$(fleet_bg_start_session "$cwd" "$(fleet_prompt_join "$primer" "$seed")")"
  if [[ -n "$sid" ]]; then
    fleet_state_jq "$id" --arg s "$sid" '.session_id=$s | .state="running" | .reason=null' >/dev/null 2>&1 || true
    fleet_log bg-start "$id" "session=$sid"
    printf '[bg-controller %s] session=%s established\n' "$id" "$sid"
  else
    printf '[bg-controller %s] FAILED to establish session — retrying next loop\n' "$id"
  fi
fi

printf '[bg-controller %s] entering deliver loop (poll=%ss). Send it work: fleet send %s "…"\n' "$id" "$poll" "$id"
while true; do
  fleet_state_jq "$id" --argjson t "$(date +%s)" '.heartbeat=$t | .ready=true' >/dev/null 2>&1 || true
  # establish the session if the first attempt failed
  sid="$(fleet_state_get "$id" '.session_id' "")"
  if [[ -z "$sid" || "$sid" == "null" ]]; then
    sid="$(fleet_bg_start_session "$cwd" "$(fleet_prompt_join "$primer" "carry on")")"
    [[ -n "$sid" ]] && fleet_state_jq "$id" --arg s "$sid" '.session_id=$s' >/dev/null 2>&1 || true
  fi
  fleet_bg_drain "$id" || true     # deliver any queued mail as turns (renders above)
  sleep "$poll"
done
