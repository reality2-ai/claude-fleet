# shellcheck shell=bash
# decisions.sh — the fleet decision-ledger: a durable, queryable, answerable
# home for decisions that are waiting on the human (the principal).
#
# Motivation: gates the fleet raises for the human otherwise live only in the
# supervisor's scrollback and get lost on scroll/compaction/reboot. This module
# persists them as provenance-bearing records so they survive, can be listed at
# any time, and — when answered — route the answer back to the blocked agent so
# it unblocks. It is also the first concrete slice of the fleet's knowledge
# layer: every decision is a record with an id, a timestamp, who raised it, who
# is waiting on it, and an append-only change log.
#
# Storage layout (durable, under the workspace state dir):
#   $STATE_DIR/decisions/<id>.json   one record per decision
#   $STATE_DIR/decisions/log.jsonl   append-only provenance of every state change
#   $STATE_DIR/decisions/.counter    monotonic id counter (→ d001, d002, …)
#
# Record shape:
#   { id, ts, epoch, raised_by, waiting, context, question, options[],
#     status: "open"|"answered", answer, answered_ts }
#
# Sourced by bin/fleet. Not meant to be executed directly. Additive: this module
# only reads/writes under $STATE_DIR/decisions and reuses the existing send path
# (_fleet_deliver) for answer-routing; it does not modify the bus or registry.

# --- paths -------------------------------------------------------------------
fleet_decisions_dir() { printf '%s\n' "$STATE_DIR/decisions"; }
fleet_decisions_log() { printf '%s\n' "$STATE_DIR/decisions/log.jsonl"; }

# Allocate the next short, sortable id (d001, d002, …). Uses a counter file with
# an flock guard so two concurrent adds can't collide. Date.now/$RANDOM may be
# constrained in some agent contexts, so we derive from a persistent counter.
_fleet_decision_next_id() {
  local dir cfile n
  dir="$(fleet_decisions_dir)"; mkdir -p "$dir"
  cfile="$dir/.counter"
  exec 9>"$dir/.counter.lock"
  flock 9 2>/dev/null || true
  n=0; [[ -f "$cfile" ]] && n="$(cat "$cfile" 2>/dev/null || echo 0)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  n=$(( n + 1 ))
  printf '%s\n' "$n" >"$cfile"
  exec 9>&-
  printf 'd%03d\n' "$n"
}

fleet_decision_path() { printf '%s/%s.json\n' "$(fleet_decisions_dir)" "$1"; }

# Append a provenance event to log.jsonl. _fleet_decision_logline <event> <id> [k v ...]
_fleet_decision_logline() {
  local event="$1" id="$2"; shift 2
  local log ts; log="$(fleet_decisions_log)"; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$log")"
  # remaining args are alternating key value pairs merged into the event object
  local -a kv=( "$@" )
  jq -nc --arg ts "$ts" --arg event "$event" --arg id "$id" --args \
    '{ts:$ts, event:$event, id:$id}
     + (reduce range(0; ($ARGS.positional|length); 2) as $i
          ({}; . + {($ARGS.positional[$i]): $ARGS.positional[$i+1]}))' \
    "${kv[@]}" >>"$log" 2>/dev/null || true
}

