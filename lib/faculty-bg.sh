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
  f="$(fleet_inbox_file "$to")" || return 0; [[ -f "$f" ]] || return 0
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
    local _reply _ok=0
    _reply="$(fleet_bg_deliver_turn "$sid" "$cwd" "[fleet msg from $from] $text")" && _ok=1   # claude-bg is claude-only
    if (( _ok == 1 )); then
      printf '  → [%s] %s\n  ← %s\n' "$from" "$text" "${_reply:0:400}"   # render the turn (visible in the controller window)
      printf '%s\n' "$(jq -c '.delivered=true' <<<"$line")" >>"$f.tmp"
    else
      rc=1; printf '%s\n' "$line" >>"$f.tmp"   # leave queued; retry next drain
    fi
  done
  mv "$f.tmp" "$f" 2>/dev/null || rm -f "$f.tmp"
  flock -u 9 2>/dev/null || true; exec 9>&-
  return "$rc"
}

# --- Codex Model-B primitives (codex exec resume; same shape as the claude ones) ---
# DORMANT (2026-06-30): claude-bg is now claude-only. Codex is NOT a per-worker brain —
# it runs as a single read-only refuter window via `fleet refute` / bin/codex-review
# (the canonical adversarial-helper role). These primitives are retained, unused, as a
# proven building block for a possible future dedicated codex-bg adapter. See ADR-002.
# Codex is durable + resumable like Claude, but reports its session id on a
# "session id: <uuid>" line (not json), and a turn is `codex exec resume <id>`.
# Verified 0.142.3. Workers run unattended → bypass approvals/sandbox when skip-perms.
_fleet_codex_perm() { [[ "${FLEET_SKIP_PERMISSIONS:-on}" != "off" ]] && printf '%s\n' --dangerously-bypass-approvals-and-sandbox; }

# Establish a NEW durable Codex session; print its session id (parsed from output).
fleet_codex_start_session() {
  local cwd="$1" prompt="$2" bin out; bin="$(fleet_provider_bin codex)"
  local -a perm=(); mapfile -t perm < <(_fleet_codex_perm)
  out="$( cd "$cwd" 2>/dev/null && timeout "${FLEET_BG_TURN_TIMEOUT:-600}" \
    "$bin" exec --skip-git-repo-check "${perm[@]}" "$prompt" </dev/null 2>&1 )" || true   # </dev/null: codex exec blocks on stdin otherwise
  sed -n 's/.*session id:[[:space:]]*\([0-9a-fA-F-]\{16,\}\).*/\1/p' <<<"$out" | head -1
}

# Deliver one turn to a Codex session by resume; print a short reply tail. Non-zero
# on failure. NO keystrokes — the delivery fix, Codex side.
fleet_codex_deliver_turn() {
  local sid="$1" cwd="$2" text="$3" bin out; bin="$(fleet_provider_bin codex)"
  [[ -n "$sid" && "$sid" != "null" ]] || return 1
  local -a perm=(); mapfile -t perm < <(_fleet_codex_perm)
  out="$( cd "$cwd" 2>/dev/null && timeout "${FLEET_BG_TURN_TIMEOUT:-600}" \
    "$bin" exec resume "$sid" --skip-git-repo-check "${perm[@]}" "$text" </dev/null 2>&1 )" || return 1   # </dev/null: codex exec blocks on stdin otherwise
  awk '/^codex$/{f=1;b="";next} /^tokens used/{f=0} f{b=b" "$0} END{print b}' <<<"$out" | sed 's/^ *//' | head -c 400
}

# Any undelivered mail queued for <to>?  (controller uses this to prioritise mail.)
fleet_bg_has_mail() {
  local f; f="$(fleet_inbox_file "$1")" || return 1; [[ -f "$f" ]] || return 1
  local n; n="$(jq -s '[.[]|select(.delivered==false)]|length' "$f" 2>/dev/null || echo 0)"
  [[ "${n:-0}" -gt 0 ]]
}

