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

meta="$(printf '%s' "$payload" | jq -r '[.tool_name // .tool // .tool.name // "", .cwd // .working_directory // ""] | @tsv' 2>/dev/null)" || exit 0
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
  local event="${FLEET_HOOK_EVENT:-}"
  [[ -n "$event" ]] || event="$(printf '%s' "$payload" | jq -r '.hook_event_name // .event_name // "PreToolUse"' 2>/dev/null)"
  jq -nc --arg r "${1:-fleet auto-approve}" \
    --arg e "$event" \
    '{hookSpecificOutput:{hookEventName:$e,permissionDecision:"allow",permissionDecisionReason:("fleet auto-confirm: " + $r)}}'
  exit 0
}
# stay silent (exit 0, no output) → normal prompting
ask() { exit 0; }

# Is a SINGLE simple command (no pipes/chaining) read-only enough to auto-allow?
cmd_safe() {
  local c="$1"
  c="${c#"${c%%[![:space:]]*}"}"          # ltrim
  [[ -n "$c" ]] || return 1
  local first="${c%%[[:space:]]*}"
  local base="${first##*/}"               # basename, so /usr/bin/git → git, claude-fleet/bin/fleet → fleet
  local _ sub act
  case "$base" in
    cd|ls|cat|head|tail|grep|egrep|fgrep|rg|pwd|echo|printf|wc|sort|uniq|cut|tr|nl|tac|\
    column|tree|stat|file|which|type|whoami|id|date|cal|basename|dirname|realpath|\
    readlink|true|false|uname|hostname|uptime|df|du|diff|cmp|md5sum|sha256sum|jq|yq|comm)
      return 0 ;;   # NB: 'env' deliberately excluded — `env VAR=v cmd` can exec
    find)   # read-only unless it executes or deletes
      case " $c " in *' -exec'* | *' -delete'* | *' -ok'* | *' -fls'* | *' -fprint'*) return 1 ;; esac
      return 0 ;;
    git)
      read -r _ sub _ <<<"$c"
      case "$sub" in
        # read-only
        status|diff|log|show|ls-files|ls-tree|ls-remote|rev-parse|describe|blame|\
        shortlog|cat-file|for-each-ref|reflog|grep|whatchanged|fetch) return 0 ;;
        # recoverable / checkpoint-creating (the GitHub-failsafe mechanism) — but NOT
        # push: pushing is outward and can irreversibly leak to a public repo, so it
        # stays a prompt (the one human glance that guards "share code, not secret").
        commit) return 0 ;;
        add)    # named staging only — reject bulk/force (secret-staging footgun)
          case " $c " in *' -A'* | *' --all'* | *' -f'* | *' --force'*) return 1 ;; esac
          case "$c" in *' .' | *' . '* | *' :/'* | *' :/') return 1 ;; esac
          return 0 ;;
        switch) # branch switch / create-branch — non-destructive (git refuses to clobber
                # uncommitted work); reject force-create / discard variants
          case " $c " in *' -C '* | *' --force-create'* | *' -f '* | *' --force'* | *' --discard-changes'*) return 1 ;; esac
          return 0 ;;
        checkout) # ONLY the non-destructive create-branch form (-b); bare `checkout <path>`
                  # / `checkout .` / `checkout -- file` can DISCARD uncommitted work → prompt
          case " $c " in *' -b '*) ;; *) return 1 ;; esac
          case " $c " in *' -B '* | *' -f '* | *' --force'*) return 1 ;; esac
          return 0 ;;
        branch|tag)   # list/show only — reject delete/rename/force
          case " $c " in *' -d'* | *' -D'* | *' -m'* | *' -M'* | *' --delete'* | *' --move'* | *' -f'* | *' --force'*) return 1 ;; esac
          return 0 ;;
        remote) # show/get-url only — reject add/remove/rename/set-url/prune
          case " $c " in *' add '* | *' remove '* | *' rm '* | *' rename '* | *' set-url'* | *' set-head'* | *' prune'*) return 1 ;; esac
          return 0 ;;
        push)  # checkpoint push under the GitHub failsafe (Roy-directed). Reject force/delete/mirror.
          case " $c " in *' --force'* | *' -f '* | *' --mirror'* | *' --delete'* | *' --prune'* | *' :'*) return 1 ;; esac
          return 0 ;;
        *) return 1 ;;  # reset/rebase/merge/pull/checkout/restore/clean/stash/cherry-pick … prompt
      esac ;;
    gh)     # read-only subcommands / GET-only api
      read -r _ sub act _ <<<"$c"
      case "$sub" in
        api)  # reject anything that sends a body or non-GET method
          case " $c " in
            *' -X'* | *' --method'* | *' -f '* | *' -F '* | *' --field'* | *' --raw-field'* | *' --input'*) return 1 ;;
            *) return 0 ;;
          esac ;;
        auth)   [[ "$act" == status ]] ;;
        pr|issue|run|release|repo|workflow|search|cache|gist|label)
          case "$act" in view|list|status|diff|checks|ls) return 0 ;; *) return 1 ;; esac ;;
        *) return 1 ;;
      esac ;;
    fleet)  # read-only introspection + inter-agent messaging (Roy-approved: low-risk,
            # internal, hop-capped). NOT ask (forks+cost) / up/down/restart/dispatch (lifecycle).
      read -r _ sub _ <<<"$c"
      case "$sub" in
        status|brief|logs|log|inbox|conflicts|list|ls|tree|who|help|--help|-h|\
        send|broadcast) return 0 ;;
        *) return 1 ;;
      esac ;;
    # Build/test runners — auto-approved UNDER the GitHub failsafe (work is recoverable).
    # Scoped to build/check/test verbs only; run/install/publish/add/update (arbitrary exec,
    # deps, supply-chain) still prompt.
    cargo)
      read -r _ sub _ <<<"$c"
      case "$sub" in
        check|build|test|clippy|fmt|doc|nextest|bench|tree|metadata|version|--version|-V) return 0 ;;
        *) return 1 ;;   # run / install / publish / add / remove / update → prompt
      esac ;;
    npm|pnpm|yarn|bun)
      read -r _ sub act _ <<<"$c"
      case "$sub" in
        test) return 0 ;;
        run)  case "$act" in test|build|lint|typecheck|check|fmt|format|tsc|types|ci|coverage) return 0 ;; *) return 1 ;; esac ;;
        *) return 1 ;;   # install / ci / add / publish / exec / x / dlx / create → prompt
      esac ;;
    tsc) return 0 ;;
    *) return 1 ;;
  esac
}

