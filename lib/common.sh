# shellcheck shell=bash
# common.sh — shared paths, helpers, logging for the fleet CLI.
# Sourced by bin/fleet. Not meant to be executed directly.

set -o pipefail

# --- tool location -----------------------------------------------------------
# TOOL_ROOT is the claude-fleet checkout (one level up from bin/).
: "${TOOL_ROOT:?TOOL_ROOT must be set by bin/fleet}"

# --- workspace + state discovery --------------------------------------------
# A workspace is a directory with `.fleet/fleet.toml`. The CLI finds it via
# $FLEET_WORKSPACE, then walks up from $PWD. A manifest-less legacy `.fleet/`
# is only a fallback, so stale nested runtime directories cannot shadow a real
# parent fleet.
fleet_find_workspace() {
  if [[ -n "${FLEET_WORKSPACE:-}" ]]; then
    printf '%s\n' "$FLEET_WORKSPACE"; return 0
  fi
  local d="$PWD" fallback=""
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/.fleet/fleet.toml" ]]; then printf '%s\n' "$d"; return 0; fi
    [[ -z "$fallback" && -d "$d/.fleet" ]] && fallback="$d"
    d="$(dirname "$d")"
  done
  [[ -n "$fallback" ]] && { printf '%s\n' "$fallback"; return 0; }
  return 1
}

# Stable, readable, path-scoped identity. The checksum prevents same-named
# workspaces in different parent directories from sharing a tmux server.
fleet_workspace_identity() {
  local workspace="${1:-${WORKSPACE:-}}" base slug sum _
  [[ -n "$workspace" ]] || return 1
  base="${workspace##*/}"
  slug="$(printf '%s' "$base" | LC_ALL=C tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//' | cut -c1-24)"
  [[ -n "$slug" ]] || slug="workspace"
  read -r sum _ < <(printf '%s' "$workspace" | cksum)
  printf 'fleet-%s-%s\n' "$slug" "$sum"
}

fleet_configure_identity() {
  local auto previous
  auto="$(fleet_workspace_identity "$WORKSPACE")" || return 1
  FLEET_WORKSPACE_ID="$auto"

  previous="${_FLEET_AUTO_TMUX_SESSION:-}"
  if [[ -z "${FLEET_TMUX_SESSION:-}" || "${FLEET_TMUX_SESSION:-}" == "$previous" ]]; then
    FLEET_TMUX_SESSION="$auto"; _FLEET_AUTO_TMUX_SESSION="$auto"
  fi
  previous="${_FLEET_AUTO_TMUX_SOCKET:-}"
  if [[ -z "${FLEET_TMUX_SOCKET:-}" || "${FLEET_TMUX_SOCKET:-}" == "$previous" ]]; then
    FLEET_TMUX_SOCKET="$auto"; _FLEET_AUTO_TMUX_SOCKET="$auto"
  fi
  previous="${_FLEET_AUTO_TMUX_UNIT:-}"
  if [[ -z "${FLEET_TMUX_UNIT:-}" || "${FLEET_TMUX_UNIT:-}" == "$previous" ]]; then
    FLEET_TMUX_UNIT="fleet-tmux-$auto"; _FLEET_AUTO_TMUX_UNIT="$FLEET_TMUX_UNIT"
  fi
  previous="${_FLEET_AUTO_SERVICE_NAME:-}"
  if [[ -z "${FLEET_SERVICE_NAME:-}" || "${FLEET_SERVICE_NAME:-}" == "$previous" ]]; then
    FLEET_SERVICE_NAME="$auto.service"; _FLEET_AUTO_SERVICE_NAME="$FLEET_SERVICE_NAME"
  fi
  export FLEET_WORKSPACE_ID FLEET_TMUX_SESSION FLEET_TMUX_SOCKET FLEET_TMUX_UNIT FLEET_SERVICE_NAME
}

