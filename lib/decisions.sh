# shellcheck shell=bash
# decisions.sh — durable human gates and mechanically latched fleet decisions.
#
# A decision has three deliberately separate concepts:
#   * state: open | ratified | revoked | superseded (record lifecycle)
#   * confidence: open | survived | wounded | refuted
#     How well the claim has survived attempts to disprove it.
#   * action: hold | go | done
#     What workers should do now.
#
# Ratification is a latch. `fleet decide` is idempotent for the same answer, but
# it never overwrites a different answer. A changed course requires either an
# authority-recorded revoke or a separately identified successor decision. This
# prevents a new transcript, compaction, or persuasive peer from silently
# reversing the fleet's current instruction.
#
# Storage:
#   $STATE_DIR/decisions/<id>.json
#   $STATE_DIR/decisions/log.jsonl
#   $STATE_DIR/decisions/.counter
#
# Readers normalize the historical status/latch_state and epistemic/operational
# field names, but every new or changed record is rewritten to this smaller v2
# vocabulary. `done` is an operational instruction, never proof of verification.

# --- paths and primitives ----------------------------------------------------
fleet_decisions_dir() { printf '%s\n' "$STATE_DIR/decisions"; }
fleet_decisions_log() { printf '%s\n' "$STATE_DIR/decisions/log.jsonl"; }
fleet_decision_path() { printf '%s/%s.json\n' "$(fleet_decisions_dir)" "$1"; }

_fleet_decision_require_id() {
  [[ "${1:-}" =~ ^d[0-9]+$ ]] || die "invalid decision id '${1:-}' (expected dNNN)"
}

_fleet_decision_read() {
  local id="$1"
  _fleet_decision_require_id "$id"
  fleet_safe_read "$(fleet_decision_path "$id")"
}

_fleet_decision_lock() {
  local dir; dir="$(fleet_decisions_dir)"
  mkdir -p "$dir"
  fleet_safe_lock "$dir/.ledger.lock"
}