# --- add ---------------------------------------------------------------------
# fleet decision add "<question>" [--for <agent>] [--options "a|b|c"]
#                    [--raised-by <who>] [--context "<text>"]
cmd_decision_add() {
  local waiting="" options="" raised_by="" context="" question=""
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --for|--waiting)      waiting="${2:?usage: fleet decision add \"<question>\" [--for <agent>] [--options \"a|b|c\"] [--raised-by <who>] [--context <text>]}"; shift 2 ;;
      --options|--opts)     options="${2:?missing --options value}"; shift 2 ;;
      --raised-by|--from)   raised_by="${2:?missing --raised-by value}"; shift 2 ;;
      --context|--task)     context="${2:?missing --context value}"; shift 2 ;;
      -h|--help)            die "usage: fleet decision add \"<question>\" [--for <agent>] [--options \"a|b|c\"] [--raised-by <who>] [--context <text>]" ;;
      *)                    [[ -z "$question" ]] && question="$1"; shift ;;
    esac
  done
  [[ -n "$question" ]] || die "usage: fleet decision add \"<question>\" [--for <agent>] [--options \"a|b|c\"] [--raised-by <who>] [--context <text>]"
  fleet_load_paths
  [[ -z "$raised_by" ]] && raised_by="${FLEET_CHILD_ID:-supervisor}"

  local id ts epoch dir opts_json
  id="$(_fleet_decision_next_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; epoch="$(date +%s)"
  dir="$(fleet_decisions_dir)"; mkdir -p "$dir"
  # split "a|b|c" into a JSON array (empty → [])
  if [[ -n "$options" ]]; then
    opts_json="$(printf '%s' "$options" | jq -Rc 'split("|") | map(select(length>0) | gsub("^\\s+|\\s+$";""))')"
  else
    opts_json='[]'
  fi

  jq -n --arg id "$id" --arg ts "$ts" --argjson epoch "$epoch" \
        --arg raised_by "$raised_by" --arg waiting "$waiting" \
        --arg context "$context" --arg question "$question" \
        --argjson options "$opts_json" '
    { id: $id, ts: $ts, epoch: $epoch,
      raised_by: $raised_by,
      waiting: (if $waiting=="" then null else $waiting end),
      context: (if $context=="" then null else $context end),
      question: $question, options: $options,
      status: "open", answer: null, answered_ts: null }' >"$(fleet_decision_path "$id")"

  _fleet_decision_logline add "$id" question "$question" raised_by "$raised_by" \
    waiting "$waiting" status open
  fleet_log decision-add "$id" "raised_by=$raised_by waiting=${waiting:--}"
  info "$id"
}

