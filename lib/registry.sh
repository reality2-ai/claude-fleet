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
  # Ground-truth union: every id with a state doc on disk, UNIONED with every id
  # that has a live tmux window. The window union is the structural cure for the
  # "supervisor goes blind" failure — a child shows in `fleet status` from its
  # live window ALONE even with zero state doc. Gate the window half off with
  # FLEET_STATE_IDS_UNION=off (then only on-disk docs, old behaviour).
  local -A seen=()
  local id f
  if [[ -d "$CHILDSTATE_DIR" ]]; then
    for f in "$CHILDSTATE_DIR"/*.json; do
      [[ -e "$f" ]] || continue
      id="$(basename "$f" .json)"
      [[ -n "${seen[$id]:-}" ]] && continue
      seen["$id"]=1; printf '%s\n' "$id"
    done
  fi
  [[ "${FLEET_STATE_IDS_UNION:-on}" == "off" ]] && return 0
  # enumeration call site — routed through the transport seam when present, else
  # straight to the tmux helper (hooks don't source transport.sh; behaviour is
  # identical either way since transport_ids' only branch IS fleet_tmux_window_ids).
  if declare -F transport_ids >/dev/null 2>&1; then
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      [[ -n "${seen[$id]:-}" ]] && continue
      seen["$id"]=1; printf '%s\n' "$id"
    done < <(transport_ids 2>/dev/null)
  elif declare -F fleet_tmux_window_ids >/dev/null 2>&1; then
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      [[ -n "${seen[$id]:-}" ]] && continue
      seen["$id"]=1; printf '%s\n' "$id"
    done < <(fleet_tmux_window_ids 2>/dev/null)
  fi
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
  # liveness call site — routed through the transport seam when present (the tmux
  # branch IS fleet_tmux_has_window, so behaviour is byte-for-byte identical).
  local _present=1
  if declare -F transport_liveness >/dev/null 2>&1; then
    transport_liveness "$id" 2>/dev/null || _present=0
  else
    fleet_tmux_has_window "$id" 2>/dev/null || _present=0
  fi
  if (( _present == 1 )); then
    # Native dead-detection: a lingering window whose pane has EXITED is dead, not
    # live/idle. Structured (#{pane_dead}), not text-scraped. Graceful: acts only on
    # a positive dead signal, so a failed/absent query never changes the old answer;
    # and a no-op under the default config (windows close on exit → no dead pane).
    if [[ "${FLEET_TMUX_NATIVE_LIVENESS:-on}" != "off" ]] && declare -F fleet_tmux_pane_dead >/dev/null 2>&1 && fleet_tmux_pane_dead "$id"; then
      printf 'dead\n'; return
    fi
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

# Last-activity epoch for a child (max of heartbeat, transcript mtime, and — when
# FLEET_JOURNAL is on — the per-child journal mtime). Ground truth: a child that
# is writing its transcript is alive even if its self-reported heartbeat was lost
# with a deleted/stale state doc.
fleet_last_activity() {
  local id="$1" hb mt jt cwd sid provider
  hb="$(fleet_state_get "$id" '.heartbeat' 0)"; [[ "$hb" == "null" ]] && hb=0
  cwd="$(fleet_state_get "$id" '.cwd' "")"; sid="$(fleet_state_get "$id" '.session_id' "")"
  provider="$(fleet_state_get "$id" '.provider' claude)"
  mt=0; [[ -n "$cwd" && -n "$sid" ]] && mt="$(fleet_mtime "$(fleet_transcript_path "$cwd" "$sid" "$provider")")"
  local best=$hb; (( mt > best )) && best=$mt
  if [[ "${FLEET_JOURNAL:-off}" != "off" ]]; then
    jt="$(fleet_mtime "$(fleet_journal_path "$id")")"; (( jt > best )) && best=$jt
  fi
  printf '%s\n' "$best"
}

# Path to a child's optional activity journal (gated behind FLEET_JOURNAL).
fleet_journal_path() { printf '%s/%s.journal\n' "$CHILDSTATE_DIR" "$1"; }

# Append one activity line to a child's journal, then tail-truncate it to the
# last FLEET_JOURNAL_LINES (default 200) so it can't grow unbounded. No-op unless
# FLEET_JOURNAL is set. Used as a ground-truth liveness signal whose mtime feeds
# fleet_last_activity even when heartbeat + transcript are unavailable.
#   fleet_journal_append <id> [note...]
fleet_journal_append() {
  [[ "${FLEET_JOURNAL:-off}" != "off" ]] || return 0
  local id="$1"; shift || true
  local j; j="$(fleet_journal_path "$id")"
  mkdir -p "$CHILDSTATE_DIR" 2>/dev/null || true
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$j" 2>/dev/null || return 0
  local max="${FLEET_JOURNAL_LINES:-200}"
  local n; n="$(wc -l <"$j" 2>/dev/null || echo 0)"
  if [[ "$n" =~ ^[0-9]+$ ]] && (( n > max )); then
    tail -n "$max" "$j" >"$j.tmp" 2>/dev/null && mv "$j.tmp" "$j" 2>/dev/null || rm -f "$j.tmp"
  fi
}

# ---------------------------------------------------------------------------
# fleet_reconcile — re-derive the registry from GROUND TRUTH (live tmux windows
# + run/<id>.session), so the supervisor's view can survive a deleted state doc
# (one skipped hook used to wipe the index `fleet status` reads). Two guarantees:
#   * CREATES-ONLY: it only *creates* a missing doc; it NEVER modifies an
#     existing one (except the carefully-gated .ready unstick below).
#   * READ-ONLY on tmux: it inspects windows/panes, it never sends keys.
# Safe to run on every `fleet status` and from the watchdog. Disable with
# FLEET_RECONCILE=off (then the registry is whatever is on disk — old behaviour).
fleet_reconcile() {
  [[ "${FLEET_RECONCILE:-on}" == "off" ]] && return 0
  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    local f; f="$(fleet_state_path "$id")"
    if [[ ! -f "$f" ]]; then
      # Recreate the missing doc from the manifest's cwd (best-effort) + the
      # session id the SessionStart hook recorded under run/<id>.session.
      local rel cwd sid
      rel="$(fleet_child_get "$id" cwd "")"
      if [[ -n "$rel" ]]; then
        cwd="${WORKSPACE:-$PWD}/$rel"; [[ "$rel" == /* ]] && cwd="$rel"
      else
        cwd="${WORKSPACE:-$PWD}"
      fi
      fleet_state_ensure "$id" "$cwd" true
      sid=""; [[ -f "$RUN_DIR/$id.session" ]] && sid="$(<"$RUN_DIR/$id.session")"
      if [[ -n "$sid" ]]; then
        fleet_state_jq "$id" --arg s "$sid" '.session_id = (.session_id // $s)' >/dev/null 2>&1 || true
      fi
      # A reconciled doc reflects a still-running window.
      fleet_state_jq "$id" '.state = (if .state=="unknown" then "running" else .state end)' >/dev/null 2>&1 || true
      fleet_log reconcile "$id" "recreated state doc from live window${sid:+ + session ${sid:0:8}}"
    fi
    fleet_reconcile_unstick_ready "$id"
  done < <(fleet_tmux_window_ids)
}

# Carefully unstick a stranded mailbox: if .ready is not true (e.g. a missed Stop
# hook) BUT the pane is clearly at its idle prompt, set .ready=true so queued mail
# can drain. AND-gated by the idle check, so a mid-task worker is never flipped to
# ready (which would inject into its turn). Never sets .ready=false. Disable with
# FLEET_READY_UNSTICK=off.
fleet_reconcile_unstick_ready() {
  local id="$1"
  [[ "${FLEET_READY_UNSTICK:-on}" == "off" ]] && return 0
  local ready; ready="$(fleet_state_get "$id" '.ready' false)"
  [[ "$ready" == "true" ]] && return 0
  # Only consider unsticking when the registry believes there is undelivered mail.
  local inbox n; inbox="$(fleet_inbox_file "$id" 2>/dev/null)"
  [[ -n "$inbox" && -f "$inbox" ]] || return 0
  n="$(jq -s '[.[]|select(.delivered==false)]|length' "$inbox" 2>/dev/null || echo 0)"
  [[ "${n:-0}" -gt 0 ]] || return 0
  # Staleness rule: a missed Stop must not strand the mailbox forever. Treat
  # .ready as stale once (now-heartbeat) > TTL, AND only when the pane is idle.
  local now hb age ttl
  now="$(date +%s)"; ttl="${FLEET_READY_TTL_SECS:-${FLEET_IDLE_SECS:-300}}"
  hb="$(fleet_state_get "$id" '.heartbeat' 0)"; [[ "$hb" =~ ^[0-9]+$ ]] || hb=0
  age=$(( now - hb )); (( age < 0 )) && age=0
  (( age > ttl )) || return 0
  if fleet_pane_is_idle "$id"; then
    fleet_state_jq "$id" '.ready=true' >/dev/null 2>&1 || true
    fleet_log unstick "$id" "ready forced true (idle prompt, ${n} queued, heartbeat ${age}s stale)"
  fi
}