# One '&&'-free command, possibly a PIPELINE: every `|` segment must be read-only-safe.
pipe_safe() {
  local c="$1"
  local -a segs=()
  IFS='|' read -ra segs <<<"$c"           # split on pipe only; no globbing
  [[ ${#segs[@]} -gt 0 ]] || return 1
  local s
  for s in "${segs[@]}"; do
    s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"   # trim both ends
    [[ -n "$s" ]] || return 1             # empty segment ⇒ '||' / leading|trailing pipe ⇒ reject
    cmd_safe "$s" || return 1
  done
  return 0
}

# Whole Bash command: auto-allow read-only/checkpoint commands, pipelines, and
# '&&' chains where EVERY part is itself auto-approvable (so `cd repo && git add x
# && git commit && git push` flows). Reject redirection, command substitution, a
# lone '&' (background / &> / |&), ';' sequencing, here-docs/newlines.
bash_safe() {
  local c="$1"
  c="${c#"${c%%[![:space:]]*}"}"          # ltrim
  case "$c" in
    *'>'* | *'<'* | *'`'* | *'$('* | *$'\n'*) return 1 ;;
  esac
  case "${c//&&/}" in *'&'*) return 1 ;; esac   # allow '&&'/';' chaining but reject a lone '&'
  # treat '&&' and ';' alike: every command in the sequence must be auto-approvable
  local rest="${c//&&/;}" part done=0
  while [[ $done -eq 0 ]]; do
    case "$rest" in
      *';'*) part="${rest%%;*}"; rest="${rest#*;}" ;;
      *)     part="$rest"; done=1 ;;
    esac
    part="${part#"${part%%[![:space:]]*}"}"; part="${part%"${part##*[![:space:]]}"}"   # trim
    [[ -n "$part" ]] || continue          # skip empty parts (trailing / doubled separators)
    pipe_safe "$part" || return 1
  done
  return 0
}

