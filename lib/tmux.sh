# shellcheck shell=bash
# tmux.sh — host worker sessions as windows in a single `fleet` tmux session.
# All functions degrade gracefully (return non-zero) when tmux is absent, so
# Tier-1 monitoring works without it.

FLEET_TMUX_SESSION="${FLEET_TMUX_SESSION:-}"
# The fleet runs on its OWN tmux socket (server), not the user's default one.
# This isolates it from any personal tmux the user runs, and — crucially — means
# the server is always spawned fresh by us, so it actually lands in the
# per-user systemd unit below instead of joining a pre-existing server that
# might sit in a login-session cgroup. Change in lockstep on all hosts.
FLEET_TMUX_SOCKET="${FLEET_TMUX_SOCKET:-}"
# Transient per-user systemd unit that owns the tmux server (see
# fleet_tmux_ensure_session). One per tmux session name so distinct fleets don't
# collide.
FLEET_TMUX_UNIT="${FLEET_TMUX_UNIT:-}"

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

# True when a tmux server is already answering on the fleet's socket — even if our
# named session isn't among its sessions. Distinct from session_exists: the durable
# systemd unit's server hosts the watchdog sessions (r2-apiwatch/idlewatch) and stays
# up after the 'fleet' session is torn down, so the server can be live while the
# session is gone. We must NOT re-run systemd-run in that case (the unit already
# exists → it errors → false "login session" warning); just create the session in the
# running server, which inherits its durability.
fleet_tmux_server_running() {
  fleet_has_tmux || return 1
  fleet_tmux list-sessions >/dev/null 2>&1
}