# Establish a NEW durable session (first turn) in <cwd> with <prompt>; print its
# session_id on success. The first turn IS the worker's initial autonomous work.
#   fleet_bg_start_session <cwd> <prompt>
fleet_bg_start_session() {
  local cwd="$1" prompt="$2" bin out
  bin="$(fleet_provider_bin claude)"
  local -a perm=(); [[ "${FLEET_SKIP_PERMISSIONS:-on}" != "off" ]] && perm=(--dangerously-skip-permissions)
  out="$( cd "$cwd" 2>/dev/null && timeout "${FLEET_BG_TURN_TIMEOUT:-600}" \
    "$bin" -p --output-format json "${perm[@]}" "$prompt" 2>/dev/null )" || return 1
  jq -r '.session_id // empty' <<<"$out" 2>/dev/null
}

# Mount a worker under the claude-bg adapter: launch its CONTROLLER in a tmux window
# named <id> (so it still appears in the unified fleet view + reuses window-based
# liveness/attach), and the controller drives the worker's durable session
# turn-by-turn (keystroke-free). Mirrors fleet_tmux_start_child's setup.
#   fleet_bg_mount <id>
fleet_bg_mount() {
  local id="$1"
  # This path spawns its window with a DIRECT `fleet_tmux new-window` (below) rather
  # than via fleet_tmux_new_agent_window, so it does not inherit that function's guard.
  # Validate here explicitly instead of relying on fleet_state_ensure further down —
  # ordering, not intent, is what kept this safe before.
  fleet_require_member_id "$id"
  fleet_tmux_ensure_session
  fleet_tmux_has_window "$id" && { warn "child '$id' already has a window"; return 0; }
  local rel cwd; rel="$(fleet_child_get "$id" cwd ".")"
  cwd="$WORKSPACE/$rel"; [[ "$rel" == /* ]] && cwd="$rel"
  [[ -d "$cwd" ]] || die "child '$id': cwd does not exist: $cwd"
  fleet_state_ensure "$id" "$cwd" true
  local provider; provider="$(fleet_provider_for_child "$id")"
  # claude-bg is claude-only. A codex worker must not be driven by the controller —
  # codex is the refuter, not a per-worker brain. Divert it to the proven cli-tmux path.
  if [[ "$provider" == "codex" ]]; then
    warn "child '$id': codex is not supported on claude-bg (codex = refuter only); mounting on cli-tmux instead"
    fleet_tmux_start_child "$id"; return $?
  fi
  # Record the adapter so the cli-tmux mail path (notify / on-stop drain / watchdog)
  # SKIPS this worker — its controller is the sole, keystroke-free deliverer. Record
  # the real provider so the controller drives claude (-p --resume) or codex (exec resume).
  fleet_state_jq "$id" --arg p "$provider" '.state="running" | .reason=null | .provider=$p | .faculty="claude-bg"' >/dev/null
  # "$FLEET_TMUX_SESSION:" — the trailing colon is load-bearing; a bare session name is
  # resolved by window-NAME match and collides with any window named like the session
  # ("fleet" → "fleet-fix"). See fleet_tmux_new_agent_window / tests/window-alloc.sh.
  fleet_tmux new-window -t "$FLEET_TMUX_SESSION:" -n "$id" -c "$cwd" \
    -e "TOOL_ROOT=$TOOL_ROOT" -e "FLEET_WORKSPACE=$WORKSPACE" -e "FLEET_CHILD_ID=$id" \
    -e "FLEET_FACULTY_ADAPTER=claude-bg" -e "FLEET_SKIP_PERMISSIONS=${FLEET_SKIP_PERMISSIONS:-on}" \
    "$TOOL_ROOT/lib/bg-controller.sh" "$id"
  declare -F transport_register >/dev/null 2>&1 && transport_register "$id"
}

# Unmount a claude-bg worker: kill its window (which kills the controller running in it)
# AND reap any orphaned controller process for this id. Killing the window normally takes
# the controller bash loop with it, but a restart that re-mounted before the prior window
# fully died could leave a duplicate controller — so we explicitly pkill the loop by its
# exact argv (anchored so 'specs' never matches 'specs2'). Idempotent.
#   fleet_bg_unmount <id>
# PIDs of running bg-controllers whose argv is EXACTLY [... , <*bg-controller.sh>, <id>].
# NB: the LIVE reap no longer calls this — fleet_bg_unmount signals via the pidfd helper
# (lib/fleet-safeio.py `signal`), which does the same argv-identity match AND binds a pidfd
# so a recycled pid can't be struck. This shell matcher is retained as a read-only
# diagnostic that tests/window-alloc.sh section F exercises to pin the exact-identity rule.
# We match by argv IDENTITY via /proc, not by a `pkill -f` regex the id is spliced into.
# That splice was a real defect (confirmed 2026-07-15 against 6d19957): the allowlist
# admits '.', and in a `pkill` regex '.' matches ANY char, so the "anchored" pattern
# `bg-controller\.sh a.b$` reaped a DIFFERENT controller running for id 'aXb'. An exact
# byte-for-byte compare of the last argv token cannot collide. The pgrep prefilter uses
# the fixed string 'bg-controller' (no metacharacters), so the id never touches a regex.
# Linux-only (needs /proc): on a host without it this yields no pids and the window kill
# in fleet_tmux_stop_child remains the teardown — safer to under-reap than mis-reap.
_fleet_bg_controller_pids() {
  local id="$1" pid
  command -v pgrep >/dev/null 2>&1 || return 0
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [[ -r "/proc/$pid/cmdline" ]] || continue
    local -a argv=()
    mapfile -d '' -t argv < "/proc/$pid/cmdline" 2>/dev/null || continue
    local n=${#argv[@]}
    (( n >= 2 )) || continue
    [[ "${argv[n-1]}" == "$id" ]] || continue            # last token == id, byte-for-byte
    [[ "${argv[n-2]}" == *bg-controller.sh ]] || continue # launched as `bg-controller.sh <id>`
    printf '%s\n' "$pid"
  done < <(pgrep -f 'bg-controller' 2>/dev/null)
}

fleet_bg_unmount() {
  local id="$1"
  # Still reject a junk id up front — but note the allowlist is NOT what makes the reap
  # safe (it admits '.'); the exact argv match is.
  fleet_valid_member_id "$id" || { warn "refusing to unmount invalid member id '$id'"; return 1; }
  declare -F fleet_tmux_stop_child >/dev/null 2>&1 && fleet_tmux_stop_child "$id" 2>/dev/null || true
  # Reap the orphaned controller ONLY via the pidfd path (lib/fleet-safeio.py `signal`). It
  # binds a pidfd to each argv-identity match and RE-VALIDATES the cmdline after binding, so
  # a pid RECYCLED between discovery and the signal can never be struck — pidfd_send_signal
  # targets THAT process instance or fails ESRCH, never a reused pid. SIGTERM = 15.
  #
  # There is DELIBERATELY no discover-then-`kill` fallback: doing so would reopen the exact
  # discovery->signal pid-reuse window this path exists to close (a `kill <pid>` on a number
  # recycled to an unrelated process). When pidfd is unavailable (no python3, non-Linux) we
  # UNDER-REAP and rely on the tmux window kill above — under-reaping is safe; mis-reaping is
  # not. This is fail-closed, and documented as the platform boundary (README Prerequisites).
  if declare -F fleet_safeio_available >/dev/null 2>&1 && fleet_safeio_available && [[ -d /proc ]]; then
    python3 "$FLEET_SAFEIO" signal 15 "$id" >/dev/null 2>&1 || true
  fi
}
