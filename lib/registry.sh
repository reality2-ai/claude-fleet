# shellcheck shell=bash
# registry.sh — per-child runtime state (state/<id>.json) and liveness.
#
# A child state document:
#   { id, managed, provider, session_id, cwd, pid, state, current_task, claims[],
#     started_at, heartbeat, reason, restarts[] }
# `state` here is the *declared* lifecycle (running/idle/stopped/failed); the
# *derived* liveness (live/idle/dead) is computed by fleet_liveness from the
# transcript mtime and tmux, so it stays honest even if a worker dies uncleanly.

FLEET_IDLE_SECS="${FLEET_IDLE_SECS:-300}"    # no transcript write in 5m → idle
FLEET_DEAD_SECS="${FLEET_DEAD_SECS:-1800}"   # 30m → presumed dead

fleet_state_path() { printf '%s/%s.json\n' "$CHILDSTATE_DIR" "$1"; }

fleet_state_ids() {
  [[ -d "$CHILDSTATE_DIR" ]] || return 0
  local f
  for f in "$CHILDSTATE_DIR"/*.json; do
    [[ -e "$f" ]] || continue
    basename "$f" .json
  done
}

# Create the doc if absent. fleet_state_ensure <id> <cwd> <managed:true|false>
fleet_state_ensure() {
  local id="$1" cwd="$2" managed="${3:-false}"
  local f; f="$(fleet_state_path "$id")"
  mkdir -p "$CHILDSTATE_DIR"
  [[ -f "$f" ]] && return 0
  jq -n --arg id "$id" --arg cwd "$cwd" --argjson managed "$managed" '
    { id: $id, managed: $managed, provider: "claude", session_id: null, cwd: $cwd, pid: null,
      state: "unknown", current_task: null, claims: [],
      started_at: null, heartbeat: null, reason: null, restarts: [] }' >"$f"
}

# Apply a jq program to the doc in place. The LAST argument is the jq program;
# any args before it are forwarded to jq (e.g. --arg k v).
#   fleet_state_jq <id> [jq-args...] <program>
fleet_state_jq() {
  local id="$1"; shift
  local f tmp; f="$(fleet_state_path "$id")"
  [[ -f "$f" ]] || fleet_state_ensure "$id" "$PWD" false
  local -a a=( "$@" ); local n=${#a[@]}
  (( n >= 1 )) || return 1
  local prog="${a[n-1]}"; unset 'a[n-1]'
  tmp="$f.tmp.$$"
  if jq "${a[@]}" "$prog" "$f" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"; return 1
  fi
}

# Read a single field. fleet_state_get <id> <jq-path> [default]
fleet_state_get() {
  local id="$1" path="$2" def="${3:-}"
  local f; f="$(fleet_state_path "$id")"
  [[ -f "$f" ]] || { printf '%s\n' "$def"; return; }
  local v; v="$(jq -r "$path // empty" "$f" 2>/dev/null)"
  printf '%s\n' "${v:-$def}"
}

# Derive liveness for a child: prints one of live|idle|dead|stopped|failed.
# Declared terminal states win; otherwise threshold on last activity (the max of
# the self-reported heartbeat and the transcript mtime), with a tmux window as a
# strong "still here" signal.
fleet_liveness() {
  local id="$1"
  local declared; declared="$(fleet_state_get "$id" '.state' unknown)"
  case "$declared" in
    stopped|failed) printf '%s\n' "$declared"; return ;;
  esac

  local now act age; now="$(date +%s)"; act="$(fleet_last_activity "$id")"
  if fleet_tmux_has_window "$id" 2>/dev/null; then
    if (( act > 0 && now - act > FLEET_IDLE_SECS )); then printf 'idle\n'; else printf 'live\n'; fi
    return
  fi
  if (( act <= 0 )); then printf 'dead\n'; return; fi
  age=$(( now - act ))
  if   (( age > FLEET_DEAD_SECS )); then printf 'dead\n'
  elif (( age > FLEET_IDLE_SECS )); then printf 'idle\n'
  else                                   printf 'live\n'
  fi
}

# Last-activity epoch for a child (max of heartbeat and transcript mtime).
fleet_last_activity() {
  local id="$1" hb mt cwd sid provider
  hb="$(fleet_state_get "$id" '.heartbeat' 0)"; [[ "$hb" == "null" ]] && hb=0
  cwd="$(fleet_state_get "$id" '.cwd' "")"; sid="$(fleet_state_get "$id" '.session_id' "")"
  provider="$(fleet_state_get "$id" '.provider' claude)"
  mt=0; [[ -n "$cwd" && -n "$sid" ]] && mt="$(fleet_mtime "$(fleet_transcript_path "$cwd" "$sid" "$provider")")"
  (( hb > mt )) && printf '%s\n' "$hb" || printf '%s\n' "$mt"
}