# Keep bootstrap lifetime independent of prompt-construction time. A real window
# removes it immediately after a successful spawn.
fleet_tmux_drop_placeholder() {
  fleet_tmux kill-window -t "$FLEET_TMUX_SESSION:__fleet_root" 2>/dev/null || true
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

# Install server-global tmux hooks (idempotent). pane-died → reap IMMEDIATELY, so a
# crashed worker is recovered the instant its pane dies instead of waiting for the
# watchdog's next poll (the mechanical-floor upgrade, ADR-002 §7c). Only meaningful
# under remain-on-exit (else the window vanishes and pane-died never fires). Reap is
# the existing, guarded mechanism (only restarts manifest children that are `running`
# per policy), so this only changes TIMING, not behaviour — and an intentional
# `fleet down` marks children stopped, which reap skips. Best-effort; never blocks.
# Gated (default off); enable with FLEET_TMUX_DEATH_HOOK=on. NB: assumes no spaces in
# WORKSPACE / the fleet bin path (nested tmux-hook quoting can't portably handle them).
fleet_tmux_install_server_hooks() {
  if [[ "${FLEET_TMUX_DEATH_HOOK:-off}" != "on" ]]; then
    # symmetric toggle: off actively removes any hook we set, so flipping it off takes
    # effect on the next fleet command without needing a server restart.
    fleet_tmux_session_exists && fleet_tmux set-hook -gu pane-died 2>/dev/null || true
    return 0
  fi
  [[ -n "${WORKSPACE:-}" ]] || return 0
  local fleetbin="${FLEET_BIN:-$TOOL_ROOT/bin/fleet}"
  fleet_tmux set-hook -g pane-died \
    "run-shell -b 'FLEET_WORKSPACE=$WORKSPACE $fleetbin reap >/dev/null 2>&1'" 2>/dev/null || true
}

fleet_tmux_ensure_session() {
  fleet_has_tmux || die "tmux is not installed (needed for 'up/down/restart'). Run: sudo apt install tmux"
  fleet_tmux_session_exists && { fleet_tmux_install_server_hooks; return 0; }
  # The timeout only cleans up an abandoned failed launch. A successful first
  # window explicitly removes the bootstrap.
  local -a srv=(tmux -L "$FLEET_TMUX_SOCKET" new-session -d -s "$FLEET_TMUX_SESSION" -n __fleet_root "sleep 300")
  # A server is already up on our socket (typically the durable systemd unit, kept
  # alive by the watchdog sessions) but lacks the 'fleet' session — just create the
  # session in it. Re-running systemd-run here would fail ("unit already exists") and
  # emit a misleading login-session warning, even though the outcome is durable.
  if fleet_tmux_server_running; then
    "${srv[@]}" 8>&- 2>/dev/null || true
    fleet_tmux_install_server_hooks; return 0
  fi
  # A tmux server spawned inside a login session lives in that session's cgroup
  # scope; on systemd hosts with KillUserProcesses=yes (common on xrdp/rdesktop
  # boxes) it is reaped the moment the session ends — even with lingering on.
  # Launch it as a transient unit of the per-user manager instead, so it lands
  # under user@.service and outlives the login that started it.
  if fleet_tmux_user_manager_ok; then
    systemctl --user reset-failed "$FLEET_TMUX_UNIT" 2>/dev/null || true
    if systemd-run --user --quiet --collect --unit="$FLEET_TMUX_UNIT" \
         --property=Type=forking "${srv[@]}" 8>&- 2>/dev/null; then
      fleet_tmux_install_server_hooks; return 0
    fi
    warn "systemd-run --user failed; starting tmux in the login session (may not survive logout)"
  fi
  "${srv[@]}" 8>&- 2>/dev/null || true
  fleet_tmux_install_server_hooks
}

# does a window named after <id> exist?
fleet_tmux_has_window() {
  fleet_tmux_session_exists || return 1
  fleet_tmux list-windows -t "$FLEET_TMUX_SESSION" -F '#W' 2>/dev/null | grep -qxF -- "$1"
}

# Does <id>'s window actually hold a LIVE agent? Distinct from has_window, which
# only proves a window object exists. Two ways a window outlives its agent:
# tmux marks the pane dead (remain-on-exit), or the runner wrapper is alive but
# the agent it spawned has exited. Both must read as NOT alive, or `fleet up`
# reports a dead lane as running (see the recycle path in fleet_tmux_start_child).
# Returns 0 only when a descendant process of the pane is a provider binary.
fleet_tmux_window_alive() {
  local id="$1" pane_pid dead
  fleet_tmux_has_window "$id" || return 1
  dead="$(fleet_tmux list-panes -t "$FLEET_TMUX_SESSION:$id" -F '#{pane_dead}' 2>/dev/null | head -1)"
  [[ "$dead" == "1" ]] && return 1
  pane_pid="$(fleet_tmux list-panes -t "$FLEET_TMUX_SESSION:$id" -F '#{pane_pid}' 2>/dev/null | head -1)"
  [[ -n "$pane_pid" ]] || return 1
  # walk the pane's process subtree for an actual provider process
  pgrep -P "$pane_pid" >/dev/null 2>&1 || return 1
  local p
  for p in $(pgrep -P "$pane_pid" 2>/dev/null); do
    case "$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)" in
      *claude*|*codex*) return 0 ;;
    esac
    # one level deeper: run-child.sh wraps the provider
    local q
    for q in $(pgrep -P "$p" 2>/dev/null); do
      case "$(tr '\0' ' ' < "/proc/$q/cmdline" 2>/dev/null)" in
        *claude*|*codex*) return 0 ;;
      esac
    done
  done
  return 1
}

# Is <id>'s pane DEAD — its command exited but the window lingers (only possible
# under remain-on-exit on)? Structured ground truth via #{pane_dead}, not text
# scraping. Returns non-zero (treated as "not dead") when tmux/window is absent or
# the query fails — so a failed query never flips a live worker to dead.
fleet_tmux_pane_dead() {
  fleet_tmux_session_exists || return 1
  local v
  v="$(fleet_tmux display-message -p -t "$FLEET_TMUX_SESSION:$1" '#{pane_dead}' 2>/dev/null)" || return 1
  [[ "$v" == "1" ]]
}