# --- Net 2: auto-checkpoint before a recoverable-but-tree-changing git op ------
# Snapshot current WIP WITHOUT touching the working tree, so reset/checkout/restore/
# merge/pull can auto-approve AND be unwound (recovery: git stash apply <ref-sha>).
do_checkpoint() {
  local s ref
  s="$(git -C "$cwd" stash create "fleet auto-checkpoint" 2>/dev/null)" || return 0
  [[ -n "$s" ]] || return 0                          # clean tree → nothing to save
  ref="refs/auto-checkpoint/$(date +%Y%m%d-%H%M%S)-$$"
  git -C "$cwd" update-ref "$ref" "$s" 2>/dev/null || return 0
  # keep only the 20 most recent checkpoints (bounded ref growth)
  git -C "$cwd" for-each-ref --sort=-refname --format='%(refname)' refs/auto-checkpoint/ 2>/dev/null \
    | tail -n +21 | while read -r r; do git -C "$cwd" update-ref -d "$r" 2>/dev/null; done
}

# A SINGLE git op that's safe to auto-approve once a checkpoint is taken first.
checkpointable_git() {
  local c="$1"
  case "$c" in *'|'* | *'&'* | *';'* | *'>'* | *'<'* | *'`'* | *'$('* | *$'\n'*) return 1 ;; esac
  c="${c#"${c%%[![:space:]]*}"}"
  local first="${c%%[[:space:]]*}"; [[ "${first##*/}" == git ]] || return 1
  local _ sub; read -r _ sub _ <<<"$c"
  case "$sub" in
    reset|checkout|restore|merge|pull)
      case " $c " in *' -b '*) return 1 ;; esac      # branch-create handled by cmd_safe
      return 0 ;;
    *) return 1 ;;
  esac
}

case "$tool" in
  Read|Glob|Grep|LS|NotebookRead|TodoWrite|WebSearch)
    allow "read-only tool" ;;
  Edit|Write|MultiEdit|NotebookEdit)
    [[ "${FLEET_AUTOCONFIRM_EDITS:-on}" == "off" ]] && ask
    p="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // .input.file_path // .input.path // .params.file_path // .params.path // ""' 2>/dev/null)"
    [[ -n "$p" ]] || ask
    case "$p" in
      "$ws"/* | "$ws") allow "in-workspace edit" ;;   # absolute, inside workspace
      /*) ask ;;                                        # absolute, outside → prompt
      *)  allow "in-workspace edit (relative to cwd)" ;;
    esac ;;
  Bash)
    c="$(printf '%s' "$payload" | jq -r '.tool_input.command // .input.command // .params.command // .command // ""' 2>/dev/null)"
    [[ -n "$c" ]] || ask
    if bash_safe "$c"; then allow "read-only shell"
    elif checkpointable_git "$c"; then do_checkpoint; allow "auto-checkpointed git op (recover: refs/auto-checkpoint/*)"
    else ask; fi ;;
  mcp__*)
    # Read-only MCP (get/list/search/read/view/fetch/find/query) auto-approves; anything whose
    # name implies a write/side-effect (create/update/delete/send/post/…) still prompts. The
    # write check runs FIRST so e.g. get_or_create → prompt. Case-insensitive.
    shopt -s nocasematch
    case "$tool" in
      *create*|*update*|*delete*|*remove*|*_set*|*_add*|*post*|*patch*|*write*|*send*|*edit*|\
      *move*|*archive*|*transition*|*complete*|*draft*|*assign*|*cancel*|*upload*|*label*|*revoke*) ask ;;
      *get*|*list*|*search*|*read*|*view*|*fetch*|*find*|*query*|*describe*|*info*|*status*|*available*|*recordings*) allow "read-only MCP" ;;
      *) ask ;;
    esac ;;
  *) ask ;;
esac
