# shellcheck shell=bash
# tmux.sh — host worker sessions as windows in a single `fleet` tmux session.
# All functions degrade gracefully (return non-zero) when tmux is absent, so
# Tier-1 monitoring works without it.

FLEET_TMUX_SESSION="${FLEET_TMUX_SESSION:-fleet}"
# The fleet runs on its OWN tmux socket (server), not the user's default one.
# This isolates it from any personal tmux the user runs, and — crucially — means
# the server is always spawned fresh by us, so it actually lands in the
# per-user systemd unit below instead of joining a pre-existing server that
# might sit in a login-session cgroup. Change in lockstep on all hosts.
FLEET_TMUX_SOCKET="${FLEET_TMUX_SOCKET:-fleet}"
# Transient per-user systemd unit that owns the tmux server (see
# fleet_tmux_ensure_session). One per tmux session name so distinct fleets don't
# collide.
FLEET_TMUX_UNIT="${FLEET_TMUX_UNIT:-fleet-tmux-$FLEET_TMUX_SESSION}"

fleet_has_tmux() { command -v tmux >/dev/null 2>&1; }

# Every fleet tmux call goes through this so they all hit the fleet's own
# socket/server. (The server-spawning command in fleet_tmux_ensure_session is
# the one exception — it must invoke the real binary so systemd-run can exec it.)
# Close fd 8 in tmux children: cmd_up holds its workspace lock there, and panes
# must not inherit it or a later `fleet up <id>` will think the first launch is
# still in progress.
fleet_tmux() { command tmux -L "$FLEET_TMUX_SOCKET" "$@" 8>&-; }

fleet_tmux_session_exists() {
  fleet_has_tmux || return 1
  fleet_tmux has-session -t "$FLEET_TMUX_SESSION" 2>/dev/null
}

# True when the tmux server can be parked in the per-user systemd manager
# (user@.service). That manager outlives any individual login, so with
# lingering enabled the fleet survives SSH/rdesktop logout even on hosts that
# set KillUserProcesses=yes. Opt out with FLEET_TMUX_USER_SCOPE=off.
fleet_tmux_user_manager_ok() {
  [[ "${FLEET_TMUX_USER_SCOPE:-auto}" != "off" ]] || return 1
  command -v systemd-run >/dev/null 2>&1 || return 1
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] || return 1
  systemctl --user show-environment >/dev/null 2>&1
}

fleet_tmux_ensure_session() {
  fleet_has_tmux || die "tmux is not installed (needed for 'up/down/restart'). Run: sudo apt install tmux"
  fleet_tmux_session_exists && return 0
  # A detached, placeholder-free session; the first child replaces window 0 once
  # __fleet_root's keepalive command exits.
  local -a srv=(tmux -L "$FLEET_TMUX_SOCKET" new-session -d -s "$FLEET_TMUX_SESSION" -n __fleet_root "true; sleep 1")
  # A tmux server spawned inside a login session lives in that session's cgroup
  # scope; on systemd hosts with KillUserProcesses=yes (common on xrdp/rdesktop
  # boxes) it is reaped the moment the session ends — even with lingering on.
  # Launch it as a transient unit of the per-user manager instead, so it lands
  # under user@.service and outlives the login that started it.
  if fleet_tmux_user_manager_ok; then
    systemctl --user reset-failed "$FLEET_TMUX_UNIT" 2>/dev/null || true
    if systemd-run --user --quiet --collect --unit="$FLEET_TMUX_UNIT" \
         --property=Type=forking "${srv[@]}" 8>&- 2>/dev/null; then
      return 0
    fi
    warn "systemd-run --user failed; starting tmux in the login session (may not survive logout)"
  fi
  "${srv[@]}" 8>&- 2>/dev/null || true
}

# does a window named after <id> exist?
fleet_tmux_has_window() {
  fleet_tmux_session_exists || return 1
  fleet_tmux list-windows -t "$FLEET_TMUX_SESSION" -F '#W' 2>/dev/null | grep -qxF -- "$1"
}

# List the ids of live CHILD windows (one per line). This is ground truth: a
# child shows here from its tmux window alone, independent of any state doc.
# Filters out the placeholder root window and the transient `ask:<id>` responder
# windows, which are not children.
fleet_tmux_window_ids() {
  fleet_tmux_session_exists || return 0
  local w
  while IFS= read -r w; do
    [[ -z "$w" ]] && continue
    [[ "$w" == "__fleet_root" ]] && continue
    [[ "$w" == ask:* ]] && continue
    printf '%s\n' "$w"
  done < <(fleet_tmux list-windows -t "$FLEET_TMUX_SESSION" -F '#W' 2>/dev/null)
}

