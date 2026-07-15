# shellcheck shell=bash
# common.sh — shared paths, helpers, logging for the fleet CLI.
# Sourced by bin/fleet. Not meant to be executed directly.

set -o pipefail

# --- tool location -----------------------------------------------------------
# TOOL_ROOT is the claude-fleet checkout (one level up from bin/).
: "${TOOL_ROOT:?TOOL_ROOT must be set by bin/fleet}"

# --- workspace + state discovery --------------------------------------------
# A workspace is any directory that holds a `.fleet/` state dir. The CLI finds
# it via, in order: $FLEET_WORKSPACE, then walking up from $PWD.
fleet_find_workspace() {
  if [[ -n "${FLEET_WORKSPACE:-}" ]]; then
    printf '%s\n' "$FLEET_WORKSPACE"; return 0
  fi
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -d "$d/.fleet" ]] && { printf '%s\n' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

# Resolve workspace + derived dirs into globals. `need_init=1` errors if absent.
# shellcheck disable=SC2120  # $1 is optional (defaults to 1); most callers pass none
fleet_load_paths() {
  local need_init="${1:-1}"
  if ! WORKSPACE="$(fleet_find_workspace)"; then
    if [[ "$need_init" == "1" ]]; then
      die "no .fleet/ found. Run 'fleet init <workspace>' first, or set FLEET_WORKSPACE."
    fi
    return 1
  fi
  STATE_DIR="$WORKSPACE/.fleet"
  MANIFEST="$STATE_DIR/fleet.toml"
  RUN_DIR="$STATE_DIR/run"
  CHILDSTATE_DIR="$STATE_DIR/state"
  LOG_FILE="$STATE_DIR/log/fleet.log"
  export WORKSPACE STATE_DIR MANIFEST RUN_DIR CHILDSTATE_DIR LOG_FILE
  # Per-workspace config: source .fleet/env if present — persistent FLEET_* settings
  # for this workspace (e.g. the liveness hardening), so they survive restarts/reboot
  # without relying on the launching shell's environment. It is the user's own file in
  # their own workspace (trusted). Read at call time, so it overrides call-time-read
  # FLEET_* vars; it cannot override source-time lib defaults (e.g. FLEET_TMUX_SESSION).
  # NB: if/fi (not `&& source`) so an ABSENT env file doesn't make this function return
  # non-zero — under `set -e` that would abort every caller.
  if [[ -f "$STATE_DIR/env" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_DIR/env"
  fi
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

# --- symlink safety ----------------------------------------------------------
# A validated id keeps a path INSIDE its dir, but a valid id is not enough: a
# pre-planted SYMLINK at that in-tree path redirects the open to an out-of-tree
# target. Verified 2026-07-15 against 6d19957: a symlink at inbox/<validid>.jsonl.lock
# was FOLLOWED by `exec 9>"$f.lock"` and an out-of-tree file was TRUNCATED — with a
# perfectly valid id 'core'. Same class hits every state read and journal/argv/inbox
# write. Bash has no O_NOFOLLOW, so we split the defence by HARM:
#
#   * TRUNCATE / OVERWRITE (the sharp harm) is removed STRUCTURALLY, with no TOCTOU:
#     fleet_atomic_write() writes a fresh temp and rename()s it over the destination —
#     rename replaces a squatted symlink (its target is never opened for write) and is
#     atomic, so there is no check-then-open window. The lock uses an APPEND open
#     (`>>`), which cannot truncate regardless of what the path points at.
#   * READS and APPENDS fall back to a best-effort check (fleet_path_regular_or_absent
#     below). This is CHECK-THEN-OPEN, NOT atomic no-follow: a concurrent same-dir
#     writer can replant a link between the check and the open. We therefore BOUND the
#     threat model to a PRE-PLANTED link (not a live racer); the residual TOCTOU on the
#     read/append paths is recorded in RESUME.md as a known limitation. Do not describe
#     these two helpers as race-safe.

# Atomically REPLACE <dest> with content read from stdin, WITHOUT following a symlink at
# <dest>: write a fresh mktemp in the SAME directory, then rename() it into place. The
# write only ever touches the private temp inode; rename swaps the directory entry, so a
# symlink squatting <dest> is replaced (its target untouched) and there is NO TOCTOU
# window. Returns non-zero if the temp create, the stdin copy, or the rename fails.
fleet_atomic_write() {
  local dest="${1:-}"; [[ -n "$dest" ]] || return 1
  local dir tmp; dir="$(dirname "$dest")"
  mkdir -p "$dir" 2>/dev/null || return 1
  tmp="$(mktemp "$dir/.tmp.XXXXXX" 2>/dev/null)" || return 1
  if cat >"$tmp"; then mv -f "$tmp" "$dest"; else rm -f "$tmp"; return 1; fi
}

# BEST-EFFORT (check-then-open, NOT atomic): true iff <path> is absent or a regular
# file that is not a symlink. Used to REFUSE reads/appends on a PRE-PLANTED symlink;
# it does not defend against a link replanted after this returns. See the note above.
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