# Resolve workspace + derived dirs into globals. `need_init=1` errors if absent.
# shellcheck disable=SC2120  # $1 is optional (defaults to 1); most callers pass none
fleet_load_paths() {
  local need_init="${1:-1}" found
  if ! found="$(fleet_find_workspace)"; then
    if [[ "$need_init" == "1" ]]; then
      die "no .fleet/ found. Run 'fleet init <workspace>' first, or set FLEET_WORKSPACE."
    fi
    return 1
  fi
  if ! WORKSPACE="$(cd -P "$found" 2>/dev/null && pwd)"; then
    [[ "$need_init" == "1" ]] && die "fleet workspace does not exist: $found"
    return 1
  fi
  FLEET_WORKSPACE="$WORKSPACE"
  STATE_DIR="$WORKSPACE/.fleet"
  MANIFEST="$STATE_DIR/fleet.toml"
  RUN_DIR="$STATE_DIR/run"
  CHILDSTATE_DIR="$STATE_DIR/state"
  LOG_FILE="$STATE_DIR/log/fleet.log"
  export FLEET_WORKSPACE WORKSPACE STATE_DIR MANIFEST RUN_DIR CHILDSTATE_DIR LOG_FILE
  # Per-workspace config: source .fleet/env if present — persistent FLEET_* settings
  # for this workspace (e.g. the liveness hardening), so they survive restarts/reboot
  # without relying on the launching shell's environment. It is the user's own file in
  # their own workspace (trusted). Read at call time before workspace identity is
  # finalized, so explicit FLEET_TMUX_* values still override automatic isolation.
  # NB: if/fi (not `&& source`) so an ABSENT env file doesn't make this function return
  # non-zero — under `set -e` that would abort every caller.
  if [[ -f "$STATE_DIR/env" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_DIR/env"
  fi
  # Do not let a sourced env redirect this invocation after discovery.
  FLEET_WORKSPACE="$WORKSPACE"
  fleet_configure_identity
  return 0
}

# --- transcript helpers ------------------------------------------------------
# Claude Code stores transcripts at ~/.claude/projects/<encoded-cwd>/<sid>.jsonl
# where <encoded-cwd> is the absolute cwd with every '/' replaced by '-'. Codex
# stores local sessions under $CODEX_HOME/sessions; that layout is searched by
# session id because it is date-sharded and provider-owned.
fleet_encode_path() { printf '%s\n' "$1" | sed 's:/:-:g'; }

fleet_projects_dir() { printf '%s\n' "${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"; }
fleet_codex_home() { printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"; }

# Path to a session's transcript given its cwd + session id (may not exist).
fleet_transcript_path() {
  local cwd="$1" sid="$2" provider="${3:-claude}"
  case "$provider" in
    codex)
      fleet_codex_transcript_path "$sid"
      ;;
    claude|*)
      printf '%s/%s/%s.jsonl\n' "$(fleet_projects_dir)" "$(fleet_encode_path "$cwd")" "$sid"
      ;;
  esac
}

fleet_codex_transcript_path() {
  local sid="$1" root
  root="$(fleet_codex_home)/sessions"
  [[ -n "$sid" && -d "$root" ]] || { printf '%s/%s.jsonl\n' "$root" "$sid"; return; }
  local f
  f="$(find "$root" -type f \( -name "$sid.jsonl" -o -name "*$sid*.jsonl" \) -print -quit 2>/dev/null || true)"
  printf '%s\n' "${f:-$root/$sid.jsonl}"
}

# Wall clock for AGENT-FACING text: local time, named zone, unambiguous date.
#
# An agent has no running clock. It learns the time only at the instants something is
# injected into its thread; its system prompt gives it a date at session start and
# nothing after. Before this existed a lane could not tell a one-minute gap from an
# overnight one, could not say how long it had been blocked, and could not act on
# "finish by Friday" — A DEADLINE YOU CANNOT LOCATE YOURSELF AGAINST IS A WISH.
#
# Local time with a named zone, not UTC: the humans reading these same threads work in
# it, and a lane reasoning about a deadline must reason in the zone the deadline was
# set in. ISO-ordered date so it sorts and so the YEAR stays visible — "06 Aug" is
# fine until the first January.
fleet_now_local() { date '+%Y-%m-%d %H:%M %Z'; }

# Parse a human-written deadline into an epoch. Accepts what someone actually types:
# "2026-08-08", "2026-08-08 17:00", "friday", "+2 days", "tomorrow 09:00".
# Prints the epoch on success; prints nothing and returns 1 on anything it cannot read.
#
# FAILS LOUD BY DESIGN. The caller must refuse rather than default: a deadline that
# silently became "now" or "never" because the string did not parse is the fail-open
# form of this feature, and it would be discovered by missing the date.
fleet_due_parse() {
  local s="${1:-}" e
  [[ -n "$s" ]] || return 1
  e="$(date -d "$s" +%s 2>/dev/null)" || return 1     # GNU date
  [[ "$e" =~ ^-?[0-9]+$ ]] || return 1
  printf '%s\n' "$e"
}

# Render a signed second-count as a short human duration: "2d 7h", "5h 12m", "45m", "30s".
# Two units at most — a deadline is a decision aid, not a stopwatch.
fleet_dur_short() {
  local s="${1:-0}"; s="${s#-}"
  local d=$(( s / 86400 )) h=$(( (s % 86400) / 3600 )) m=$(( (s % 3600) / 60 ))
  if   (( d > 0 )); then printf '%dd %dh\n' "$d" "$h"
  elif (( h > 0 )); then printf '%dh %dm\n' "$h" "$m"
  elif (( m > 0 )); then printf '%dm\n' "$m"
  else printf '%ds\n' "$s"; fi
}

# mtime (epoch secs) of a file, or 0 if missing. GNU stat then BSD stat.
fleet_mtime() {
  [[ -f "$1" ]] || { echo 0; return; }
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# Absolute path for an existing file/dir without relying on GNU readlink -f.
fleet_realpath() {
  local p="$1"
  if [[ -d "$p" ]]; then ( cd "$p" && pwd )
  else printf '%s/%s\n' "$( cd "$(dirname "$p")" 2>/dev/null && pwd )" "$(basename "$p")"; fi
}

# --- member ids and the paths derived from them ------------------------------
# A member id must be a PLAIN NAME. It is not just a label: it is interpolated
# into filesystem paths (state/<id>.json, run/<id>.exit, inbox/<id>.jsonl,
# memory/<id>.md) and used as a tmux window name. Anything that is not a plain
# name is therefore a boundary violation, not a cosmetic one:
#   * a leading '-' is never a legitimate id — it is always a misparsed flag, and
#     it is what registered the phantom members seen live (.fleet/state/--help.json,
#     .fleet/state/--.json), which then haunt status/doctor forever;
#   * '/' or '..' ESCAPE the state dir. Verified 2026-07-15 against 0ab4a0e:
#     `fleet_state_jq '../victim' '.state="pwned"'` rewrote a state doc OUTSIDE
#     CHILDSTATE_DIR, and `rm -f "$RUN_DIR/../keepme.exit"` deleted an out-of-tree
#     file — because validation lived ONLY in fleet_state_ensure, which an already
#     existing file short-circuits and which the launch path reached only AFTER
#     creating/destroying artifacts.
# This is an ALLOWLIST on purpose. A denylist is the wrong shape here, because an id
# is not only a path component: it is also interpolated into a tmux window name and
# into a `pkill -f` REGEX (fleet_bg_unmount, lib/faculty-bg.sh). A denylist that only
# bans '/' and '..' still admits '.*', which silently turns that "anchored" pattern
# into a match-everything regex and reaps EVERY controller in the fleet — so the
# charset, not the path, is the real boundary.
# Verified 2026-07-15 against all 66 live member ids on this host: every one of them
# ('core', 'android-codex', 'core-codex-claude-refute', 'a_b.c') fits this allowlist,
# and the only id that does not is the phantom '--help' this guard exists to reject.
fleet_valid_member_id() {
  local id="${1:-}"
  [[ -n "$id" ]] || return 1
  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  # '-' leads a misparsed flag, never a real id ('--help' was live in .fleet/state).
  [[ "$id" != -* ]] || return 1
  # '.'/'..' name a directory rather than a member. ('/' is already excluded above, so
  # traversal is impossible by construction; these stay as belt-and-braces.)
  [[ "$id" != "." && "$id" != ".." && "$id" != *..* ]] || return 1
  return 0
}

# The SINGLE choke point for id -> path. Prints "<dir>/<id><suffix>"; for an id
# that is not a plain name it prints NOTHING and returns 1, so every caller fails
# CLOSED rather than operating on a caller-chosen path. Callers must check:
#   f="$(fleet_member_path "$dir" "$id" .json)" || return 1
# (`local f; f="$(...)"` preserves the status; `local f="$(...)"` does NOT.)
#   fleet_member_path <dir> <id> <suffix>
fleet_member_path() {
  local dir="${1:-}" id="${2:-}" suffix="${3:-}"
  fleet_valid_member_id "$id" || return 1
  printf '%s/%s%s\n' "$dir" "$id" "$suffix"
}

# run/<id><suffix> — the .session / .exit / .argv run files. Validated.
fleet_run_path() { fleet_member_path "${RUN_DIR:-}" "${1:-}" "${2:-}"; }

# Refuse an invalid id AT A USER-FACING BOUNDARY, with one consistent diagnostic.
# Use this where an id arrives from argv and a clear error beats a silent skip; the
# path primitives above stay the last line of defence for everything else.
fleet_require_member_id() {
  fleet_valid_member_id "${1:-}" \
    || die "invalid member id '${1:-}': ids must match [A-Za-z0-9._-]+, and cannot be empty, start with '-', or be '.'/'..'"
}

# --- symlink safety (fd-bound, no-follow) ------------------------------------
# A validated id keeps a path INSIDE its dir, but a valid id is not enough: a
# pre-planted OR RACE-REPLANTED symlink at that in-tree path redirects the open to
# an out-of-tree target. Verified 2026-07-15 against 6d19957: a symlink at
# inbox/<validid>.jsonl.lock was FOLLOWED by `exec 9>"$f.lock"` and an out-of-tree
# file was TRUNCATED — with a perfectly valid id 'core'. Same class hits every state
# read and journal/argv/inbox write.
#
# Bash cannot express O_NOFOLLOW, so the REAL fix lives in a tiny helper
# (lib/fleet-safeio.py) that opens each path with O_NOFOLLOW and does an fstat on the
# resulting fd — the open IS the check, so there is NO check-then-open window even
# against a live replant racer. The four hardened operations route through it:
#   * READ   (state_get, state_jq)        -> fleet_safe_read   (O_RDONLY|O_NOFOLLOW)
#   * APPEND (enqueue inbox, journal)      -> fleet_safe_append (O_APPEND|O_CREAT|O_NOFOLLOW)
#   * REPLACE(atomic_write: state, argv..) -> fleet_safe_write  (O_EXCL temp -> rename)
# fleet_safe_write also holds when the helper is absent: rename() never follows a final
# symlink, so the overwrite/truncate class is safe in pure shell too (it only adds a
# dir/special-file refusal). READ and APPEND, by contrast, REQUIRE the helper for a
# no-follow open; without it they FAIL CLOSED (refuse) — we do NOT relabel the old
# check-then-open as safe. python3 is therefore a prerequisite for the mailbox/state
# hardening (see README Prerequisites); a host without it degrades those paths to
# refusal, never to an unsafe follow.

# Absolute path to the no-follow / pidfd helper.
FLEET_SAFEIO="${FLEET_SAFEIO:-$TOOL_ROOT/lib/fleet-safeio.py}"

# True iff the fd-bound no-follow primitive is usable here (python3 + helper present).
# Cached in _FLEET_SAFEIO_OK so the probe runs once per process.
fleet_safeio_available() {
  if [[ -z "${_FLEET_SAFEIO_OK:-}" ]]; then
    if command -v python3 >/dev/null 2>&1 && [[ -f "$FLEET_SAFEIO" ]]; then
      _FLEET_SAFEIO_OK=1
    else
      _FLEET_SAFEIO_OK=0
    fi
    export _FLEET_SAFEIO_OK
  fi
  [[ "$_FLEET_SAFEIO_OK" == 1 ]]
}

# One-time loud note when the safe primitive is missing on a read/append path, so a
# fail-closed default is never silently mistaken for real data. Guarded so status/doctor
# don't spam. FLEET_SAFEIO_QUIET=1 silences it (tests set this).
_fleet_safeio_warn_once() {
  [[ -n "${_FLEET_SAFEIO_WARNED:-}" || -n "${FLEET_SAFEIO_QUIET:-}" ]] && return 0
  _FLEET_SAFEIO_WARNED=1; export _FLEET_SAFEIO_WARNED
  warn "python3 (lib/fleet-safeio.py) not available: mailbox/state safe IO fails CLOSED (see README Prerequisites)."
}

# READ <path> to stdout with a no-follow open. Exit: 0 ok, 3 refused (symlink/non-
# regular), 4 absent, 5 primitive-unavailable. Callers treat any non-zero as "no
# content" and fall back to their default — a fail-closed read, never a follow.
fleet_safe_read() {
  local p="${1:-}"; [[ -n "$p" ]] || return 2
  if fleet_safeio_available; then
    python3 "$FLEET_SAFEIO" read "$p"; return $?
  fi
  _fleet_safeio_warn_once; return 5
}

# APPEND stdin to <path> with a no-follow open (creates if absent). Exit: 0 ok, 3
# refused (symlink/non-regular), 5 primitive-unavailable. FAILS CLOSED without python3.
fleet_safe_append() {
  local p="${1:-}"; [[ -n "$p" ]] || return 2
  if fleet_safeio_available; then
    python3 "$FLEET_SAFEIO" append "$p"; return $?
  fi
  _fleet_safeio_warn_once; return 5
}

# Atomically REPLACE <dest> with stdin, WITHOUT following a symlink at <dest>. ALWAYS via
# the helper (O_EXCL|O_NOFOLLOW temp -> fsync -> rename), never a shell `mv`: a shell
# `[[ -d ]]` check then `mv` is itself TOCTOU — the dest can race from regular/absent to a
# DIRECTORY after the check, and `mv` would then DESCEND into it, moving the temp inside and
# silently defeating the atomic replace. rename(2) can never descend (a dir dest fails
# atomically), so the helper is the only correct primitive. FAILS CLOSED (return 5) when the
# helper is unavailable — we do not fall back to an unsafe `mv`.
fleet_safe_write() {
  local dest="${1:-}"; [[ -n "$dest" ]] || return 1
  if fleet_safeio_available; then
    python3 "$FLEET_SAFEIO" write "$dest"; return $?
  fi
  _fleet_safeio_warn_once; return 5
}

# Back-compat name kept for existing call sites (state_ensure, argv writer, .session).
fleet_atomic_write() { fleet_safe_write "${1:-}"; }

# ENQUEUE: one locked no-follow transaction (helper `enqueue`) — flock the lock and APPEND
# stdin to the inbox, both O_NOFOLLOW, then release. Replaces the shell `exec 9>>lock` +
# `>>inbox`. Reads the message line on stdin. FAILS CLOSED (5) without the primitive.
fleet_safe_enqueue() {
  local inbox="${1:-}" lock="${2:-}"; [[ -n "$inbox" && -n "$lock" ]] || return 1
  fleet_safeio_available || { _fleet_safeio_warn_once; return 5; }
  python3 "$FLEET_SAFEIO" enqueue "$inbox" "$lock"; return $?
}

# Atomically GRAB <src> as <dst> via rename (helper `rotate`) — the drain's snapshot: after
# it, the read-modify-write runs on <dst>, an inode no other writer can name or swap. Returns
# 0 (grabbed), 4 (src absent), non-zero (error / no primitive -> fail closed).
fleet_safe_rotate() {
  local src="${1:-}" dst="${2:-}"; [[ -n "$src" && -n "$dst" ]] || return 1
  fleet_safeio_available || { _fleet_safeio_warn_once; return 5; }
  python3 "$FLEET_SAFEIO" rotate "$src" "$dst"; return $?
}

# Plain atomic rename (helper `rename`) — used ONLY to RESTORE a drain snapshot back to the
# inbox on abort, so mail is never lost. Never descends, never follows a final symlink.
fleet_safe_rename() {
  local src="${1:-}" dst="${2:-}"; [[ -n "$src" && -n "$dst" ]] || return 1
  fleet_safeio_available || { _fleet_safeio_warn_once; return 5; }
  python3 "$FLEET_SAFEIO" rename "$src" "$dst"; return $?
}

# Hold a no-follow flock on <lockpath> across arbitrary shell work, via a coprocess that
# OWNS the fd (bash cannot open O_NOFOLLOW itself). The drain's read-modify-write runs
# between fleet_safe_lock and fleet_safe_unlock without ever opening the lock in shell.
# Only ONE such lock is held at a time (bash allows a single active coproc); the drain is
# the sole caller and always releases before returning. 0 = locked; non-zero (incl. 5 = no
# primitive, or a refused symlinked/non-regular lock) = fail closed, nothing held.
fleet_safe_lock() {
  local lockpath="${1:-}"; [[ -n "$lockpath" ]] || return 1
  fleet_safeio_available || { _fleet_safeio_warn_once; return 5; }
  mkdir -p "$(dirname "$lockpath")" 2>/dev/null || true
  coproc _FLEET_LOCKP { python3 "$FLEET_SAFEIO" hold-lock "$lockpath"; }
  _FLEET_LOCK_W=${_FLEET_LOCKP[1]}; _FLEET_LOCK_R=${_FLEET_LOCKP[0]}; _FLEET_LOCK_PID=$_FLEET_LOCKP_PID
  local line=''
  IFS= read -r line <&"${_FLEET_LOCK_R}" 2>/dev/null || line=''
  if [[ "$line" != "LOCKED" ]]; then
    { exec {_FLEET_LOCK_W}>&-; } 2>/dev/null || true
    wait "$_FLEET_LOCK_PID" 2>/dev/null || true
    unset _FLEET_LOCK_W _FLEET_LOCK_R _FLEET_LOCK_PID
    return 1
  fi
  return 0
}

# Release the lock held by fleet_safe_lock (idempotent).
fleet_safe_unlock() {
  [[ -n "${_FLEET_LOCK_W:-}" ]] || return 0
  # Redirection on a bare `exec` persists in the caller. Keep stderr suppression
  # on a command group or every later diagnostic in this CLI disappears.
  { exec {_FLEET_LOCK_W}>&-; } 2>/dev/null || true  # close stdin -> holder exits
  { exec {_FLEET_LOCK_R}<&-; } 2>/dev/null || true
  wait "${_FLEET_LOCK_PID}" 2>/dev/null || true
  unset _FLEET_LOCK_W _FLEET_LOCK_R _FLEET_LOCK_PID
}

# BEST-EFFORT (check-then-open, NOT atomic): true iff <path> is absent or a regular
# file that is not a symlink. RETAINED only as a cheap pre-filter where a subsequent
# fleet_safe_* call is the real no-follow guard; never rely on it alone. Do not describe
# it as race-safe.
fleet_path_regular_or_absent() {
  local p="${1:-}"
  [[ -n "$p" ]] || return 1
  [[ -L "$p" ]] && return 1          # a symlink is tampering: refuse to follow it
  [[ -e "$p" ]] || return 0          # absent -> fine
  [[ -f "$p" ]]                      # exists -> must be a regular file
}

# --- jq guard ----------------------------------------------------------------
fleet_require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not found on PATH."
}

# --- logging -----------------------------------------------------------------
# Append a structured event to the aggregate log. fleet_log <event> <id> [msg...]
fleet_log() {
  local event="$1" id="${2:--}"; shift 2 || true
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '%s\t%s\t%s\t%s\n' "$ts" "$event" "$id" "$*" >>"$LOG_FILE"
}

# --- output helpers ----------------------------------------------------------
c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_red=$'\033[31m'; c_grn=$'\033[32m'
c_yel=$'\033[33m'; c_blu=$'\033[34m'; c_bold=$'\033[1m'
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
  c_reset='' c_dim='' c_red='' c_grn='' c_yel='' c_blu='' c_bold=''
fi

warn() { printf '%sfleet:%s %s\n' "$c_yel" "$c_reset" "$*" >&2; }
die()  { printf '%sfleet: error:%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

# Relative time, e.g. "12s", "4m", "3h", "2d", from an epoch seconds value.
fleet_ago() {
  local then="$1" now; now="$(date +%s)"
  [[ "$then" -le 0 ]] && { echo "never"; return; }
  local d=$(( now - then ))
  (( d < 0 )) && d=0
  if   (( d < 60 ));     then echo "${d}s"
  elif (( d < 3600 ));   then echo "$(( d/60 ))m"
  elif (( d < 86400 ));  then echo "$(( d/3600 ))h"
  else                        echo "$(( d/86400 ))d"
  fi
}
