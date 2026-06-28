# shellcheck shell=bash
# faculty-bg.sh — the `claude-bg` faculty adapter (Model B, ADR-003): drive a worker's
# DURABLE session turn-by-turn with programmatic `claude -p --resume … stream-json`,
# instead of typing into a tmux TUI. This is the delivery fix — no keystrokes, so the
# unsubmitted-Enter / stuck-message bug class cannot occur.
#
# PROVEN (bench 2026-06-29): `claude -p --resume <sid>` delivers a turn programmatically
# and the session persists context across turns (asked it to remember 42, resumed,
# it answered 42); `claude attach <id>` renders the session in a tmux window (unified
# view). See docs/ADR-003-claude-bg-adapter.md.
#
# Selected by FLEET_FACULTY_ADAPTER=claude-bg. cli-tmux remains the default + fallback,
# so sourcing this file is INERT unless that adapter is chosen. This slice ships the
# proven DELIVERY primitive; the worker-lifecycle controller loop (start workers as
# durable sessions + attach-in-tmux view) is the next step (ADR-003 rollout).
#
# Requires: registry.sh + provider.sh + comms.sh sourced.

# Deliver one message to a worker's durable session as a programmatic turn. Prints the
# agent's reply (json .result) on stdout; non-zero on failure. NO tmux keystrokes.
#   fleet_bg_deliver_turn <session_id> <cwd> <text>
fleet_bg_deliver_turn() {
  local sid="$1" cwd="$2" text="$3" bin out
  [[ -n "$sid" && "$sid" != "null" ]] || return 1
  bin="$(fleet_provider_bin claude)"
  local -a perm=()
  [[ "${FLEET_SKIP_PERMISSIONS:-on}" != "off" ]] && perm=(--dangerously-skip-permissions)
  out="$( cd "$cwd" 2>/dev/null && timeout "${FLEET_BG_TURN_TIMEOUT:-300}" \
    "$bin" -p --resume "$sid" --output-format json "${perm[@]}" "$text" 2>/dev/null )" || return 1
  jq -r '.result // .text // empty' <<<"$out" 2>/dev/null
}

# claude-bg drain: deliver each currently-undelivered inbox line to <to> as a
# programmatic turn, marking delivered ONLY on success (at-least-once, like the
# tmux drain but keystroke-free). Returns 0 if nothing left queued, 1 if it had to
# leave mail queued (no session id, or a turn failed).
#   fleet_bg_drain <to>
fleet_bg_drain() {
  local to="$1" f sid cwd
  f="$(fleet_inbox_file "$to")"; [[ -f "$f" ]] || return 0
  sid="$(fleet_state_get "$to" '.session_id' "")"
  [[ -n "$sid" && "$sid" != "null" ]] || return 1            # no durable session yet → keep queued
  cwd="$(fleet_state_get "$to" '.cwd' "$PWD")"
  exec 9>"$f.lock"; flock 9 2>/dev/null || true
  local -a lines=(); local line; while IFS= read -r line; do lines+=("$line"); done <"$f"
  : >"$f.tmp"; local idx delivered from text rc=0
  for idx in "${!lines[@]}"; do
    line="${lines[$idx]}"; [[ -z "$line" ]] && continue
    delivered="$(jq -r '.delivered // false' <<<"$line" 2>/dev/null)"
    if [[ "$delivered" == "true" ]]; then printf '%s\n' "$line" >>"$f.tmp"; continue; fi
    from="$(jq -r '.from' <<<"$line")"; text="$(jq -r '.text' <<<"$line")"
    if fleet_bg_deliver_turn "$sid" "$cwd" "[fleet msg from $from] $text" >/dev/null; then
      printf '%s\n' "$(jq -c '.delivered=true' <<<"$line")" >>"$f.tmp"
    else
      rc=1; printf '%s\n' "$line" >>"$f.tmp"   # leave queued; retry next drain
    fi
  done
  mv "$f.tmp" "$f" 2>/dev/null || rm -f "$f.tmp"
  flock -u 9 2>/dev/null || true; exec 9>&-
  return "$rc"
}