fleet_agent_argv_size() {
  local arr_name="$1" a total=0
  local -n argv="$arr_name"
  for a in "${argv[@]}"; do
    total=$(( total + ${#a} + 1 ))
  done
  printf '%s\n' "$total"
}

fleet_write_agent_argv_file() {
  local id="$1" arr_name="$2" f
  local -n argv="$arr_name"
  mkdir -p "$RUN_DIR"
  f="$RUN_DIR/$id.argv"
  : >"$f"
  local a
  for a in "${argv[@]}"; do
    printf '%s\0' "$a"
  done >"$f"
  printf '%s\n' "$f"
}

fleet_tmux_new_agent_window() {
  local id="$1" cwd="$2" exitfile="$3" provider="$4" arr_name="$5"
  local -n argv="$arr_name"
  local max="${FLEET_TMUX_ARG_MAX:-20000}" size argvfile
  size="$(fleet_agent_argv_size "$arr_name")"
  if [[ "$size" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ && "$size" -gt "$max" ]]; then
    argvfile="$(fleet_write_agent_argv_file "$id" "$arr_name")"
    fleet_tmux new-window -t "$FLEET_TMUX_SESSION" -n "$id" -c "$cwd" \
      -e "FLEET_CHILD_ID=$id" -e "FLEET_AGENT_PROVIDER=$provider" \
      "$TOOL_ROOT/lib/run-child.sh" "$exitfile" -- "$TOOL_ROOT/lib/run-argv-file.sh" "$argvfile"
  else
    fleet_tmux new-window -t "$FLEET_TMUX_SESSION" -n "$id" -c "$cwd" \
      -e "FLEET_CHILD_ID=$id" -e "FLEET_AGENT_PROVIDER=$provider" \
      "$TOOL_ROOT/lib/run-child.sh" "$exitfile" -- "${argv[@]}"
  fi
}

# Start one child in its own window. fleet_tmux_start_child <id>
# Resumes from run/<id>.session when present, else seeds a fresh session.
fleet_tmux_start_child() {
  local id="$1"
  fleet_tmux_ensure_session
  fleet_tmux_has_window "$id" && { warn "child '$id' already has a window"; return 0; }

  local rel cwd name pm seed sid provider primer
  rel="$(fleet_child_get "$id" cwd ".")"
  cwd="$WORKSPACE/$rel"; [[ "$rel" == /* ]] && cwd="$rel"
  [[ -d "$cwd" ]] || die "child '$id': cwd does not exist: $cwd"
  name="$(fleet_child_get "$id" name "$id")"
  pm="$(fleet_child_get "$id" permission_mode "")"
  seed="$(fleet_child_get "$id" seed "")"
  provider="$(fleet_provider_for_child "$id")"
  sid=""; [[ -f "$RUN_DIR/$id.session" ]] && sid="$(<"$RUN_DIR/$id.session")"

  # prime the worker with its identity, peers, and the mailbox protocol
  if declare -F fleet_peer_primer >/dev/null 2>&1; then
    primer="$(fleet_peer_primer "$id")"
  fi
  local prompt=""
  if [[ -n "$sid" ]]; then
    # A resumed session reopens idle at its prompt — nudge it to pick its work
    # back up. Per-child 'resume_nudge', else $FLEET_RESUME_NUDGE, else "carry
    # on"; set any of them empty to leave it idle.
    local nudge; nudge="$(fleet_child_get "$id" resume_nudge "${FLEET_RESUME_NUDGE-carry on}")"
    [[ -n "$nudge" ]] && prompt="$nudge"
    fleet_log resume "$id" "session=$sid${nudge:+ nudge=$nudge}"
  elif [[ -n "$seed" ]]; then
    prompt="$seed"
    fleet_log start "$id" "fresh seed"
  fi

  local -a agent_args=()
  fleet_agent_build_args agent_args "$provider" "$id" "$name" "$cwd" "$primer" "$prompt" "$sid" "$pm"

  mkdir -p "$RUN_DIR"
  local exitfile="$RUN_DIR/$id.exit"; rm -f "$exitfile"
  # -e sets env in the new window (tmux ≥3.0); command + args passed as argv so
  # no shell-quoting of the seed prompt is needed.
  fleet_tmux_new_agent_window "$id" "$cwd" "$exitfile" "$provider" agent_args

  fleet_state_ensure "$id" "$cwd" true
  fleet_state_jq "$id" --arg p "$provider" '.state="running" | .reason=null | .provider=$p' >/dev/null
  # record the transport that hosts this child (down-payment on a future
  # native-primitives migration). No-op if the seam isn't sourced.
  declare -F transport_register >/dev/null 2>&1 && transport_register "$id"
}

# Stop a child's window. fleet_tmux_stop_child <id>
fleet_tmux_stop_child() {
  local id="$1"
  fleet_tmux_has_window "$id" || return 0
  fleet_tmux kill-window -t "$FLEET_TMUX_SESSION:$id" 2>/dev/null || true
}

# Read the recorded exit code of a child's last run (empty if none).
fleet_child_exit_code() {
  local id="$1" f="$RUN_DIR/$1.exit"
  [[ -f "$f" ]] && cat "$f" || printf ''
}