# Last-output epoch for <id>'s window (#{window_activity}) — a tmux-native activity
# signal. Prints the epoch, or 0 if unavailable. NOTE: this counts ANY pane output
# incl. TUI repaints, so it is a reliable ALIVE signal but NOT an idle-vs-busy
# discriminator; bench against a real idle Claude pane before wiring it into liveness.
fleet_tmux_window_activity() {
  fleet_tmux_session_exists || { echo 0; return; }
  local v
  v="$(fleet_tmux display-message -p -t "$FLEET_TMUX_SESSION:$1" '#{window_activity}' 2>/dev/null)"
  [[ "$v" =~ ^[0-9]+$ ]] && printf '%s\n' "$v" || echo 0
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
  # Validated run path: an unguarded '../../pwned' here wrote an argv file clean
  # outside RUN_DIR (verified against 0ab4a0e).
  f="$(fleet_run_path "$id" .argv)" || return 1
  mkdir -p "$RUN_DIR"
  # Atomic no-follow write: a symlink squatting the argv path would send an in-place
  # `:>"$f"` through to an out-of-tree target. Instead build the NUL-delimited argv in a
  # fresh temp and rename() it into place (fleet_atomic_write) — rename replaces a
  # squatted link (target untouched) with no TOCTOU window. Confirmed against 6d19957.
  local a
  { for a in "${argv[@]}"; do printf '%s\0' "$a"; done; } | fleet_atomic_write "$f" || return 1
  printf '%s\n' "$f"
}

fleet_tmux_new_agent_window() {
  local id="$1" cwd="$2" exitfile="$3" provider="$4" arr_name="$5"
  local -n argv="$arr_name"
  # The id becomes a tmux WINDOW NAME and an argv filename. Refuse a non-plain id
  # here, at the artifact boundary — creating the window first and validating later
  # (which is what the pre-0ab4a0e ordering did) leaves a phantom window behind.
  fleet_valid_member_id "$id" || { warn "refusing to spawn a window for invalid member id '$id'"; return 1; }
  # Over this argv size, spill to a NUL-delimited file (run-argv-file.sh) instead of
  # passing argv inline — tmux ferries a command to its server over imsg, whose
  # MAX_IMSGSIZE ceiling is 16384 bytes; an inline argv above that dies with tmux's
  # "command too long" (hit live 2026-07-01: a codex companion prompt at 17429 bytes
  # slipped the old 20000 gate — which sat ABOVE tmux's real ceiling — and failed to
  # launch). Keep the default comfortably under 16384 to leave room for the
  # new-window wrapper (run-child.sh path, -e env, --). The file path is proven and
  # cheap, so erring low only costs a small temp file.
  local max="${FLEET_TMUX_ARG_MAX:-12000}" size argvfile
  size="$(fleet_agent_argv_size "$arr_name")"
  # ALWAYS target "$FLEET_TMUX_SESSION:" — the trailing colon (an explicit EMPTY window
  # component) is load-bearing, not cosmetic. A bare "$FLEET_TMUX_SESSION" is parsed by
  # tmux as a target-WINDOW and resolved by window-NAME match, which PREFIX-matches any
  # window named like the session — e.g. session `fleet` matches the window `fleet-fix`.
  # new-window then tries to create AT that window's index and dies with
  # "create window failed: index N in use", deterministically, for every spawn
  # (up/dispatch/pair/refute). Live 2026-07-15: `fleet refute` failed with "index 11 in
  # use" = the fleet-fix window's index; it tracked that window as it moved (12 → 11).
  # With the empty component tmux resolves session-only and allocates the next unused
  # index. Same fix as cmd_ask (8ac37cc). See tests/window-alloc.sh.
  local spawn_rc=0
  if [[ "$size" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ && "$size" -gt "$max" ]]; then
    argvfile="$(fleet_write_agent_argv_file "$id" "$arr_name")"
    fleet_tmux new-window -t "$FLEET_TMUX_SESSION:" -n "$id" -c "$cwd" \
      -e "FLEET_CHILD_ID=$id" -e "FLEET_AGENT_PROVIDER=$provider" \
      "$TOOL_ROOT/lib/run-child.sh" "$exitfile" -- "$TOOL_ROOT/lib/run-argv-file.sh" "$argvfile" || spawn_rc=$?
  else
    fleet_tmux new-window -t "$FLEET_TMUX_SESSION:" -n "$id" -c "$cwd" \
      -e "FLEET_CHILD_ID=$id" -e "FLEET_AGENT_PROVIDER=$provider" \
      "$TOOL_ROOT/lib/run-child.sh" "$exitfile" -- "${argv[@]}" || spawn_rc=$?
  fi
  (( spawn_rc == 0 )) || return "$spawn_rc"
  fleet_tmux_drop_placeholder
  # opt-in hardening: keep a crashed worker's window as a DEAD pane (a visible
  # corpse + its exit code) instead of letting it vanish — so #{pane_dead} liveness
  # and reap can SEE the crash rather than the window silently disappearing. Default
  # off → live-fleet behaviour unchanged. Enable with FLEET_TMUX_REMAIN_ON_EXIT=on.
  if [[ "${FLEET_TMUX_REMAIN_ON_EXIT:-off}" == "on" ]]; then
    fleet_tmux set-option -w -t "$FLEET_TMUX_SESSION:$id" remain-on-exit on 2>/dev/null || true
  fi
}