# Build a JSON array without asking jq to follow state-file symlinks.
_fleet_decisions_collect() {
  local dir f raw compact first=1
  dir="$(fleet_decisions_dir)"
  shopt -s nullglob
  local -a files=( "$dir"/*.json )
  shopt -u nullglob
  printf '['
  for f in "${files[@]}"; do
    raw="$(fleet_safe_read "$f" 2>/dev/null)" || continue
    compact="$(printf '%s' "$raw" | jq -ce 'select(type=="object")' 2>/dev/null)" || continue
    (( first == 1 )) || printf ','
    printf '%s' "$compact"
    first=0
  done
  printf ']\n'
}

# Allocate d001, d002, ... under a no-follow lock and atomic counter write.
_fleet_decision_next_id() {
  local dir cfile n
  dir="$(fleet_decisions_dir)"; mkdir -p "$dir"
  cfile="$dir/.counter"
  fleet_safe_lock "$dir/.counter.lock" || die "cannot lock the decision counter"
  n="$(fleet_safe_read "$cfile" 2>/dev/null)" || n=0
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  n=$(( n + 1 ))
  if ! printf '%s\n' "$n" | fleet_safe_write "$cfile"; then
    fleet_safe_unlock
    die "cannot persist the decision counter"
  fi
  fleet_safe_unlock
  printf 'd%03d\n' "$n"
}

# Append a provenance event. Record updates remain valid if the audit append is
# unavailable, but the failure is loud rather than silently discarded.
_fleet_decision_logline() {
  local event="$1" id="$2"; shift 2
  local log ts line
  log="$(fleet_decisions_log)"; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$log")"
  local -a kv=( "$@" )
  line="$(jq -nc --arg ts "$ts" --arg event "$event" --arg id "$id" --args '
    {ts:$ts, event:$event, id:$id}
    + (reduce range(0; ($ARGS.positional|length); 2) as $i
         ({}; . + {($ARGS.positional[$i]): $ARGS.positional[$i+1]}))' \
    "${kv[@]}")" || return 1
  printf '%s\n' "$line" | fleet_safe_append "$log" 2>/dev/null || {
    warn "decision '$id' changed, but its audit event could not be appended"
    return 1
  }
}

_fleet_decision_actor() { printf '%s\n' "${FLEET_CHILD_ID:-supervisor}"; }

# --- add ---------------------------------------------------------------------
# fleet decision add "<question>" [--for <agent>] [--scope global|<agent>]
#   [--options "a|b"] [--raised-by <who>] [--authority <who>]
#   [--context <text>] [--evidence <text>] [--falsifier <text>]
#   [--supersedes <id>]
cmd_decision_add() {
  local waiting="" options="" raised_by="" authority="" context="" question=""
  local scope="" evidence="" falsifier="" supersedes="" scope_set=0 authority_set=0
  local due_raw="" due_epoch="" due_iso=""
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --for|--waiting)    waiting="${2:?missing --for value}"; shift 2 ;;
      --scope)            scope="${2:?missing --scope value}"; scope_set=1; shift 2 ;;
      --options|--opts)   options="${2:?missing --options value}"; shift 2 ;;
      --raised-by|--from) raised_by="${2:?missing --raised-by value}"; shift 2 ;;
      --authority)        authority="${2:?missing --authority value}"; authority_set=1; shift 2 ;;
      --context|--task)   context="${2:?missing --context value}"; shift 2 ;;
      --evidence)         evidence="${2:?missing --evidence value}"; shift 2 ;;
      --falsifier)        falsifier="${2:?missing --falsifier value}"; shift 2 ;;
      --supersedes)       supersedes="${2:?missing --supersedes value}"; shift 2 ;;
      --due|--by)         due_raw="${2:?missing --due value}"; shift 2 ;;
      -h|--help) die "usage: fleet decision add \"<question>\" [--for <agent>] [--scope <scope>] [--options \"a|b\"] [--authority <who>] [--supersedes <id>] [--due <when>]" ;;
      *) [[ -z "$question" ]] && question="$1"; shift ;;
    esac
  done
  [[ -n "$question" ]] || die "usage: fleet decision add \"<question>\" [--for <agent>] [--options \"a|b\"]"
  fleet_load_paths
  [[ -z "$raised_by" ]] && raised_by="$(_fleet_decision_actor)"

  # A successor inherits scope and authority unless explicitly overridden.
  local previous=""
  if [[ -n "$supersedes" ]]; then
    _fleet_decision_require_id "$supersedes"
    previous="$(_fleet_decision_read "$supersedes" 2>/dev/null)" \
      || die "no such predecessor decision '$supersedes'"
    (( scope_set == 1 )) || scope="$(printf '%s' "$previous" | jq -r '.scope // .waiting // "global"')"
    (( authority_set == 1 )) || authority="$(printf '%s' "$previous" | jq -r '.authority // "supervisor"')"
  fi
  [[ -n "$scope" ]] || scope="${waiting:-global}"
  [[ -n "$authority" ]] || authority="supervisor"

  # A deadline that did not parse must REFUSE, never default. A --due nobody could read,
  # silently dropped, produces a decision that looks undated and a human who believes it
  # is dated — the failure is discovered by missing the date.
  if [[ -n "$due_raw" ]]; then
    due_epoch="$(fleet_due_parse "$due_raw")" \
      || die "could not read --due '$due_raw' (try '2026-08-08', '2026-08-08 17:00', 'friday', '+2 days')"
    due_iso="$(date -d "@$due_epoch" '+%Y-%m-%d %H:%M %Z')"
  fi

  local id ts epoch dir opts_json record
  id="$(_fleet_decision_next_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; epoch="$(date +%s)"
  dir="$(fleet_decisions_dir)"; mkdir -p "$dir"
  if [[ -n "$options" ]]; then
    opts_json="$(printf '%s' "$options" | jq -Rc 'split("|") | map(select(length>0) | gsub("^\\s+|\\s+$";""))')"
  else
    opts_json='[]'
  fi

  record="$(jq -n --arg id "$id" --arg ts "$ts" --argjson epoch "$epoch" \
      --arg raised_by "$raised_by" --arg waiting "$waiting" --arg scope "$scope" \
      --arg authority "$authority" --arg context "$context" --arg question "$question" \
      --arg evidence "$evidence" --arg falsifier "$falsifier" \
      --arg supersedes "$supersedes" --argjson options "$opts_json" \
      --arg due_iso "$due_iso" --arg due_epoch "$due_epoch" '
    {id:$id, ts:$ts, epoch:$epoch, raised_by:$raised_by,
     waiting:(if $waiting=="" then null else $waiting end),
     scope:$scope, authority:$authority,
     context:(if $context=="" then null else $context end),
     question:$question, options:$options,
     evidence:(if $evidence=="" then null else $evidence end),
     falsifier:(if $falsifier=="" then null else $falsifier end),
     schema:2, state:"open", confidence:"open", action:"hold",
     answer:null, answered_ts:null, ratified_by:null, ratified_ts:null,
     revoked_by:null, revoked_ts:null, revocation_reason:null,
     supersedes:(if $supersedes=="" then null else $supersedes end),
     due:(if $due_iso=="" then null else $due_iso end),
     due_epoch:(if $due_epoch=="" then null else ($due_epoch|tonumber) end),
     superseded_by:null, challenges:[]}' )" || die "failed to build decision record"
  printf '%s\n' "$record" | fleet_safe_write "$(fleet_decision_path "$id")" \
    || die "failed to persist decision '$id'"

  _fleet_decision_logline add "$id" question "$question" raised_by "$raised_by" \
    authority "$authority" scope "$scope" waiting "$waiting" state open || true
  fleet_log decision-add "$id" "raised_by=$raised_by authority=$authority scope=$scope waiting=${waiting:--}"
  info "$id"
}

# --- current-state view ------------------------------------------------------
_fleet_decisions_current_json() {
  local scope="${1:-}" max="${2:-${FLEET_DECISIONS_CURRENT_MAX:-12}}" all
  [[ "$max" =~ ^[0-9]+$ ]] || max=12
  (( max > 0 )) || max=12
  all="$(_fleet_decisions_collect)"
  printf '%s' "$all" | jq --arg scope "$scope" --argjson max "$max" '
    def state: (.state // .latch_state // (if .status=="answered" then "ratified" else (.status // "open") end));
    . as $all
    | [$all[] | select(state=="ratified") | .supersedes // empty] as $replaced
    | [$all[]
       | select((state=="open" or state=="ratified") and ((.id as $id | $replaced | index($id)) == null))
       | select($scope=="" or (.scope // .waiting // "global")=="global"
                or (.scope // "")==$scope or (.waiting // "")==$scope)]
    | sort_by(.epoch // 0) | reverse | .[0:$max] | reverse'
}

_fleet_decisions_current_print() {
  local scope="${1:-}" max="${2:-${FLEET_DECISIONS_CURRENT_MAX:-12}}" json="${3:-0}" current full total shown omitted
  current="$(_fleet_decisions_current_json "$scope" "$max")" || current='[]'
  full="$(_fleet_decisions_current_json "$scope" 1000000)" || full="$current"
  total="$(printf '%s' "$full" | jq -r 'length' 2>/dev/null || echo 0)"
  shown="$(printf '%s' "$current" | jq -r 'length' 2>/dev/null || echo 0)"
  [[ "$total" =~ ^[0-9]+$ ]] || total=0; [[ "$shown" =~ ^[0-9]+$ ]] || shown=0
  omitted=$(( total - shown )); (( omitted < 0 )) && omitted=0
  if [[ "$json" == 1 ]]; then
    printf '%s\n' "$current"
    (( omitted == 0 )) || warn "$omitted active decision(s) omitted by --max $max; absence from this bounded result is not revocation"
    return
  fi
  if [[ "$(printf '%s' "$current" | jq 'length')" == 0 ]]; then
    printf '(no active decision latches or open gates)\n'
    return
  fi
  # `now` is passed in and the remaining time is RECOMPUTED on every print. This
  # function runs on each primer injection, so a lane always reads a fresh figure.
  # Storing "2 days left" would rot exactly like any other unrecomputed number, and
  # an agent has no clock to notice it had (see fleet_now_local, lib/common.sh).
  printf '%s' "$current" | jq -r --argjson now "$(date +%s)" '
    def state: (.state // .latch_state // (if .status=="answered" then "ratified" else (.status // "open") end));
    def dur($s): ($s|fabs|floor) as $a
      | ($a/86400|floor) as $d | (($a%86400)/3600|floor) as $h | (($a%3600)/60|floor) as $m
      | if $d>0 then "\($d)d \($h)h" elif $h>0 then "\($h)h \($m)m" elif $m>0 then "\($m)m" else "\($a)s" end;
    def duetag: if (.due_epoch // null) == null then ""
      else (.due_epoch - $now) as $s
        | if $s < 0 then "\n  ‼ DUE \(.due) — OVERDUE by \(dur($s))"
          else "\n  DUE \(.due) — \(dur($s)) remaining" end
      end;
    .[] | if state=="ratified" then
      "#\(.id) [RATIFIED/\(.action // .operational_state // "go")] scope=\(.scope // .waiting // "global") authority=\(.authority // "supervisor")\(duetag)\n  \(.answer // "")"
    else
      "#\(.id) [OPEN/HOLD] scope=\(.scope // .waiting // "global") authority=\(.authority // "supervisor")\(duetag)\n  \(.question // "")"
    end'
  if (( omitted > 0 )); then
    printf '(WARNING: %s additional active decision(s) omitted by the context bound; absence here is not revocation. Run: fleet decisions --current --max %s)\n' \
      "$omitted" "$total"
  fi
}

# --- list --------------------------------------------------------------------
_fleet_decisions_print() {
  local all="$1" json="$2" records out
  records="$(_fleet_decisions_collect)"
  if [[ "$json" == 1 ]]; then
    printf '%s' "$records" | jq --argjson all "$all" '
      def state: (.state // .latch_state // (if .status=="answered" then "ratified" else (.status // "open") end));
      map(select($all==1 or state=="open")) | sort_by(.epoch // 0)'
    return
  fi
  out="$(printf '%s' "$records" | jq -r --argjson all "$all" '
    def state: (.state // .latch_state // (if .status=="answered" then "ratified" else (.status // "open") end));
    def ago($d):
      if $d < 60 then "\($d)s" elif $d < 3600 then "\($d/60|floor)m"
      elif $d < 86400 then "\($d/3600|floor)h" else "\($d/86400|floor)d" end;
    (now|floor) as $now
    | map(select($all==1 or state=="open")) | sort_by(.epoch // 0)
    | map("#\(.id)  \(ago(($now-(.epoch//$now))|if .<0 then 0 else . end)) ago"
      + " · \(state)" + (if (.waiting//"")!="" then " · waiting: \(.waiting)" else "" end)
      + "\n  " + ((.question//"")|gsub("\n";"\n  "))
      + (if (.options//[]|length)>0 then "\n  options:\n"+(.options|map("    • "+.)|join("\n")) else "" end)
      + (if state!="open" and (.answer//"")!="" then "\n  → \(.answer)" else "" end)
      + (if state=="ratified" then "\n  action: \(.action//.operational_state//"go") · confidence: \(.confidence//.epistemic_state//"survived")" else "" end))
    | join("\n\n")' 2>/dev/null)" || out=""
  if [[ -z "$out" ]]; then
    [[ "$all" == 1 ]] && info "(no decisions recorded yet)" || info "(no open decisions — nothing waiting on you)"
  else
    printf '%s\n' "$out"
  fi
}

_fleet_decisions_watch() {
  local all="$1" current="$2" scope="$3" max="$4"
  local interval="${FLEET_DECISIONS_WATCH_SECS:-5}" limit="${FLEET_DECISIONS_WATCH_ITERS:-0}" i=0
  [[ "$interval" =~ ^[0-9]+$ ]] || interval=5
  while :; do
    clear 2>/dev/null || printf '\033[2J\033[H'
    printf '%s── fleet decisions ── %s ──%s\n' "$c_bold" "$(date -u +%H:%M:%SZ)" "$c_reset"
    if [[ "$current" == 1 ]]; then _fleet_decisions_current_print "$scope" "$max" 0
    else _fleet_decisions_print "$all" 0; fi
    i=$(( i + 1 ))
    [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 && "$i" -ge "$limit" ]] && break
    sleep "$interval"
  done
}

# fleet decisions [--all|--current] [--for <scope>] [--max N] [--json] [--watch]
cmd_decisions() {
  local all=0 json=0 watch=0 current=0 scope="" max="${FLEET_DECISIONS_CURRENT_MAX:-12}"
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --all) all=1; shift ;;
      --current) current=1; shift ;;
      --for|--scope) scope="${2:?missing --for value}"; shift 2 ;;
      --max) max="${2:?missing --max value}"; shift 2 ;;
      --json) json=1; shift ;;
      --watch) watch=1; shift ;;
      -h|--help) die "usage: fleet decisions [--all|--current] [--for <scope>] [--max N] [--json] [--watch]" ;;
      *) die "unknown decisions option '$1'" ;;
    esac
  done
  fleet_load_paths
  if [[ "$watch" == 1 ]]; then _fleet_decisions_watch "$all" "$current" "$scope" "$max"; return; fi
  if [[ "$current" == 1 ]]; then _fleet_decisions_current_print "$scope" "$max" "$json"
  else _fleet_decisions_print "$all" "$json"; fi
}

# --- tmux window -------------------------------------------------------------
fleet_start_decisions_window() {
  [[ "${FLEET_DECISIONS_WINDOW:-off}" == on ]] || return 0
  fleet_has_tmux || return 0
  fleet_tmux_has_window decisions 2>/dev/null && return 0
  fleet_tmux_ensure_session 2>/dev/null || return 0
  local view="decisions --current"; [[ "${FLEET_DECISIONS_WINDOW_ALL:-off}" != off ]] && view="decisions --all"
  fleet_tmux new-window -t "$FLEET_TMUX_SESSION:" -n decisions -c "$WORKSPACE" \
    -e "FLEET_WORKSPACE=$WORKSPACE" -e "TOOL_ROOT=$TOOL_ROOT" \
    -e "FLEET_TMUX_SOCKET=$FLEET_TMUX_SOCKET" -e "FLEET_TMUX_SESSION=$FLEET_TMUX_SESSION" \
    "$TOOL_ROOT/bin/fleet" $view --watch 2>/dev/null || return 0
  fleet_tmux_drop_placeholder
  return 0
}

# --- ratify / challenge / revoke --------------------------------------------
_fleet_decision_route() {
  local to="$1" text="$2" from="${FLEET_CHILD_ID:-supervisor}"
  [[ -n "$to" && "$to" != null && "$to" != "$from" ]] || return 1
  fleet_has_tmux || return 1
  ( _fleet_deliver msg "$to" "$from" "$text" ) || return 1
}

# fleet decide <id> "<answer>" [--action hold|go|done] [--evidence <text>]
cmd_decide() {
  local id="${1:-}" answer="${2:-}" actor op="go" evidence=""
  local due_raw="" due_epoch="" due_iso=""
  [[ -n "$id" && -n "$answer" ]] || die "usage: fleet decide <id> \"<answer>\" [--action hold|go|done] [--due <when>]"
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action|--state) op="${2:?missing --action value}"; shift 2 ;;
      --evidence) evidence="${2:?missing --evidence value}"; shift 2 ;;
      --due|--by) due_raw="${2:?missing --due value}"; shift 2 ;;
      *) die "unknown decide option '$1'" ;;
    esac
  done
  # Same refuse-don't-default contract as `decision add`: an unreadable deadline is
  # an error, never a silent drop.
  if [[ -n "$due_raw" ]]; then
    due_epoch="$(fleet_due_parse "$due_raw")" \
      || die "could not read --due '$due_raw' (try '2026-08-08', '2026-08-08 17:00', 'friday', '+2 days')"
    due_iso="$(date -d "@$due_epoch" '+%Y-%m-%d %H:%M %Z')"
  fi
  [[ "$op" =~ ^(hold|go|done)$ ]] || die "invalid operational action '$op' (use hold, go, or done)"
  _fleet_decision_require_id "$id"
  fleet_load_paths
  actor="$(_fleet_decision_actor)"
  local f raw latch authority old_answer old_op waiting question supersedes ts updated
  f="$(fleet_decision_path "$id")"
  _fleet_decision_lock || die "cannot lock the decision ledger"
  raw="$(fleet_safe_read "$f" 2>/dev/null)" || { fleet_safe_unlock; die "no such decision '$id' (see: fleet decisions --all)"; }
  latch="$(printf '%s' "$raw" | jq -r '.state // .latch_state // (if .status=="answered" then "ratified" else (.status // "open") end)')"
  authority="$(printf '%s' "$raw" | jq -r '.authority // "supervisor"')"
  old_answer="$(printf '%s' "$raw" | jq -r '.answer // ""')"
  old_op="$(printf '%s' "$raw" | jq -r '.action // .operational_state // (if (.state // .latch_state // .status)=="answered" then "go" else "hold" end)')"
  if [[ "$latch" == ratified && "$old_answer" == "$answer" && "$old_op" == "$op" ]]; then
    fleet_safe_unlock
    info "unchanged: #$id already ratified — $answer"
    return 0
  fi
  if [[ "$latch" != open ]]; then
    fleet_safe_unlock
    die "decision '$id' is $latch and latched; use 'fleet decision revoke $id <reason>' or add a --supersedes successor"
  fi
  if [[ "$actor" != "$authority" ]]; then
    fleet_safe_unlock
    die "decision '$id' can be ratified only by authority '$authority' (actor was '$actor')"
  fi
  supersedes="$(printf '%s' "$raw" | jq -r '.supersedes // ""')"
  local predecessor="" predecessor_file="" predecessor_latch="" predecessor_authority="" predecessor_scope="" new_scope=""
  if [[ -n "$supersedes" ]]; then
    predecessor_file="$(fleet_decision_path "$supersedes")"
    predecessor="$(fleet_safe_read "$predecessor_file" 2>/dev/null)" || { fleet_safe_unlock; die "predecessor '$supersedes' is missing"; }
    predecessor_latch="$(printf '%s' "$predecessor" | jq -r '.state // .latch_state // (if .status=="answered" then "ratified" else (.status // "open") end)')"
    predecessor_authority="$(printf '%s' "$predecessor" | jq -r '.authority // "supervisor"')"
    predecessor_scope="$(printf '%s' "$predecessor" | jq -r '.scope // .waiting // "global"')"
    new_scope="$(printf '%s' "$raw" | jq -r '.scope // .waiting // "global"')"
    [[ "$predecessor_latch" == ratified ]] || { fleet_safe_unlock; die "predecessor '$supersedes' is not an active ratified decision"; }
    [[ "$predecessor_authority" == "$authority" && "$predecessor_scope" == "$new_scope" ]] \
      || { fleet_safe_unlock; die "successor must keep predecessor authority and scope"; }
  fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated="$(printf '%s' "$raw" | jq --arg a "$answer" --arg ts "$ts" --arg actor "$actor" --arg op "$op" --arg evidence "$evidence" \
      --arg due_iso "$due_iso" --arg due_epoch "$due_epoch" '
    .schema=2 | .state="ratified" | .answer=$a | .answered_ts=$ts
    | .ratified_ts=$ts | .ratified_by=$actor | .action=$op
    | .confidence="survived"
    | del(.status,.latch_state,.epistemic_state,.operational_state)
    | if $evidence!="" then .evidence=$evidence else . end
    | if $due_iso!="" then (.due=$due_iso | .due_epoch=($due_epoch|tonumber)) else . end')" \
    || { fleet_safe_unlock; die "failed to build ratified decision '$id'"; }
  if ! printf '%s\n' "$updated" | fleet_safe_write "$f"; then
    fleet_safe_unlock; die "failed to record decision '$id'"
  fi
  if [[ -n "$supersedes" ]]; then
    local old_updated
    old_updated="$(printf '%s' "$predecessor" | jq --arg id "$id" --arg ts "$ts" '
      .schema=2 | .state="superseded" | .superseded_by=$id | .superseded_ts=$ts
      | del(.status,.latch_state,.epistemic_state,.operational_state)')"
    if ! printf '%s\n' "$old_updated" | fleet_safe_write "$predecessor_file"; then
      fleet_safe_unlock
      die "successor '$id' was ratified, but predecessor '$supersedes' could not be annotated; current view still suppresses it"
    fi
  fi
  fleet_safe_unlock
  waiting="$(printf '%s' "$raw" | jq -r '.waiting // ""')"
  question="$(printf '%s' "$raw" | jq -r '.question // ""')"
  _fleet_decision_logline ratify "$id" answer "$answer" actor "$actor" action "$op" supersedes "$supersedes" || true
  [[ -n "$supersedes" ]] && _fleet_decision_logline supersede "$supersedes" superseded_by "$id" actor "$actor" || true
  fleet_log decision-ratify "$id" "authority=$actor state=$op waiting=${waiting:--}"
  info "recorded: #$id ratified/$op — $answer"
  if [[ -n "$waiting" && "$waiting" != null ]]; then
    local msg="Decision #$id RATIFIED/$op: ${answer} (Q: ${question}). This is latched; challenges do not reverse it."
    if _fleet_decision_route "$waiting" "$msg"; then
      info "routed the ratified decision to '$waiting'."
    else
      warn "could not route to '$waiting' — the latch is recorded; deliver it manually if needed."
    fi
  else
    info "(no waiting agent recorded — decision stored only.)"
  fi
}

# A challenge changes only epistemic state; the operational latch is untouched.
cmd_decision_challenge() {
  local id="${1:-}" claim="${2:-}" actor evidence=""
  [[ -n "$id" && -n "$claim" ]] || die "usage: fleet decision challenge <id> \"<claim>\" [--evidence <text>]"
  shift 2
  while [[ $# -gt 0 ]]; do case "$1" in
    --evidence) evidence="${2:?missing --evidence value}"; shift 2 ;;
    *) die "unknown challenge option '$1'" ;;
  esac; done
  _fleet_decision_require_id "$id"; fleet_load_paths
  actor="$(_fleet_decision_actor)"
  local f raw ts updated op latch
  f="$(fleet_decision_path "$id")"; _fleet_decision_lock || die "cannot lock the decision ledger"
  raw="$(fleet_safe_read "$f" 2>/dev/null)" || { fleet_safe_unlock; die "no such decision '$id'"; }
  op="$(printf '%s' "$raw" | jq -r '.action // .operational_state // "hold"')"
  latch="$(printf '%s' "$raw" | jq -r '.state // .latch_state // (if .status=="answered" then "ratified" else (.status // "open") end)')"
  if [[ "$latch" != open && "$latch" != ratified ]]; then
    fleet_safe_unlock
    die "decision '$id' is $latch history; challenge its active successor or open a new decision"
  fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated="$(printf '%s' "$raw" | jq --arg ts "$ts" --arg actor "$actor" --arg claim "$claim" --arg evidence "$evidence" --arg state "$latch" --arg action "$op" '
    .schema=2 | .state=$state | .action=$action
    | .challenges=((.challenges // []) + [{ts:$ts,by:$actor,claim:$claim,evidence:(if $evidence=="" then null else $evidence end)}])
    | .confidence="wounded" | del(.status,.latch_state,.epistemic_state,.operational_state)')" || { fleet_safe_unlock; die "failed to build challenge"; }
  if ! printf '%s\n' "$updated" | fleet_safe_write "$f"; then fleet_safe_unlock; die "failed to record challenge"; fi
  fleet_safe_unlock
  _fleet_decision_logline challenge "$id" actor "$actor" claim "$claim" state "$latch" action "$op" || true
  info "challenged: #$id confidence is wounded; operational latch remains $latch/$op"
}

# Only the named authority can invalidate a ratified decision.
cmd_decision_revoke() {
  local id="${1:-}" reason="${2:-}" actor evidence=""
  [[ -n "$id" && -n "$reason" ]] || die "usage: fleet decision revoke <id> \"<reason>\" [--evidence <text>]"
  shift 2
  while [[ $# -gt 0 ]]; do case "$1" in
    --evidence) evidence="${2:?missing --evidence value}"; shift 2 ;;
    *) die "unknown revoke option '$1'" ;;
  esac; done
  _fleet_decision_require_id "$id"; fleet_load_paths
  actor="$(_fleet_decision_actor)"
  local f raw latch authority ts updated
  f="$(fleet_decision_path "$id")"; _fleet_decision_lock || die "cannot lock the decision ledger"
  raw="$(fleet_safe_read "$f" 2>/dev/null)" || { fleet_safe_unlock; die "no such decision '$id'"; }
  latch="$(printf '%s' "$raw" | jq -r '.state // .latch_state // (if .status=="answered" then "ratified" else (.status // "open") end)')"
  authority="$(printf '%s' "$raw" | jq -r '.authority // "supervisor"')"
  [[ "$actor" == "$authority" ]] || { fleet_safe_unlock; die "decision '$id' can be revoked only by authority '$authority' (actor was '$actor')"; }
  [[ "$latch" == ratified ]] || { fleet_safe_unlock; die "decision '$id' is $latch, not ratified"; }
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated="$(printf '%s' "$raw" | jq --arg ts "$ts" --arg actor "$actor" --arg reason "$reason" --arg evidence "$evidence" '
    .schema=2 | .state="revoked" | .action="hold"
    | .confidence="refuted" | .revoked_ts=$ts | .revoked_by=$actor
    | .revocation_reason=$reason
    | del(.status,.latch_state,.epistemic_state,.operational_state)
    | if $evidence!="" then .revocation_evidence=$evidence else . end')" \
    || { fleet_safe_unlock; die "failed to build revocation"; }
  if ! printf '%s\n' "$updated" | fleet_safe_write "$f"; then fleet_safe_unlock; die "failed to revoke '$id'"; fi
  fleet_safe_unlock
  _fleet_decision_logline revoke "$id" actor "$actor" reason "$reason" || true
  fleet_log decision-revoke "$id" "authority=$actor reason=$reason"
  info "revoked: #$id is now refuted/hold — $reason"
}
