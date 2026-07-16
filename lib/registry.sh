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

# state/<id>.json — validated via the central choke point (lib/common.sh), so an id
# that is not a plain name yields NO path and a non-zero status instead of one that
# escapes CHILDSTATE_DIR. Every caller below fails closed on that status.
fleet_state_path() { fleet_member_path "${CHILDSTATE_DIR:-}" "${1:-}" .json; }

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
# Rejecting at REGISTRATION stops the phantom members observed live
# (.fleet/state/--help.json, --.json). NB: this is no longer the ONLY guard —
# registration is not a boundary an existing file has to cross, so the real
# choke point is fleet_member_path (lib/common.sh). fleet_valid_member_id is
# called here only to `die` with a helpful message on the registration path.
fleet_state_ensure() {
  local id="$1" cwd="$2" managed="${3:-false}"
  fleet_require_member_id "$id"
  local f; f="$(fleet_state_path "$id")" || return 1
  mkdir -p "$CHILDSTATE_DIR"
  # A symlink here is refused so we neither read it as "present" nor create through it;
  # the write itself also goes via temp+rename (fleet_atomic_write), so even a link
  # replanted after this check is replaced rather than followed (no out-of-tree create).
  [[ -L "$f" ]] && { warn "refusing state write: '$f' is a symlink"; return 1; }
  [[ -f "$f" ]] && return 0
  jq -n --arg id "$id" --arg cwd "$cwd" --argjson managed "$managed" '
    { id: $id, managed: $managed, provider: "claude", session_id: null, cwd: $cwd, pid: null,
      state: "unknown", current_task: null, claims: [],
      started_at: null, heartbeat: null, reason: null, restarts: [] }' | fleet_atomic_write "$f"
}