# Start one child in its own window. fleet_tmux_start_child <id>
# Resumes from run/<id>.session when present, else seeds a fresh session.
fleet_tmux_start_child() {
  local id="$1"
  # FIRST, before any run-file path is derived and before the window exists: the old
  # order reached fleet_state_ensure (the only validator) only AFTER `rm -f
  # "$RUN_DIR/$id.exit"`, so an id of '../keepme' deleted an out-of-tree file and a
  # window was already spawned by the time registration refused the id.
  fleet_require_member_id "$id"
  fleet_tmux_ensure_session
  # A WINDOW IS NOT A RUNNING AGENT. This used to `return 0` on window-exists
  # alone, so a window whose agent had died still counted as up: `fleet up`
  # printed "started" for every lane while doing nothing, and `fleet restart` of
  # a pair lane left a dead window that `fleet up` then refused to replace.
  # Measured 2026-07-19: six codex refuters sat dead for ~an hour reporting
  # "already running"; the claude lanes' processes were 190915s old after an
  # `up` that claimed to start them. Presence of a window is not reachability of
  # an agent — so probe the pane and RECYCLE a dead one instead of reporting it up.
  if fleet_tmux_has_window "$id"; then
    if fleet_tmux_window_alive "$id"; then
      warn "child '$id' already running"; return 0
    fi
    warn "child '$id': stale window (agent dead) — recycling"
    fleet_tmux kill-window -t "$FLEET_TMUX_SESSION:$id" 2>/dev/null || true
  fi

  local rel cwd name pm seed sid provider primer
  rel="$(fleet_child_get "$id" cwd ".")"
  cwd="$WORKSPACE/$rel"; [[ "$rel" == /* ]] && cwd="$rel"
  [[ -d "$cwd" ]] || die "child '$id': cwd does not exist: $cwd"
  name="$(fleet_child_get "$id" name "$id")"
  pm="$(fleet_child_get "$id" permission_mode "")"
  seed="$(fleet_child_get "$id" seed "")"
  provider="$(fleet_provider_for_child "$id")"
  local sf; sf="$(fleet_run_path "$id" .session)" || return 1
  sid=""; [[ -f "$sf" ]] && sid="$(<"$sf")"

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
  local exitfile; exitfile="$(fleet_run_path "$id" .exit)" || return 1
  rm -f "$exitfile"
  # -e sets env in the new window (tmux ≥3.0); command + args passed as argv so
  # no shell-quoting of the seed prompt is needed.
  fleet_tmux_new_agent_window "$id" "$cwd" "$exitfile" "$provider" agent_args

  fleet_state_ensure "$id" "$cwd" true
  fleet_state_jq "$id" --arg p "$provider" '.state="running" | .reason=null | .provider=$p | .faculty="cli-tmux"' >/dev/null
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
  local id="$1" f
  f="$(fleet_run_path "$id" .exit)" || { printf ''; return; }
  [[ -f "$f" ]] && cat "$f" || printf ''
}
