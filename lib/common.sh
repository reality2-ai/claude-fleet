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
}

# --- transcript helpers ------------------------------------------------------
# Claude Code stores transcripts at ~/.claude/projects/<encoded-cwd>/<sid>.jsonl
# where <encoded-cwd> is the absolute cwd with every '/' replaced by '-'.
fleet_encode_path() { printf '%s\n' "$1" | sed 's:/:-:g'; }

fleet_projects_dir() { printf '%s\n' "${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"; }

# Path to a session's transcript given its cwd + session id (may not exist).
fleet_transcript_path() {
  local cwd="$1" sid="$2"
  printf '%s/%s/%s.jsonl\n' "$(fleet_projects_dir)" "$(fleet_encode_path "$cwd")" "$sid"
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