# Apply a jq program to the doc in place. The LAST argument is the jq program;
# any args before it are forwarded to jq (e.g. --arg k v).
#   fleet_state_jq <id> [jq-args...] <program>
fleet_state_jq() {
  local id="$1"; shift
  # Fail CLOSED before touching the filesystem. This is the hole the registration
  # guard did NOT cover: an EXISTING file short-circuits fleet_state_ensure, so
  # '../victim' never reached the only validator and jq rewrote a doc outside
  # CHILDSTATE_DIR (reproduced against 0ab4a0e; tests/window-alloc.sh section E).
  local f; f="$(fleet_state_path "$id")" || return 1
  local -a a=( "$@" ); local n=${#a[@]}
  (( n >= 1 )) || return 1
  local prog="${a[n-1]}"; unset 'a[n-1]'
  # READ the doc through a fd-bound no-follow open (fleet_safe_read). The open IS the
  # check — a pre-planted or race-replanted symlink cannot be followed and leak an
  # out-of-tree doc; a missing primitive FAILS CLOSED (refuse). rc: 0 ok, 4 absent (create
  # then re-read), 3 symlink/non-regular (refuse), 5 no-primitive (fail closed).
  local content rc=0
  content="$(fleet_safe_read "$f")" || rc=$?
  if (( rc == 4 )); then
    fleet_state_ensure "$id" "$PWD" false || return 1
    rc=0; content="$(fleet_safe_read "$f")" || rc=$?
  fi
  if (( rc != 0 )); then
    (( rc == 3 )) && warn "refusing state read/write: '$f' is not a regular file"
    return 1
  fi
  # Transform, then REPLACE via the no-follow atomic write (rename drops a squatted link,
  # refuses a dir/special/foreign dest). jq failure leaves the doc untouched.
  local out
  out="$(printf '%s' "$content" | jq "${a[@]}" "$prog" 2>/dev/null)" || return 1
  printf '%s' "$out" | fleet_safe_write "$f"
}

# Read a single field. fleet_state_get <id> <jq-path> [default]
fleet_state_get() {
  local id="$1" path="$2" def="${3:-}"
  # Read path: an invalid id is indistinguishable from an absent doc, so answer the
  # default rather than `die` — a bad id in the registry must not take `fleet status`
  # down with it. Fail closed, stay honest, keep the caller alive.
  local f; f="$(fleet_state_path "$id")" || { printf '%s\n' "$def"; return; }
  # Fd-bound no-follow read (fleet_safe_read): never `jq` through a link (that would read
  # an out-of-tree file the id was never allowed to name). Any non-zero — absent, symlink,
  # non-regular, or primitive-unavailable — yields the caller's default (fail closed).
  local content rc=0
  content="$(fleet_safe_read "$f")" || rc=$?
  (( rc != 0 )) && { printf '%s\n' "$def"; return; }
  local v; v="$(printf '%s' "$content" | jq -r "$path // empty" 2>/dev/null)"
  printf '%s\n' "${v:-$def}"
}

# Last-turn CONTEXT size for <id>, in tokens = cache_read + cache_creation input
# tokens of the most recent assistant turn in its transcript. This is the figure
# every turn re-processes — the per-turn token cost that drives rate-limits and
# "running out" — and what proactive /compact makes sawtooth. Prints an integer
# (0 if unknown). Cheap: reads only the transcript TAIL, not the whole file.
fleet_ctx_tokens() {
  local id="$1" sid cwd provider f buf r c
  sid="$(fleet_state_get "$id" '.session_id' '')"
  cwd="$(fleet_state_get "$id" '.cwd' '')"
  provider="$(fleet_state_get "$id" '.provider' claude)"
  [[ -z "$sid" || "$sid" == "null" || -z "$cwd" || "$cwd" == "null" ]] && { printf '0\n'; return 1; }
  f="$(fleet_transcript_path "$cwd" "$sid" "$provider")"
  [[ -f "$f" ]] || { printf '0\n'; return 1; }
  buf="$(tail -c "${FLEET_CTX_TAIL_BYTES:-300000}" "$f" 2>/dev/null)"
  r="$(printf '%s' "$buf" | grep -o '"cache_read_input_tokens":[0-9]*'     | tail -1 | grep -o '[0-9]*')"
  c="$(printf '%s' "$buf" | grep -o '"cache_creation_input_tokens":[0-9]*' | tail -1 | grep -o '[0-9]*')"
  printf '%s\n' "$(( ${r:-0} + ${c:-0} ))"
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
  # tmux-native activity: #{window_activity} is the pane's last-output epoch — a more
  # responsive liveness signal than transcript mtime. Bench (2026-06-29): it stays
  # FLAT while the TUI sits idle, so it raises "live" only on real output and never
  # masks a genuinely idle worker. Opt-in (FLEET_TMUX_ACTIVITY); only ever increases
  # `best`, so it can't make a live worker look dead.
  if [[ "${FLEET_TMUX_ACTIVITY:-off}" != "off" ]] && declare -F fleet_tmux_window_activity >/dev/null 2>&1; then
    local wa; wa="$(fleet_tmux_window_activity "$id")"
    [[ "$wa" =~ ^[0-9]+$ ]] && (( wa > best )) && best=$wa
  fi
  printf '%s\n' "$best"
}

# Path to a child's optional activity journal (gated behind FLEET_JOURNAL). Validated:
# an unguarded '../../escaped' here wrote a journal outside the state dir (verified
# against 0ab4a0e).
fleet_journal_path() { fleet_member_path "${CHILDSTATE_DIR:-}" "${1:-}" .journal; }

# Append one activity line to a child's journal, then tail-truncate it to the
# last FLEET_JOURNAL_LINES (default 200) so it can't grow unbounded. No-op unless
# FLEET_JOURNAL is set. Used as a ground-truth liveness signal whose mtime feeds
# fleet_last_activity even when heartbeat + transcript are unavailable.
#   fleet_journal_append <id> [note...]
fleet_journal_append() {
  [[ "${FLEET_JOURNAL:-off}" != "off" ]] || return 0
  local id="$1"; shift || true
  local j; j="$(fleet_journal_path "$id")" || return 0   # invalid id: write nothing
  mkdir -p "$CHILDSTATE_DIR" 2>/dev/null || true
  # Fd-bound no-follow APPEND (fleet_safe_append). A squatted/replanted symlink cannot be
  # followed; a missing primitive just disables the journal for this call. The journal is
  # best-effort by design, so every failure path is a quiet no-op (never fatal).
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | fleet_safe_append "$j" 2>/dev/null || return 0
  local max="${FLEET_JOURNAL_LINES:-200}"
  local n; n="$(fleet_safe_read "$j" 2>/dev/null | wc -l 2>/dev/null || echo 0)"
  if [[ "$n" =~ ^[0-9]+$ ]] && (( n > max )); then
    # tail-truncate via a no-follow read piped into a no-follow rename write.
    fleet_safe_read "$j" 2>/dev/null | tail -n "$max" | fleet_safe_write "$j" 2>/dev/null || true
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
    # ids here come from live tmux WINDOW NAMES, not from our own state dir — a window
    # named '../evil' must not be able to steer reconcile into creating a doc outside
    # CHILDSTATE_DIR. Skip anything that is not a plain name.
    local f; f="$(fleet_state_path "$id")" || continue
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
      local sf; sf="$(fleet_run_path "$id" .session)" || continue
      sid=""; [[ -f "$sf" ]] && sid="$(<"$sf")"
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
  local inbox n; inbox="$(fleet_inbox_file "$id" 2>/dev/null)" || inbox=""
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
