# shellcheck shell=bash
# restart.sh — OTP-style restart policy + restart-intensity circuit breaker.
#
#   permanent  → always restart
#   transient  → restart only on abnormal exit (non-zero / crash)
#   temporary  → never restart
#
# Intensity: if a child is restarted more than SUP_MAX_RESTARTS times within
# SUP_MAX_SECONDS, the breaker trips: the child is marked `failed` and left down
# (mirrors a supervisor reaching max restart intensity and giving up on it).

# Decide whether a child should be restarted given its last exit code.
# fleet_restart_policy_allows <id> <exit_code>
fleet_restart_policy_allows() {
  local id="$1" rc="${2:-}"
  local policy; policy="$(fleet_child_get "$id" restart permanent)"
  case "$policy" in
    permanent) return 0 ;;
    temporary) return 1 ;;
    transient) [[ -n "$rc" && "$rc" != "0" ]] && return 0 || return 1 ;;
    *)         return 0 ;;
  esac
}

# Record a restart timestamp and report whether the breaker has tripped.
# Returns 0 if a restart is still within budget, 1 if intensity exceeded.
fleet_intensity_ok() {
  local id="$1" now; now="$(date +%s)"
  local window=$(( now - SUP_MAX_SECONDS ))
  fleet_state_jq "$id" --argjson now "$now" --argjson win "$window" \
    '.restarts = ((.restarts // []) + [$now] | map(select(. >= $win)))' >/dev/null
  local count; count="$(fleet_state_get "$id" '.restarts | length' 0)"
  (( count > SUP_MAX_RESTARTS ))  && return 1 || return 0
}

# Restart one child, honouring policy + intensity. fleet_restart_child <id> [force]
fleet_restart_child() {
  local id="$1" force="${2:-}"
  local rc; rc="$(fleet_child_exit_code "$id")"

  if [[ "$force" != "force" ]] && ! fleet_restart_policy_allows "$id" "$rc"; then
    fleet_log skip-restart "$id" "policy=$(fleet_child_get "$id" restart permanent) rc=${rc:-?}"
    return 0
  fi
  if ! fleet_intensity_ok "$id"; then
    fleet_state_jq "$id" '.state="failed" | .reason="restart intensity exceeded"' >/dev/null
    fleet_log breaker-trip "$id" "> $SUP_MAX_RESTARTS restarts / ${SUP_MAX_SECONDS}s — left down"
    warn "child '$id': restart intensity exceeded — marked failed, not restarting"
    return 1
  fi
  fleet_tmux_stop_child "$id"
  fleet_tmux_start_child "$id"
  fleet_log restart "$id" "rc=${rc:-?}"
}