# --- list --------------------------------------------------------------------
# Print the human-readable list. $1=all(0|1) $2=json(0|1). Formats fully in jq
# (age from `now`) so empty fields can't misalign — a tab-`read` in bash would
# collapse empty columns since tab is IFS-whitespace.
_fleet_decisions_print() {
  local all="$1" json="$2" dir; dir="$(fleet_decisions_dir)"
  shopt -s nullglob; local -a files=( "$dir"/*.json ); shopt -u nullglob
  if [[ "$json" == "1" ]]; then
    if [[ ${#files[@]} -eq 0 ]]; then printf '[]\n'; return; fi
    jq -s --argjson all "$all" \
      'map(select($all==1 or .status=="open")) | sort_by(.epoch)' "${files[@]}" 2>/dev/null || printf '[]\n'
    return
  fi
  if [[ ${#files[@]} -eq 0 ]]; then
    [[ "$all" == "1" ]] && info "(no decisions recorded yet)" || info "(no open decisions — nothing waiting on you)"
    return
  fi
  local out
  out="$(jq -rs --argjson all "$all" --arg grn "$c_grn" --arg rst "$c_reset" '
    def ago($d):
      if   $d < 60    then "\($d)s"
      elif $d < 3600  then "\($d/60|floor)m"
      elif $d < 86400 then "\($d/3600|floor)h"
      else                 "\($d/86400|floor)d" end;
    (now|floor) as $now
    | map(select($all==1 or .status=="open"))
    | sort_by(.epoch)
    | .[]
    | ("#\(.id) · \(ago(($now - (.epoch // $now))|if . < 0 then 0 else . end)) · "
       + (if (.waiting // "") != "" then "[waiting: \(.waiting)] · " else "" end)
       + .question
       + (if (.options // [] | length) > 0 then "  (\(.options|join("/")))" else "" end)
       + (if .status == "answered" then "  \($grn)→ \(.answer // "")\($rst)" else "" end))
  ' "${files[@]}" 2>/dev/null || true)"
  if [[ -z "$out" ]]; then
    [[ "$all" == "1" ]] && info "(no decisions recorded yet)" || info "(no open decisions — nothing waiting on you)"
    return
  fi
  printf '%s\n' "$out"
}

# Self-refreshing view for a tmux pane. $1=all(0|1).
_fleet_decisions_watch() {
  local all="$1" interval="${FLEET_DECISIONS_WATCH_SECS:-5}"
  [[ "$interval" =~ ^[0-9]+$ ]] || interval=5
  # allow a bounded run for testing (FLEET_DECISIONS_WATCH_ITERS>0), else forever
  local max="${FLEET_DECISIONS_WATCH_ITERS:-0}" i=0
  while :; do
    clear 2>/dev/null || printf '\033[2J\033[H'
    printf '%s── fleet decisions ── %s ──%s\n' "$c_bold" "$(date -u +%H:%M:%SZ)" "$c_reset"
    _fleet_decisions_print "$all" 0
    i=$(( i + 1 ))
    [[ "$max" =~ ^[0-9]+$ && "$max" -gt 0 && "$i" -ge "$max" ]] && break
    sleep "$interval"
  done
}

# fleet decisions [--all] [--json] [--watch]
cmd_decisions() {
  local all=0 json=0 watch=0
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --all)      all=1; shift ;;
      --json)     json=1; shift ;;
      --watch)    watch=1; shift ;;
      -h|--help)  die "usage: fleet decisions [--all] [--json] [--watch]" ;;
      *)          break ;;
    esac
  done
  fleet_load_paths
  if [[ "$watch" == "1" ]]; then _fleet_decisions_watch "$all"; return; fi
  _fleet_decisions_print "$all" "$json"
}

# --- tmux window -------------------------------------------------------------
# Spawn a persistent `decisions` window running `fleet decisions --watch`, so the
# open gate list is always visible in a pane. Gated behind FLEET_DECISIONS_WINDOW
# (default on) and written to be non-fatal: every failure path returns 0 so it can
# never break `fleet up`. Requires tmux; no-ops without it.
fleet_start_decisions_window() {
  [[ "${FLEET_DECISIONS_WINDOW:-on}" != "off" ]] || return 0
  fleet_has_tmux || return 0
  fleet_tmux_has_window decisions 2>/dev/null && return 0
  fleet_tmux_ensure_session 2>/dev/null || return 0
  local view="decisions"; [[ "${FLEET_DECISIONS_WINDOW_ALL:-off}" != "off" ]] && view="decisions --all"
  # shellcheck disable=SC2086
  fleet_tmux new-window -t "$FLEET_TMUX_SESSION" -n decisions -c "$WORKSPACE" \
    -e "FLEET_WORKSPACE=$WORKSPACE" -e "TOOL_ROOT=$TOOL_ROOT" \
    -e "FLEET_TMUX_SOCKET=$FLEET_TMUX_SOCKET" -e "FLEET_TMUX_SESSION=$FLEET_TMUX_SESSION" \
    "$TOOL_ROOT/bin/fleet" $view --watch 2>/dev/null || return 0
  return 0
}

# --- decide ------------------------------------------------------------------
# Route an answer back to the waiting agent via the existing send path. Wrapped
# in a subshell so a `die` inside _fleet_deliver (hop limit, self-send) can never
# abort `fleet decide`. Returns 0 if delivered/queued, 1 otherwise.
_fleet_decision_route() {
  local to="$1" text="$2" from="${FLEET_CHILD_ID:-supervisor}"
  [[ -n "$to" && "$to" != "null" ]] || return 1
  [[ "$to" != "$from" ]] || return 1
  fleet_has_tmux || return 1
  ( _fleet_deliver msg "$to" "$from" "$text" ) || return 1
  return 0
}

# fleet decide <id> "<answer>"
cmd_decide() {
  local id="${1:-}" answer="${2:-}"
  [[ -n "$id" && -n "$answer" ]] || die "usage: fleet decide <id> \"<answer>\""
  fleet_load_paths
  local f; f="$(fleet_decision_path "$id")"
  [[ -f "$f" ]] || die "no such decision '$id' (see: fleet decisions --all)"

  local status waiting question
  status="$(jq -r '.status // "open"' "$f" 2>/dev/null)"
  waiting="$(jq -r '.waiting // ""' "$f" 2>/dev/null)"
  question="$(jq -r '.question // ""' "$f" 2>/dev/null)"
  [[ "$status" == "answered" ]] && warn "decision '$id' was already answered — recording the new answer"

  local ts tmp; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; tmp="$f.tmp.$$"
  if jq --arg a "$answer" --arg ts "$ts" \
      '.status="answered" | .answer=$a | .answered_ts=$ts' "$f" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"; die "failed to record answer for '$id'"
  fi
  _fleet_decision_logline answer "$id" answer "$answer" waiting "$waiting" status answered
  fleet_log decision-answer "$id" "waiting=${waiting:--}"

  info "recorded: #$id answered — $answer"
  if [[ -n "$waiting" && "$waiting" != "null" ]]; then
    local msg="Decision #$id answered: ${answer}  (Q: ${question})"
    if _fleet_decision_route "$waiting" "$msg"; then
      info "routed the answer to '$waiting' so it can unblock."
    else
      warn "could not route to '$waiting' (no tmux / self / offline) — answer is recorded; deliver it manually if needed."
    fi
  else
    info "(no waiting agent recorded — answer stored only.)"
  fi
}
