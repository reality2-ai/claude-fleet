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
# claude-bg is CLAUDE-ONLY: the controller drives the worker's durable session with
# `claude -p --resume`. Codex is NOT a per-worker brain — it runs as a single read-only
# refuter window via `fleet refute` / bin/codex-review (the canonical adversarial role).
# Refuse to drive a codex worker here (belt-and-braces; fleet_bg_mount already diverts
# codex to cli-tmux). See docs/ADR-002 + ADR-003.
provider="$(fleet_state_get "$id" '.provider' "")"
[[ -z "$provider" || "$provider" == "null" ]] && provider="$(fleet_provider_for_child "$id" 2>/dev/null || echo claude)"
if [[ "$provider" == "codex" ]]; then
  printf '[bg-controller %s] codex is not supported on claude-bg (codex = refuter only); use cli-tmux for codex workers.\n' "$id"
  fleet_state_jq "$id" '.state="failed" | .reason="codex unsupported on claude-bg (refuter-only)"' >/dev/null 2>&1 || true
  exit 0
fi
_ctl_start_session() { fleet_bg_start_session "$cwd" "$1"; }      # <prompt> → prints session id
_ctl_deliver_turn()  { fleet_bg_deliver_turn "$1" "$cwd" "$2"; }  # <sid> <text> → prints reply tail

printf '[bg-controller %s] start · cwd=%s · provider=claude · adapter=claude-bg (keystroke-free delivery)\n' "$id" "$cwd"

sid="$(fleet_state_get "$id" '.session_id' "")"
if [[ -z "$sid" || "$sid" == "null" ]]; then
  seed="$(fleet_child_get "$id" seed "Resume work in this repo. Run 'git status' first and summarise where things stand.")"
  printf '[bg-controller %s] establishing durable session…\n' "$id"
  sid="$(_ctl_start_session "$(fleet_prompt_join "$primer" "$seed")")"
  if [[ -n "$sid" ]]; then
    fleet_state_jq "$id" --arg s "$sid" '.session_id=$s | .state="running" | .reason=null' >/dev/null 2>&1 || true
    fleet_log bg-start "$id" "session=$sid"
    printf '[bg-controller %s] session=%s established\n' "$id" "$sid"
  else
    printf '[bg-controller %s] FAILED to establish session — retrying next loop\n' "$id"
  fi
fi

# --- autonomy policy --------------------------------------------------------
# Mail is always priority. Between messages, drive autonomous "continue" turns ONLY
# while the worker keeps making progress (a changed git HEAD or dirty-count); after
# FLEET_BG_MAX_IDLE_TURNS no-progress turns, back off to await-mail (cost-bounded —
# it can't spin forever). Incoming mail re-engages autonomy. Disable autonomous
# turns entirely with FLEET_BG_AUTONOMY=off (pure await-mail worker).
autonomy="${FLEET_BG_AUTONOMY:-on}"; max_idle="${FLEET_BG_MAX_IDLE_TURNS:-2}"; idle_turns=0
_git_fp() { printf '%s:%s' \
  "$(git -C "$cwd" rev-parse HEAD 2>/dev/null || echo none)" \
  "$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"; }

printf '[bg-controller %s] deliver loop (poll=%ss, autonomy=%s/max-idle=%s). Send work: fleet send %s "…"\n' \
  "$id" "$poll" "$autonomy" "$max_idle" "$id"
while true; do
  fleet_state_jq "$id" --argjson t "$(date +%s)" '.heartbeat=$t | .ready=true' >/dev/null 2>&1 || true
  sid="$(fleet_state_get "$id" '.session_id' "")"
  if [[ -z "$sid" || "$sid" == "null" ]]; then
    sid="$(_ctl_start_session "$(fleet_prompt_join "$primer" "carry on")")"
    [[ -n "$sid" ]] && fleet_state_jq "$id" --arg s "$sid" '.session_id=$s' >/dev/null 2>&1 || true
  fi
  if fleet_bg_has_mail "$id"; then
    fleet_bg_drain "$id" && idle_turns=0 || true        # mail priority; re-engages autonomy
  elif [[ "$autonomy" == "on" && "$idle_turns" -lt "$max_idle" && -n "$sid" && "$sid" != "null" ]]; then
    before="$(_git_fp)"
    printf '── autonomous continue turn ──\n'
    reply="$(_ctl_deliver_turn "$sid" "Continue your current task. If you are blocked or have nothing left to do, say so in one line.")" || reply=""
    printf '  ← %s\n' "${reply:0:400}"
    if [[ "$(_git_fp)" != "$before" ]]; then
      idle_turns=0; printf '  (progress)\n'
    else
      idle_turns=$(( idle_turns + 1 )); printf '  (no progress; idle %s/%s)\n' "$idle_turns" "$max_idle"
      (( idle_turns >= max_idle )) && fleet_state_jq "$id" '.reason="idle: no progress, awaiting input"' >/dev/null 2>&1 || true
    fi
  fi
  sleep "$poll"
done
