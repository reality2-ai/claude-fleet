#!/usr/bin/env bash
# auto-approve.sh — PreToolUse hook. Auto-allows a curated, NON-DESTRUCTIVE set of
# tool calls so fleet members don't stop for routine "press-enter-for-yes"
# confirmations, while anything destructive or ambiguous still falls through to
# the normal permission prompt. It NEVER auto-denies — worst case it stays silent
# and you decide.
#
# Auto-allowed: read-only tools (Read/Glob/Grep/LS/NotebookRead/TodoWrite/
# WebSearch), edits to files inside the workspace, and read-only shell commands
# (no pipes/redirection/substitution; safe leading command; read-only git).
# Everything else — writes outside the repo, rm/mv/dd, installs, network, sudo,
# git push/reset/commit, runners (make/npm/node…), unknown tools — prompts.
#
# Scope: only acts inside a `.fleet` workspace. Toggles:
#   FLEET_AUTOCONFIRM=off        disable entirely (prompt as normal)
#   FLEET_AUTOCONFIRM_EDITS=off  keep prompting for file edits
set -uo pipefail

[[ "${FLEET_AUTOCONFIRM:-on}" == "off" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat 2>/dev/null || true)"
[[ -n "$payload" ]] || exit 0

meta="$(printf '%s' "$payload" | jq -r '[.tool_name // "", .cwd // ""] | @tsv' 2>/dev/null)" || exit 0
tool="${meta%%$'\t'*}"; cwd="${meta#*$'\t'}"
[[ -n "$tool" ]] || exit 0
[[ -n "$cwd" ]] || cwd="$PWD"

# scope to a fleet workspace, so a user-level install never auto-approves in
# unrelated projects. Cheap walk-up (no external commands).
ws=""; d="$cwd"
while [[ -n "$d" ]]; do
  [[ -d "$d/.fleet" ]] && { ws="$d"; break; }
  [[ "$d" == "/" ]] && break
  d="${d%/*}"; [[ -z "$d" ]] && d="/"
done
[[ -n "$ws" ]] || exit 0

allow() {   # emit the permission decision and stop
  jq -nc --arg r "${1:-fleet auto-approve}" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:("fleet auto-confirm: " + $r)}}'
  exit 0
}
# stay silent (exit 0, no output) → normal prompting
ask() { exit 0; }

# Is a single Bash command read-only enough to auto-allow?
bash_safe() {
  local c="$1"
  # any chaining / redirection / substitution → can't statically vouch for it
  case "$c" in
    *'|'* | *'&'* | *';'* | *'>'* | *'<'* | *'`'* | *'$('* | *$'\n'*) return 1 ;;
  esac
  local first="${c%%[[:space:]]*}"
  case "$first" in
    ls|cat|head|tail|grep|egrep|fgrep|rg|pwd|echo|printf|wc|sort|uniq|cut|tr|nl|tac|\
    column|tree|stat|file|which|type|whoami|id|date|cal|basename|dirname|realpath|\
    readlink|true|false|uname|hostname|uptime|df|du|diff|cmp|md5sum|sha256sum|jq|yq|env|comm)
      return 0 ;;
    find)   # read-only unless it executes or deletes
      case " $c " in *' -exec'* | *' -delete'* | *' -ok'* | *' -fls'* | *' -fprint'*) return 1 ;; esac
      return 0 ;;
    git)    # read-only subcommands only
      local sub; sub="${c#git}"; sub="${sub#"${sub%%[![:space:]]*}"}"; sub="${sub%%[[:space:]]*}"
      case "$sub" in
        status|diff|log|show|ls-files|ls-tree|rev-parse|describe|blame|shortlog|\
        cat-file|for-each-ref|reflog|grep|whatchanged) return 0 ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

case "$tool" in
  Read|Glob|Grep|LS|NotebookRead|TodoWrite|WebSearch)
    allow "read-only tool" ;;
  Edit|Write|MultiEdit|NotebookEdit)
    [[ "${FLEET_AUTOCONFIRM_EDITS:-on}" == "off" ]] && ask
    p="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)"
    [[ -n "$p" ]] || ask
    case "$p" in
      "$ws"/* | "$ws") allow "in-workspace edit" ;;   # absolute, inside workspace
      /*) ask ;;                                        # absolute, outside → prompt
      *)  allow "in-workspace edit (relative to cwd)" ;;
    esac ;;
  Bash)
    c="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)"
    [[ -n "$c" ]] || ask
    if bash_safe "$c"; then allow "read-only shell"; else ask; fi ;;
  *) ask ;;
esac
