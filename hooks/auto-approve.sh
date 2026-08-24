#!/usr/bin/env bash
# auto-approve.sh — PreToolUse hook. Auto-allows a curated, NON-DESTRUCTIVE set of
# tool calls so fleet members don't stop for routine "press-enter-for-yes"
# confirmations, while anything destructive or ambiguous still falls through to
# the normal permission prompt. It auto-denies ONE class — firmware-flash /
# firmware-sign / key-mint / trust-material-artifact ops (probe A9) — because under
# --dangerously-skip-permissions a silent fall-through would RUN them; everything else
# it either allows or stays silent on and you decide.
#
# Auto-allowed: read-only tools (Read/Glob/Grep/LS/NotebookRead/TodoWrite/
# WebSearch), edits to files inside the workspace, safe shell commands, named
# git staging/commit/non-force push, and scoped build/test runners.
# Everything else — writes outside the repo, rm/mv/dd, installs, arbitrary
# network, sudo, force-push/reset/rebase/pull, unknown runners/tools — prompts.
#
# Scope: only acts inside a `.fleet` workspace. Toggles:
#   FLEET_AUTOCONFIRM=off        disable entirely (prompt as normal)
#   FLEET_AUTOCONFIRM_EDITS=off  keep prompting for file edits
#   FLEET_FIRMWARE_GATE=off      disable the firmware/key/OTA escalation (deny) gate
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

deny() {   # HARD deny → blocks even --dangerously-skip-permissions; escalates to a human
  local event="${FLEET_HOOK_EVENT:-}"
  [[ -n "$event" ]] || event="$(printf '%s' "$payload" | jq -r '.hook_event_name // .event_name // "PreToolUse"' 2>/dev/null)"
  jq -nc --arg r "${1:-high-sensitivity op}" \
    --arg e "$event" \
    '{hookSpecificOutput:{hookEventName:$e,permissionDecision:"deny",permissionDecisionReason:("fleet firmware/key gate — escalate to a human: " + $r)}}'
  exit 0
}

# Is a SINGLE simple command (no pipes/chaining) read-only enough to auto-allow?
cmd_safe() {
  local c="$1"
  c="${c#"${c%%[![:space:]]*}"}"          # ltrim
  [[ -n "$c" ]] || return 1
  local first="${c%%[[:space:]]*}"
  local base="${first##*/}"               # basename, so /usr/bin/git → git, claude-fleet/bin/fleet → fleet
  local _ sub act
  case "$base" in
    cd|ls|cat|head|tail|grep|egrep|fgrep|pwd|echo|printf|wc|uniq|cut|tr|nl|tac|\
    column|tree|stat|file|which|type|whoami|id|date|cal|basename|dirname|realpath|\
    readlink|true|false|uname|hostname|uptime|df|du|diff|cmp|md5sum|sha256sum|jq|comm)
      return 0 ;;   # NB: 'env' deliberately excluded — `env VAR=v cmd` can exec
    sort)   # read-only EXCEPT -o/--output (writes any file) + --compress-program (execs a helper)
      case " $c " in *' -o'* | *' --output'* | *' --compress-program'*) return 1 ;; esac
      return 0 ;;
    rg)     # ripgrep is read-only EXCEPT flags that execute an external program
      case " $c " in *' --pre'* | *' --hostname-bin'* | *' --search-zip'* | *' -z'*) return 1 ;; esac
      return 0 ;;
    yq)     # writes to stdout by default; -i / --inplace rewrites a file in place
      case " $c " in *' -i'* | *' --inplace'* | *' --in-place'*) return 1 ;; esac
      return 0 ;;
    find)   # read-only unless it executes or deletes
      case " $c " in *' -exec'* | *' -delete'* | *' -ok'* | *' -fls'* | *' -fprint'*) return 1 ;; esac
      return 0 ;;
    git)
      read -r _ sub _ <<<"$c"
      case "$sub" in
        # read-only
        status|diff|log|show|ls-files|ls-tree|ls-remote|rev-parse|describe|blame|\
        shortlog|cat-file|for-each-ref|reflog|grep|whatchanged|fetch) return 0 ;;
        # recoverable / checkpoint-creating (the GitHub-failsafe mechanism);
        # non-force push is guarded by the fleet pre-push secret scan.
        commit) return 0 ;;
        add)    # named staging only — reject bulk/force (secret-staging footgun)
          case " $c " in *' -A'* | *' --all'* | *' -f'* | *' --force'*) return 1 ;; esac
          case "$c" in *' .' | *' . '* | *' :/'*) return 1 ;; esac   # ' :/'* already covers a trailing ' :/'
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
# '&&'/';' chains where EVERY part is itself auto-approvable (so `cd repo && git add
# x && git commit && git push` flows). Reject redirection, command substitution, a
# lone '&' (background / &> / |&), here-docs/newlines.
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

# --- Firmware/key/OTA high-sensitivity gate (probe A9) ------------------------
# Flashing, firmware signing, key generation/minting, and writes to KEY/SIGNATURE
# artifacts are high-stakes + often irreversible. Source edits (.rs/.toml/.md) under
# keystore/provision dirs are NOT gated — only the dangerous OPERATIONS + trust-material
# artifacts — so #20/#17 source dev stays fast while flash/sign/mint require a human go.
# Command-wrappers that pass through to another program (`env espflash …`,
# `timeout 60 espflash …`, `sudo openssl genpkey …`). The gate must look THROUGH
# these, or a wrapper defeats the basename match and the op runs silently.
# A bare shell assignment prefix is a wrapper too: in `VAR=value espflash …` the
# ASSIGNMENT is the first token, so the look-through never fires and the real program is
# invisible to the gate — no check, no USED line. This has fired (g19).
#
# It MUST be tested against the RAW token, never the basename: `${first##*/}` reduces
# `R2_OTA_TARGET=/dev/serial/by-id/…` to the path tail, so an assignment whose value is a
# PATH stops looking like an assignment — and a device path is exactly the real bypass
# shape. Testing the basename fixes `FOO=bar` and misses the case that actually occurred.
#
# Fail-safe direction: matching here can only cause MORE segments to be scanned for a
# flasher, never fewer. A false positive costs a prompt; the false negative is the hole.
_hs_is_assign() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]
}

# A shell invoked in NOEXEC mode parses its input and runs NOTHING. `bash -n file.sh`
# is a syntax check, not an execution, so the file's contents must not be classified.
#
# FOUND BY THE FIX FIRING ON ITS AUTHOR, minutes after it landed: the new script-file
# look-through read `hooks/auto-approve.sh` during a routine `bash -n` syntax check,
# found flasher names in the source, and denied. That is precisely the false-positive
# shape that produced the wrapper era — a gate blocking a harmless op teaches the
# operator to route around it — so it is closed HERE rather than worked around.
_hs_is_noexec() {
  local seg="$1" base t
  base="$(_hs_detok "${seg%%[[:space:]]*}")"
  case "$base" in sh|bash|dash|zsh|ksh) : ;; *) return 1 ;; esac
  for t in $seg; do
    case "$(_hs_detok "$t")" in -n|--noexec|-vn|-nv) return 0 ;; esac
  done
  return 1
}

# Strip shell quoting/escaping from a SINGLE TOKEN so a basename comparison sees the
# real program name. TOKEN-level only — never applied to a segment.
#
# WHY NOT AT SEGMENT LEVEL: _hs_segments preserves quote characters as DATA on purpose,
# because prose-quoting-prose is the common case here (a fleet message whose text
# contains `"… ; write-persona …"` must not be split on that ';'). Stripping quotes
# earlier would reopen that. So the strip happens exactly where a name is compared.
#
# MEASURED DEFECT THIS CLOSES (2026-07-28 probe, route 7 verification): `${first##*/}`
# on `"espflash"` yields the literal token `"espflash"` — quote included — which matches
# no case arm and no wrapper arm, so the gate NEVER FIRED. `"espflash" flash --port …`,
# `'espflash' …`, `\espflash …` and `esp''flash …` were all silent. ONE KEYSTROKE
# defeated both the flash gate and the key-mint gate, with no wrapper file involved.
_hs_detok() {
  local t="$1" out='' i=0 n ch
  n=${#t}
  while (( i < n )); do
    ch="${t:i:1}"
    # shellcheck disable=SC1003  # '\' is a case PATTERN matching one literal backslash,
    # not a botched attempt to escape a quote. The house convention for this exact
    # false positive is a per-line disable with a reason (see .github/workflows/ci.yml).
    # Do not "fix" it to \\ without re-running tests/firmware-gate.sh: this is the
    # detokeniser the flash/key gate depends on, and `\espflash` is one of the bypasses
    # it exists to catch.
    case "$ch" in
      "'"|'"') : ;;                              # drop quote characters entirely
      '\')     out+="${t:i+1:1}"; (( i++ )) ;;   # escaped char: take the escapee
      *)       out+="$ch" ;;
    esac
    (( i++ ))
  done
  printf '%s' "${out##*/}"                       # basename AFTER unquoting: "/usr/bin/espflash"
}

_hs_is_wrapper() {
  case "$1" in
    env|command|sudo|doas|nice|ionice|chrt|nohup|setsid|stdbuf|time|timeout|xargs|\
    sh|bash|dash|zsh|ksh) return 0 ;;
    # ADDED 2026-07-28 after the probe measured each of these passing a flasher
    # through silently. `ssh host 'espflash …'` was route 3; `python -m esptool`,
    # `uvx esptool` and `pipx run esptool` were found by route 6's verifier. These are
    # program RUNNERS: whatever they are handed is the real operation, so the token
    # scan must look through them exactly as it does through `env`/`sudo`.
    ssh|python|python3|pipx|uvx|perl|ruby|node|npx) return 0 ;;
  esac
  return 1
}

# `make <target>` cannot be resolved without reading the Makefile, so it is gated on the
# TARGET NAME instead — fail-closed on the names that conventionally drive a programmer.
# This is a heuristic and is labelled as one: it will not catch a flashing recipe behind
# an innocuous target name, and it is not claimed to.
_hs_is_make_firmware() {
  local seg="$1" t
  [[ "$(_hs_detok "${seg%%[[:space:]]*}")" == make ]] || return 1
  for t in $seg; do
    case "$(_hs_detok "$t")" in
      flash|flash-*|*-flash|erase|erase-*|*-erase|burn|burn-*|program|program-*|\
      upload|dfu|ota|*-ota) return 0 ;;
    esac
  done
  return 1
}

# Is this segment a LOOKUP of a program rather than an INVOCATION of one? (#88)
#
# DEFECT (2026-07-20, hit by the supervisor's own pre-flight, and by hive the night
# before). `command` is in the wrapper list above — correctly, because `command
# espflash flash …` really does invoke a flasher and must not escape the gate. But
# that put `command -v espflash` — a pure "is it installed?" query that runs NOTHING
# — through the same token scan, and it denied.
#
# This is the openssl `-verify` lesson recurring one function down: the gate matched
# the VOCABULARY and not the ACT. A read-only availability check is the opposite of a
# flash, and blocking it taxes exactly the pre-flight that makes a flash safe. It
# blocked hive's escalation TO the supervisor and then blocked the supervisor's own
# artifact verification — a gate whose false positives block the checks that precede
# the dangerous act is worse than no gate at that moment.
#
# NARROW BY CONSTRUCTION: only `command`/`type`/`hash` with a lookup FLAG, or a bare
# `type`/`which`. `command espflash …` (no flag) still falls through to the scan.
_hs_is_lookup() {
  local seg="$1"; local -a t
  read -ra t <<<"$seg"
  [[ ${#t[@]} -ge 2 ]] || return 1
  case "${t[0]##*/}" in
    command|type|hash)
      case "${t[1]}" in -v|-V|-p|-t) return 0 ;; esac ;;
    which|whereis) return 0 ;;
  esac
  return 1
}

# Does command basename $1 (with full segment $2 for arg-context) denote a
# firmware-flash / firmware-sign / key-mint operation? (probe A9)
# openssl is DUAL-USE: `dgst` and `pkeyutl` SIGN or VERIFY depending on flags.
# Classify the OPERATION, not the vocabulary.
#
# LESSON (2026-07-17, reported by specs; core hit it too, and NEITHER routed
# around it). The old test matched `*' dgst'*` and `*' -sign'*` as SUBSTRINGS, so
#   openssl dgst -sha256 -verify pub.pem -signature sig.bin persona.bin
# was denied TWICE over — once for `dgst`, and once because `-signature` CONTAINS
# `-sign`. The sign-detector matched its own opposite. That command is a PURE
# VERIFICATION: the exact operation that CATCHES a bad artifact.
#
# WHY THIS WAS THE WORST OF THE THREE GATE DEFECTS. The gate exists to stop
# unauthorised signing/minting/flashing. Verification is the OPPOSITE operation.
# Blocking it does not prevent a risky action — IT PREVENTS THE EVIDENCE THAT
# WOULD TELL US WHETHER THE ACTION IS RISKY. Measured cost (specs' finding): core
# could not re-derive the baked cert, fell back to a six-byte prefix match on the
# subject — which is NOT a verification — so a would-be INDEPENDENTLY-VERIFIED
# artifact became a SINGLY-VERIFIED one, in the exact area where the fleet was
# chasing fail-silent radiating certs. The gate degraded the evidence base it
# exists to protect. VERIFYING IS NOT SIGNING.
_hs_openssl_mutates() {
  local -a t; local i sub="" start=0
  read -ra t <<<"$1"
  # LOCATE `openssl` first — the caller reaches here through the wrapper loop too,
  # so the segment may be `sudo openssl …` / `env X=1 openssl …` and t[0] is NOT
  # openssl. Assuming index 0 made `sudo openssl genpkey` read `openssl` as its own
  # subcommand and stop denying — caught by this file's own positive control.
  for (( i=0; i<${#t[@]}; i++ )); do
    [[ "${t[i]##*/}" == openssl ]] && { start=$i; break; }
  done
  for (( i=start+1; i<${#t[@]}; i++ )); do    # first non-flag token = subcommand
    case "${t[i]}" in -*) ;; *) sub="${t[i]}"; break ;; esac
  done
  case "$sub" in
    genpkey|genrsa|gendsa|ecparam|pkcs12|ca) return 0 ;;   # always mints
    dgst|pkeyutl)   # dual-use: an explicit verify flag wins; bare dgst = a hash
      for (( i=1; i<${#t[@]}; i++ )); do
        case "${t[i]}" in -verify|-verifyrecover|-prverify) return 1 ;; esac
      done
      for (( i=1; i<${#t[@]}; i++ )); do      # `-sign` as a TOKEN — `-signature` is not it
        case "${t[i]}" in -sign) return 0 ;; esac
      done
      return 1 ;;
    x509)           # prints by default; only mutates when it signs/creates
      for (( i=1; i<${#t[@]}; i++ )); do
        case "${t[i]}" in -req|-signkey|-CA|-CAkey) return 0 ;; esac
      done
      return 1 ;;
    req)            # `-in … -noout -text` prints; -new/-newkey/-x509/-keyout mint
      for (( i=1; i<${#t[@]}; i++ )); do
        case "${t[i]}" in -new|-newkey|-x509|-keyout) return 0 ;; esac
      done
      return 1 ;;
  esac
  return 1          # verify / asn1parse / pkey -pubout / version / … = inspection
}

# ssh-keygen IS A READ TOOL AND A MINT TOOL IN ONE BINARY, and until 2026-08-24 it sat
# in the unconditional arm below beside five key-minting binaries — classified by the
# word "keygen". MEASURED THAT DAY, and the inversion was inside a single line:
#   `ssh-keyscan -T 10 HOST | ssh-keygen -lf -`   -> DENY
#   `ssh-keyscan -T 10 HOST`  (that half alone)   -> ordinary prompt
# `ssh-keygen -lf -` reads bytes from stdin, mints nothing, touches no file and
# contacts no host. THE GATE DENIED THE READ THAT MINTS NOTHING AND PERMITTED THE READ
# THAT ESTABLISHES TRUST — a lane was stopped because it tried to LOOK at the key it
# was fetching. Reported by r2, escalated rather than worked around; the lane declined
# StrictHostKeyChecking=accept-new on its own judgement before it knew keyscan was
# unpoliced, which is the only reason this was found by a report and not by a surprise.
#
# THIS IS DEFECT 4 (VERIFYING IS NOT SIGNING) A SECOND TIME, ON A DIFFERENT BINARY. The
# openssl arm already carries that fix and has since 2026-07-17; ssh-keygen was left
# behind in the same file. A fix applied to one member of a list is not applied to the
# list.
#
# ALLOWLIST, NOT BLOCKLIST, AND THAT IS THE DESIGN RATHER THAN A DETAIL: a blocklist
# enumerates the dangerous flags somebody thought of, and this binary hides `-s` (sign
# a certificate), `-y` (read a private key), `-p` (rewrite a key file) and `-R` (rewrite
# known_hosts) among two dozen options. DENY unless EVERY option character present is
# named here:
#     l  print a fingerprint          f  input file (takes an argument)
#     F  find a host in known_hosts   Q  query supported algorithms
#     E  fingerprint hash algorithm   v  verbose
# Short options BUNDLE — `-lf -` is `-l -f -` — so every character of every cluster is
# checked, which is what stops `-lt ed25519` being read as an allowed `-l`. A bare
# `ssh-keygen` with no options is INTERACTIVE KEY GENERATION and denies. An empty or
# unparseable segment reaches the end with saw=0 and DENIES: fail closed.
#
# Locate the binary rather than assuming token 0, for the reason _hs_openssl_mutates
# already carries: the caller reaches here through the wrapper loop, so the segment may
# be `sudo ssh-keygen …` or `timeout 25 ssh-keygen …`.
_hs_sshkeygen_readonly() {
  local -a t; local i j tok rest ch start=0 saw=0
  read -ra t <<<"$1"
  for (( i=0; i<${#t[@]}; i++ )); do
    [[ "${t[i]##*/}" == ssh-keygen ]] && { start=$i; break; }
  done
  for (( i=start+1; i<${#t[@]}; i++ )); do
    tok="${t[i]}"
    case "$tok" in
      --*) return 1 ;;                 # no long option here is read-only; fail closed
      -)   continue ;;                 # the stdin operand
      -*)  saw=1; rest="${tok#-}"
           for (( j=0; j<${#rest}; j++ )); do
             ch="${rest:j:1}"
             case "$ch" in l|f|F|Q|E|v) ;; *) return 1 ;; esac
           done ;;
      *)   continue ;;                 # an operand: a filename, a host, an algorithm
    esac
  done
  (( saw ))
}

_hs_flash_or_mint() {
  local base="$1" seg="$2" cargo_sub cargo_d; local -a _cw
  case "$base" in
    dfu-util|dfu-programmer|st-flash|stm32flash|openocd|\
    nrfjprog|nrfutil|adafruit-nrfutil|JLinkExe|teensy_loader_cli|teensy-loader-cli|\
    cargo-embed|cargo-flash|probe-run|elf2uf2-rs|avrdude|bossac)
      return 0 ;;
    # espflash / esptool GAIN SUBCOMMAND DISCRIMINATION (2026-07-28), which their
    # siblings probe-rs / picotool / pyocd / arduino-cli have always had.
    #
    # WHY THIS IS A SECURITY CHANGE AND NOT A CONVENIENCE ONE. These two were an
    # UNCONDITIONAL basename match, so `espflash save-image` — a pure offline ELF→image
    # conversion with no port, no board, no device of any kind — was DENIED, three times
    # in one session on 2026-07-27. No grant could rescue it: `save-image` names no
    # target, so _hs_authorized fails its target test before it can allow. The operator's
    # only remaining routes were escalate-to-a-human or wrap-it-in-a-script, and the
    # wrapper era followed. A GATE THAT BLOCKS THE HARMLESS TRAINS PEOPLE TO ROUTE AROUND
    # IT, and every route around is silent and unaudited. Fixing the matcher without
    # fixing this leaves the incentive that produced the bypass fully intact.
    #
    # DIRECTION IS FAIL-CLOSED AND DECLARED: an UNKNOWN subcommand DENIES. Only an
    # explicit, enumerated set of no-device operations returns 1. A new espflash verb we
    # have never seen is treated as device-touching until someone adds it deliberately.
    espflash)
      case " $seg " in
        # file-only / informational: no port is opened, nothing is written to a device
        *' save-image '*|*' --version '*|*' -V '*|*' --help '*|*' -h '*|*' completions '*)
          return 1 ;;
      esac
      # Bare `espflash` with no subcommand prints usage and touches nothing.
      # COMPARE AGAINST THE RESOLVED BASENAME ($1), NOT THE SEGMENT'S FIRST TOKEN. The
      # first cut compared the segment to its own first word, so `T=espflash` — a segment
      # that IS its first word — was classified "bare" and let the variable-carried route
      # straight through. The exemption must apply only when the thing being run is
      # literally this tool with no arguments.
      [[ "$(printf '%s' "$seg" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')" == "$1" ]] && return 1
      return 0 ;;
    # espefuse / espsecure WERE ABSENT FROM THIS LIST ENTIRELY until 2026-07-28.
    #
    # espefuse BURNS eFUSES: burn_key, burn_efuse, write_protect_efuse, set_flash_voltage.
    # Every one is PERMANENT — no erase, no rollback, no reflash recovers it. It can brick
    # a part outright, or enable Secure Boot against a key digest nobody holds, which
    # makes the board unbootable forever. It is the most destructive tool in the ESP32
    # family and the gate did not know it existed, while gating `espflash`, which only
    # writes flash you can rewrite. A tool list assembled from what people USE will
    # always omit what they have not needed yet.
    #
    # espsecure signs images and generates signing keys — key-mint class by definition.
    #
    # DIRECTION IS STRICTER HERE THAN FOR espflash, DELIBERATELY: unknown subcommands
    # deny, AND so does a bare invocation. For a reversible tool a bare call costs an
    # escalation; for an irreversible one an unrecognised form must never slip through.
    # Read-only queries stay open so the eFuse state can be MEASURED without turning the
    # gate off — an enablement question answered by disabling a control is not an answer.
    espefuse|espefuse.py)
      case " $seg " in
        *' summary '*|*' dump '*|*' adc_info '*|*' get_custom_mac '*|\
        *' --version '*|*' --help '*|*' -h '*)
          return 1 ;;
      esac
      return 0 ;;
    espsecure|espsecure.py)
      case " $seg " in
        *' --version '*|*' --help '*|*' -h '*) return 1 ;;
      esac
      return 0 ;;
    esptool|esptool.py)
      case " $seg " in
        *' merge_bin '*|*' image_info '*|*' elf2image '*|*' version '*|\
        *' --version '*|*' --help '*|*' -h '*)
          return 1 ;;
      esac
      return 0 ;;
    probe-rs)
      case " $seg " in *' download'* | *' run'* | *' erase'* | *' flash'* | *' gdb'*) return 0 ;; esac ;;
    picotool)
      case " $seg " in *' load'* | *' save'* | *' erase'*) return 0 ;; esac ;;
    pyocd)
      case " $seg " in *' flash'* | *' erase'* | *' load'*) return 0 ;; esac ;;
    west)
      case " $seg " in *' flash'*) return 0 ;; esac ;;
    idf.py)
      case " $seg " in *' flash'*) return 0 ;; esac ;;
    pio|platformio)
      case " $seg " in *' upload'*) return 0 ;; esac ;;
    arduino-cli)
      case " $seg " in *' upload'* | *' burn-bootloader'*) return 0 ;; esac ;;
    # ssh-keyscan ADDED 2026-08-24. It mints nothing, which is exactly why it was
    # missed — but it fetches a host key off the network, and whatever is written from
    # its output becomes what this machine trusts from then on. That is the same trust
    # act as StrictHostKeyChecking=accept-new, which nobody would have left ungated.
    ssh-keyscan)
      return 0 ;;
    # ssh-keygen: deny by default, with the named read-only allowlist above.
    ssh-keygen)
      _hs_sshkeygen_readonly "$seg" && return 1
      return 0 ;;
    age-keygen|minisign|signify|certtool|mkcert)
      return 0 ;;
    keytool)
      case " $seg " in *' -genkey'* | *' -genseckey'* | *' -importcert'* | *' -certreq'*) return 0 ;; esac ;;   # ' -genkey'* already covers -genkeypair
    wg)
      case " $seg " in *' genkey'* | *' genpsk'*) return 0 ;; esac ;;
    cfssl)
      case " $seg " in *' gencert'* | *' genkey'* | *' sign'*) return 0 ;; esac ;;
    step)
      case " $seg " in *' certificate create'* | *' crypto keypair'* | *' ca sign'*) return 0 ;; esac ;;
    openssl)
      _hs_openssl_mutates "$seg" && return 0 ;;
    gpg|gpg2)
      case " $seg " in *' --sign'* | *' --clearsign'* | *' --detach-sig'* | *' --gen-key'* | *' --full-gen-key'* | *' --export-secret'*) return 0 ;; esac ;;
    dd)
      case " $seg " in *' of=/dev/'*) return 0 ;; esac ;;
    cargo|cross)
      # embed/flash/espflash always flash a device; `cargo run` flashes IFF the
      # target's .cargo runner is a flasher (probe-rs/cargo-embed/espflash/…)
      read -ra _cw <<<"$seg"; cargo_sub="${_cw[1]:-}"; [[ "$cargo_sub" == +* ]] && cargo_sub="${_cw[2]:-}"
      case "$cargo_sub" in
        embed|flash|espflash) return 0 ;;
        run|r|rr|runner)
          cargo_d="$cwd"
          while [[ -n "$cargo_d" ]]; do
            [[ -f "$cargo_d/.cargo/config.toml" ]] && grep -qiE 'runner[[:space:]]*=.*(probe-rs|probe-run|cargo-?embed|cargo-?flash|espflash|dfu-util|elf2uf2)' "$cargo_d/.cargo/config.toml" 2>/dev/null && return 0
            [[ "$cargo_d" == "/" ]] && break; cargo_d="${cargo_d%/*}"; [[ -z "$cargo_d" ]] && cargo_d="/"
          done ;;
      esac ;;
  esac
  return 1
}

# Split a command into top-level segments, HONOURING QUOTES.
#
# LESSON (2026-07-17). The previous splitter was `${c//&&/;}` + split-on-';' —
# QUOTE-BLIND. Text inside '…' or "…" is DATA, not shell, but it was fragmented
# anyway and each fragment was then classified AS IF IT WERE A COMMAND. So a
# commit message or a fleet note that merely DESCRIBED this subject tripped the
# gate: `git commit -m "a; write-persona is the wrong verb"` → fragment
# ` write-persona is the wrong verb"` → matched the verb list → hard DENY. It
# blocked three lanes in one evening, including a RESUME.md commit — i.e. it
# blocked the DURABLE HANDOFF RECORD — and a lane escalating a security finding
# TO the supervisor. A gate that taxes precise reporting of a defect degrades the
# evidence base it exists to protect, and teaches lanes to describe findings
# vaguely to get them through. Gates must match ACTS, never the WORDS in a
# message body. Parse the structure; do not substring-match fragments.
# HEREDOC BODIES ARE DATA, NOT COMMANDS (#88, found 2026-07-20).
#
# The splitter already knows that text inside '…'/"…" is DATA — that was defect (1) in
# tests/firmware-gate.sh, and fixing it stopped the gate denying commit messages. IT WAS
# NEVER GENERALISED TO HEREDOCS, which are the other way a shell carries a document.
#
#   cat > _FLASH-SAFETY.md <<EOF
#   Wrong: cd staged; espflash flash --partition-table partitions.csv
#   EOF
#
# The ';' inside the BODY split the "command", the next fragment began with a flasher
# name, and the gate hard-DENIED. That is one `cat`, writing one markdown file, touching
# no device. Measured live: a body with no metacharacter passes, a body containing ';'
# followed by a flasher name DENIES — so the gate blocks precisely the document that
# quotes the dangerous invocation in order to warn against it.
#
# ★ SAME DEFECT AS (1), ONE FORM OUT. The lesson "quoted text is data" was learned and
# not carried to the next construct that carries data. And it lands in the same place
# both times: a gate whose false positives block REMEDIATION and the DOCUMENTATION of
# the hazard it guards. Third instance in one session of an artifact tripping the
# detector for the hazard it documents.
#
# We skip the body and keep scanning AFTER the terminator, so a real command chained
# after a heredoc is still classified: `cat <<EOF > f\n…\nEOF\nespflash flash x` denies.
_hs_skip_heredoc() {   # echo the index just past the heredoc body, or -1 if not one
  local s="$1" i="$2" n="$3" delim='' j c
  (( i + 1 < n )) || { printf '%s' -1; return; }
  [[ "${s:i:2}" == '<<' ]] || { printf '%s' -1; return; }
  j=$(( i + 2 ))
  [[ "${s:j:1}" == '<' ]] && { printf '%s' -1; return; }   # `<<<` here-STRING, not a doc
  [[ "${s:j:1}" == '-' ]] && (( j++ ))                     # `<<-` strips leading tabs
  while (( j < n )); do c="${s:j:1}"; [[ "$c" == ' ' || "$c" == $'\t' ]] || break; (( j++ )); done
  while (( j < n )); do                                    # delimiter word, quoted or bare
    c="${s:j:1}"
    case "$c" in [A-Za-z0-9_]) delim+="$c"; (( j++ )) ;; "'"|'"') (( j++ )) ;; *) break ;; esac
  done
  [[ -n "$delim" ]] || { printf '%s' -1; return; }
  # find a line that is exactly the delimiter (optionally indented, per `<<-`)
  local rest="${s:j}" line off=$j
  while [[ "$rest" == *$'\n'* ]]; do
    rest="${rest#*$'\n'}"; off=$(( n - ${#rest} ))
    line="${rest%%$'\n'*}"; line="${line#"${line%%[! 	]*}"}"
    [[ "$line" == "$delim" ]] && { printf '%s' "$(( off + ${#line} ))"; return; }
  done
  printf '%s' "$n"    # unterminated heredoc: the rest of the command is body
}

_hs_segments() {
  local s="$1"                       # NB: separate statement — a `local` line expands
  local i=0 n=${#s} ch q='' seg=''   # every word BEFORE assigning, so `n=${#s}` on the
                                     # same line reads an unset s and `set -u` aborts.
  local _hd
  while (( i < n )); do
    ch="${s:i:1}"
    if [[ -z "$q" && "$ch" == '<' ]]; then
      # `<<<` is a here-STRING and carries no body. It must be consumed WHOLE: rejecting
      # it and advancing one char leaves the scanner on the 2nd '<', where `<< "text"`
      # reads as a heredoc whose delimiter never appears — so the skip runs to end-of-
      # string and SWALLOWS EVERY COMMAND AFTER IT. That is a laundering channel, and
      # it was opened by the fix for the false positive above. Caught by the KAT
      # `grep -q x <<< "t"; espflash flash …`, which the suite did not have until the
      # same commit: the heredoc fix and the KAT that falsifies it must land together.
      if [[ "${s:i:3}" == '<<<' ]]; then seg+='<<<'; i=$(( i + 3 )); continue; fi
      _hd="$(_hs_skip_heredoc "$s" "$i" "$n")"
      if [[ "$_hd" != -1 ]]; then i="$_hd"; continue; fi
    fi
    if [[ -n "$q" ]]; then                       # inside a quote: copy verbatim
      # Inside "…" a backslash ESCAPES the next char, including the closing quote;
      # inside '…' a backslash is literal. Shell semantics, and load-bearing: the
      # first cut of this splitter skipped it, so `fleet broadcast "… -m \"a;
      # write-persona\" …"` read the \" as a CLOSING quote, fell out of the quoted
      # region, split on the ';', and denied the message. It denied this very
      # commit's own announcement. Prose quoting prose is the COMMON case here.
      # shellcheck disable=SC1003  # '\' is a literal backslash to match, not a bad escape
      if [[ "$q" == '"' && "$ch" == '\' ]]; then
        seg+="$ch${s:i+1:1}"; (( i+=2 )); continue
      fi
      seg+="$ch"; [[ "$ch" == "$q" ]] && q=''
      (( i++ )); continue
    fi
    # shellcheck disable=SC1003  # the '\' branch is a literal-backslash pattern, not a bad escape
    case "$ch" in
      "'"|'"')  q="$ch"; seg+="$ch" ;;           # quote opens → text is data
      '\')      seg+="$ch${s:i+1:1}"; (( i++ )) ;;   # escaped char: take both
      ';'|'&'|'|')
        printf '%s\n' "$seg"; seg=''
        while (( i+1 < n )); do                  # swallow the rest of &&, ||, ;;
          case "${s:i+1:1}" in ';'|'&'|'|') (( i++ )) ;; *) break ;; esac
        done ;;
      *)        seg+="$ch" ;;
    esac
    (( i++ ))
  done
  printf '%s\n' "$seg"
}

# Does this SEGMENT invoke fleet messaging? The wire only DELIVERS text, never
# executes it, so OTA/cert/sign/mint WORDS in a note are not operations.
# Looks THROUGH wrappers (`timeout 30 fleet send …`) — the old check read only
# token 0 of the WHOLE command, so any `cd … && fleet send …` defeated it.
# FAIL-CLOSED on a command substitution: `fleet send "$(espflash …)"` is not
# just text, so it does not earn the exemption.
# Explicit signed-OTA / cert-mint / persona-write verbs, matched as a TOKEN
# SEQUENCE rather than by substring.
#
# LESSON (2026-07-17, found by writing positive controls for the fix above).
# The old test was `case " $seg " in *' ota '*' sign'*)` — and it COULD NOT MATCH
# `composer ota sign`, the exact canonical form it names: matching `' ota '`
# consumes the space that `' sign'` then requires, so only the non-adjacent
# `ota --foo sign` ever fired. Same for `' ota '*' push'`. So the gate's headline
# verbs NEVER caught their headline case, and every green run "confirmed" a check
# that was structurally incapable of firing — the decorative-cert defect
# (task #89), one level up, in the gate itself. Substring patterns with
# overlapping delimiters are a trap; compare TOKENS.
# NB `sign` as a token, never a substring — `*sign*` would match `design`.
# GAP FOUND 2026-07-27, reported by composer AGAINST ITS OWN CONVENIENCE while it held explicit
# grant authority. The metal BLE-OTA pusher WRITES FIRMWARE TO A BOARD OVER A RADIO and was NOT
# gated at all: only the USB flashers are in the basename list, and the `ota` branch below
# anticipated `ota push` as TWO tokens while the real CLI subcommand is the SINGLE hyphenated
# token `ota-push`. So the gate had the right shape and the wrong spelling — a decorative gate
# for this path. A tool that writes firmware to a device is a firmware-write operation whatever
# it is called and whichever bearer it uses; the flash gate was never meant to be USB-specific.
#
# WHY THE SUBCOMMAND AND NOT THE BINARY: it also runs via `cargo run --bin …  -- ota-push`, so a
# basename match misses the common invocation. Match the verb token, on any tool.
#
# DRY-RUN IS EXEMPT AND THAT IS AN OPERATION CLASSIFICATION, NOT A COURTESY: `--dry-run` drives
# an in-process mock — no radio, no device, nothing written. Same principle as the openssl branch
# and `command -v`: classify the ACT, not the vocabulary.
#
# FAIL-SAFE CONSTRUCTION: the exemption requires the flag as a WHOLE TOKEN, never a substring, so
# a path or filename containing "dry-run" cannot buy a pass — that would fail OPEN, the one
# direction this file must never fail. And on the exempt path we do NOT return early: we fall
# through so the remaining tokens are still scanned for other gated verbs.
#
# NOT GATED, deliberately (composer's source-level classification, and Roy's delegation):
# gen-persona, gen-role, derive-id, carrier-plan, recipe-index, ensemble-compose. None touch a
# device, and gen-persona is the synthetic dev-trial mint class Roy DELEGATED on 2026-07-17 with
# no per-mint gate — re-gating it through a tool-name match would quietly overturn that ruling.
# There is no separate signing subcommand in that repo: signing is inline in ota-push, so gating
# the real push covers the sign too.
_hs_verb_seq() {
  local -a t; local i j dry
  read -ra t <<<"$1"
  for (( i=0; i<${#t[@]}; i++ )); do
    case "${t[i]}" in
      sign-firmware|mint-cert|write-persona|write_persona) return 0 ;;
      ota-push|ota_push)
                 dry=0
                 for (( j=0; j<${#t[@]}; j++ )); do
                   case "${t[j]}" in --dry-run|--dry_run) dry=1; break ;; esac
                 done
                 (( dry )) || return 0 ;;
      ota)       for (( j=i+1; j<${#t[@]}; j++ )); do
                   case "${t[j]}" in sign|push) return 0 ;; esac; done ;;
      mint)      for (( j=i+1; j<${#t[@]}; j++ )); do
                   case "${t[j]}" in cert|certificate|cert-*) return 0 ;; esac; done ;;
      provision) for (( j=i+1; j<${#t[@]}; j++ )); do
                   case "${t[j]}" in write) return 0 ;; esac; done ;;
    esac
  done
  return 1
}

_hs_is_fleet_msg() {
  case "$1" in *'$('* | *'`'*) return 1 ;; esac
  local -a t; read -ra t <<<"$1"; local i
  for (( i=0; i<${#t[@]}; i++ )); do
    [[ "${t[i]##*/}" == fleet ]] || continue
    case "${t[i+1]:-}" in send|broadcast|ask|pair-send|pair-ask) return 0 ;; esac
    return 1
  done
  return 1
}

hs_bash() {   # is this Bash command a flash / firmware-sign / key-mint operation?
  local c="$1" first base seg tb tbn inner body; local -a segtoks
  # git and fleet-messaging are exempted PER-SEGMENT (never whole-command): the
  # commit message / note may MENTION mint/sign/cert as prose, but a real flasher
  # after `git commit && …` is its OWN segment and must still be gated.
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [[ -n "$seg" ]] || continue
    first="${seg%%[[:space:]]*}"; base="$(_hs_detok "$first")"
    case "$seg" in *'$('* | *'`'*) : ;; *)
      [[ "$base" == git ]] && continue ;;   # git segment = source control, never a runtime flash/mint
    esac
    _hs_is_fleet_msg "$seg" && continue
    _hs_is_lookup "$seg" && continue      # `command -v espflash` runs nothing (#88)
    _hs_is_noexec "$seg" && continue      # `bash -n file` parses, executes nothing
    _hs_flash_or_mint "$base" "$seg" && { _HS_MATCHED_SEG="$seg"; return 0; }
    _hs_is_make_firmware "$seg" && { _HS_MATCHED_SEG="$seg"; return 0; }
    # look THROUGH a command-wrapper (env/sudo/timeout/nice/bash -c … <flasher>):
    # re-classify every token's basename so the wrapper can't hide the real op.
    if _hs_is_wrapper "$base" || _hs_is_assign "$first"; then
      read -ra segtoks <<<"$seg"
      # AN ASSIGNMENT CARRIES ITS PAYLOAD ON THE RIGHT OF THE '='. `T=espflash` tokenises
      # whole, so the basename compared was the literal `T=espflash` and matched nothing —
      # `T=espflash; $T flash …` went straight through. Test the VALUE. This scan is safe
      # over ALL tokens because `X=espflash` is unambiguous: nothing else has that shape.
      for tb in "${segtoks[@]}"; do
        _hs_is_assign "$tb" || continue
        _hs_flash_or_mint "$(_hs_detok "${tb#*=}")" "$seg" && { _HS_MATCHED_SEG="$seg"; return 0; }
      done
      # RESOLVE THE PROGRAM, DO NOT SCAN EVERY TOKEN.
      #
      # THIRD OVERREACH CAUGHT BY THE SUITE: scanning all tokens denied
      # `command grep -n espflash flash-board.sh` — the tool name there is a SEARCH
      # PATTERN, not the program. Under the all-tokens rule, any command that so much as
      # MENTIONS a flasher was refused, which is the false-positive engine that produced
      # the wrapper era in the first place.
      #
      # Walk past wrapper names, options and numeric arguments (`timeout 60 espflash`);
      # the first token that is none of those IS the program. Classify only that, then
      # stop — a flasher appearing after the program is an argument, not an operation.
      # `ssh` takes a DESTINATION before the remote command, so the first non-option
      # token is the host, not the program. Missed on the first cut and caught by the
      # suite: A3 regressed to silence because `h.invalid` was resolved as the program.
      local _skip_operand=0
      [[ "$base" == ssh ]] && _skip_operand=1
      for tb in "${segtoks[@]:1}"; do
        tbn="$(_hs_detok "$tb")"
        case "$tbn" in
          ''|-*) continue ;;                    # option
          *=*)   _hs_is_assign "$tb" && continue ;;
        esac
        [[ "$tbn" =~ ^[0-9]+$ ]] && continue    # e.g. the seconds in `timeout 60 …`
        if _hs_is_wrapper "$tbn"; then          # chained wrappers: env sudo espflash
          [[ "$tbn" == ssh ]] && _skip_operand=1
          continue
        fi
        if (( _skip_operand )); then _skip_operand=0; continue; fi   # ssh destination
        [[ "$tbn" == git ]] && break
        _hs_flash_or_mint "$tbn" "$seg" && { _HS_MATCHED_SEG="$seg"; return 0; }
        break                                   # program identified and it is not gated
      done
      # SCRIPT-FILE LOOK-THROUGH — the route that actually fired in production.
      # `bash flash-board.sh X1` carries the flasher only INSIDE the file, so no token
      # scan can ever see it. Read the file and classify its CONTENT. Depth-limited so a
      # script that sources itself cannot spin. If the file is named but UNREADABLE we
      # deny: an invocation whose program we cannot inspect is exactly the laundering
      # shape, and failing open there is what made routes 2 and 4 silent.
      # ONLY when the file is being EXECUTED, never when it is merely NAMED.
      #
      # SECOND OVERREACH CAUGHT BY THE GATE FIRING ON ITS AUTHOR: the first cut scanned
      # every token, so `command grep -n pattern some-script.sh` — a READ of a file that
      # happens to mention a flasher — was denied. `cat`, `wc`, `grep`, `shellcheck` on
      # any script mentioning espflash would all have denied. A gate that fires on
      # READING a file is worse than the bypass it replaced.
      #
      # The interpreter must be a SHELL, and the candidate must be the FIRST NON-OPTION
      # argument — i.e. the thing the shell is being asked to run.
      if (( ${_HS_FILE_DEPTH:-0} < 3 )) && [[ "$base" =~ ^(sh|bash|dash|zsh|ksh|source|\.)$ ]]; then
        local _cand='' _body=''
        for tb in "${segtoks[@]:1}"; do
          tbn="$(_hs_detok "$tb")"
          case "$tbn" in -*|'') continue ;; esac
          _cand="$tbn"; break                     # first non-option arg = the program
        done
        # RESOLVE RELATIVE TO THE PAYLOAD'S cwd, not the hook's. The hook does not chdir,
        # so `bash flash-board.sh` — the exact shape that fired in production — resolved
        # against the wrong directory, `-f` failed, and the look-through silently did
        # nothing. A path test against the wrong base is a check that always passes.
        [[ -n "$_cand" && "$_cand" != /* ]] && _cand="$cwd/$_cand"
        if [[ -n "$_cand" && -f "$_cand" ]]; then
          if [[ -r "$_cand" ]]; then
            _body="$(cat -- "$_cand" 2>/dev/null)" || _body=''
            if [[ -n "$_body" ]]; then
              _HS_FILE_DEPTH=$(( ${_HS_FILE_DEPTH:-0} + 1 ))
              if hs_bash "$_body"; then
                _HS_FILE_DEPTH=$(( _HS_FILE_DEPTH - 1 ))
                _HS_MATCHED_SEG="$seg"; return 0
              fi
              _HS_FILE_DEPTH=$(( _HS_FILE_DEPTH - 1 ))
            fi
          else
            # named as the program but UNREADABLE → fail closed. An invocation whose
            # program cannot be inspected is the laundering shape itself.
            _HS_MATCHED_SEG="$seg"; return 0
          fi
        fi
      fi
    fi
    # explicit signed-OTA / cert-mint / persona-write verbs on any tool
    _hs_verb_seq "$seg" && { _HS_MATCHED_SEG="$seg"; return 0; }
    # a command substitution embeds a REAL command — scan its body too, so
    # `fleet send hive "$(espflash flash …)"` cannot launder a flasher through
    # an exemption. Terminates: each pass consumes one `$(`.
    inner="$seg"
    while [[ "$inner" == *'$('* ]]; do
      inner="${inner#*\$(}"
      body="${inner%%)*}"
      [[ -n "$body" ]] && hs_bash "$body" && { _HS_MATCHED_SEG="$seg"; return 0; }
    done
  done < <(_hs_segments "$c")
  return 1
}

# --- Per-operation firmware authorization (#88) --------------------------------
#
# WHY THIS EXISTS. Before it, the only way past the gate was FLEET_FIRMWARE_GATE=off
# — blanket, permanent, silent, and leaving no record of what was flashed or on whose
# say-so. A gate whose sole escape hatch is "turn it off" gets turned off the first
# time it is inconvenient and never fires again. Observed 2026-07-20: the gate blocked
# an authorized flash three times in one session, and the honest options were "hand the
# command to the human" or "disable the gate". Neither is a path a system should push
# people toward.
#
# WHAT IT IS. A single-operation record the principal writes, naming the artifact
# basename, the target, an expiry, and the expected sha256:
#
#     $ws/.fleet/flash-authorization
#         expires=<unix-epoch>
#         artifact=<basename>
#         target=<device or host:device>
#         sha256=<expected digest>          # audit; see the honest limit below
#
# The gate allows a flash ONLY when a live record exists AND the MATCHED SEGMENT names
# BOTH that artifact and that target, and it stops authorizing when it expires.
#
# ★★ CORRECTED 2026-07-28 — THIS COMMENT USED TO SAY "It authorizes one operation, not a
# class." THAT WAS FALSE AS WRITTEN, and it was measured false: three identical payloads
# against one grant returned allow / allow / allow with the grant file intact.
# `_hs_authorized` never consumed, decremented or invalidated anything. What a grant
# actually is: A TIME-WINDOWED CLASS AUTHORISATION for one (artifact, target) substring
# pair — unlimited uses until expiry. It is written that way now because a comment that
# overstates a control is worse than no comment: the next reader trusts it and stops
# looking. Retiring a spent grant is a SEPARATE ACT the granter must perform.
#
# ★ THE HONEST LIMIT, STATED IN THE FILE RATHER THAN ASSUMED. This raises the bar; it
# is NOT a boundary against a determined agent, because any process that can read this
# file can also write it. What it buys is real but narrower than "enforcement":
#   - no ACCIDENTAL flash — the default is still a hard deny
#   - one operation per grant, with an expiry, instead of a permanent global off-switch
#   - an audit trail naming artifact + target + time, so what ran is reconstructable
#   - forging it requires writing a specific, dated, artifact-named record — a
#     deliberate and legible act, not a flag flip
# THE HUMAN REMAINS THE BOUNDARY. Do not describe this as making flashes safe.
#
# The sha256 field is RECORDED, not enforced: a remote flash (ssh to another host)
# gives this hook no way to hash the bytes that will actually be written. Binding is
# on artifact-name + target, which IS checkable here; the digest exists so a mismatch
# is discoverable afterwards. Stating which half is enforced matters — a field that
# looks like a check and is not one is the decorative-gate defect this file already
# carries two lessons about.
_hs_authorized() {
  local c="$1" f="$ws/.fleet/flash-authorization"
  [[ -r "$f" ]] || return 1
  local expires="" artifact="" target="" sha256="" k v
  while IFS='=' read -r k v; do
    case "$k" in
      expires)  expires="$v" ;;
      artifact) artifact="$v" ;;
      target)   target="$v" ;;
      sha256)   sha256="$v" ;;
    esac
  done < "$f"
  # every field is REQUIRED — a partial record authorizes nothing. An empty
  # artifact or target would otherwise substring-match every command.
  [[ -n "$expires" && -n "$artifact" && -n "$target" ]] || { _hs_audit DENIED no-grant-fields "$c"; return 1; }
  [[ "$expires" =~ ^[0-9]+$ ]] || { _hs_audit DENIED bad-expires "$c"; return 1; }
  [[ "$expires" -gt "$(date +%s)" ]] || { _hs_audit DENIED expired "$c"; return 1; }

  # MATCH AGAINST THE MATCHED SEGMENT, WITH ANY TRAILING COMMENT REMOVED.
  #
  # THE LAUNDERING DEFECT THIS CLOSES (measured 2026-07-28). This function used to test
  # the WHOLE command string while hs_bash had matched PER SEGMENT. Under a grant for
  # (probe-fixture.bin, /dev/ttyPROBE0) all of these were ALLOWED:
  #   esptool.py --chip esp32s3 erase_flash # authorized: probe-fixture.bin -> /dev/ttyPROBE0
  #   echo probe-fixture.bin /dev/ttyPROBE0 && esptool.py --chip esp32s3 erase_flash
  #   esptool.py --port /dev/ttyACM0 write_flash 0x0 attacker.bin   (tokens echoed ahead)
  #   esptool.py --port /dev/ttyACM0 read_flash 0x9000 0x6000 secrets.bin # <tokens>
  # The last one is the worst: A FLASH GRANT AUTHORISING NVS / KEY EXTRACTION. Tokens in
  # a comment, or in a different segment, are not part of the operation being authorised.
  local segn="${c%%#*}"
  [[ "$segn" == *"$artifact"* ]] || { _hs_audit DENIED artifact-not-in-segment "$c"; return 1; }
  [[ "$segn" == *"$target"*   ]] || { _hs_audit DENIED target-not-in-segment   "$c"; return 1; }

  # AUDIT IS A PRECONDITION OF THE ALLOW, NOT A SIDE EFFECT OF IT.
  # Previously `>> … 2>/dev/null || true`: an operation whose audit write FAILED was
  # allowed anyway and was byte-identical in the record to one that never happened.
  # If we cannot record it, we do not authorise it.
  _hs_audit USED allowed "$c" || return 1
  return 0
}

# One audit writer for both outcomes. Records the COMMAND's own text alongside the grant
# fields — the old line recorded only the GRANT's artifact/target, so a laundered erase
# was logged as a flash of the granted artifact: a record that AFFIRMATIVELY MISDESCRIBED
# the operation. Returns non-zero if the record could not be written.
_hs_audit() {
  local outcome="$1" reason="$2" cmd="$3" logf="$ws/.fleet/flash-authorization.log"
  local safe; safe="$(printf '%s' "$cmd" | tr '\t\n' '  ' | cut -c1-160)"
  printf '%s\t%s\treason=%s\tgrant_artifact=%s\tgrant_target=%s\tsha256=%s\tcmd=%s\n' \
    "$(date -Is)" "$outcome" "$reason" "${artifact:-none}" "${target:-none}" \
    "${sha256:-unrecorded}" "$safe" >> "$logf" || return 1
  return 0
}

hs_path() {   # is this Write/Edit target a key / signature / trust-material artifact?
  case "$1" in
    *.key | *.pem | *.sig | *.der | *.p12 | *.pfx | *.jks | *.seed | *.privkey) return 0 ;;
    *tg_priv* | *_private_key* | *private-key* | *persona*.bin | *keystore*.db | *wallet*.dat) return 0 ;;
  esac
  return 1
}

case "$tool" in
  Read|Glob|Grep|LS|NotebookRead|TodoWrite|WebSearch)
    allow "read-only tool" ;;
  Edit|Write|MultiEdit|NotebookEdit)
    [[ "${FLEET_AUTOCONFIRM_EDITS:-on}" == "off" ]] && ask
    p="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // .input.file_path // .input.path // .params.file_path // .params.path // ""' 2>/dev/null)"
    [[ -n "$p" ]] || ask
    [[ "${FLEET_FIRMWARE_GATE:-on}" != "off" ]] && hs_path "$p" && \
      deny "write to a key / signature / trust-material artifact ($p) — report to the supervisor with the exact artifact + authority + reason; do not auto-write"
    case "$p" in
      "$ws"/* | "$ws") allow "in-workspace edit" ;;   # absolute, inside workspace
      /*) ask ;;                                        # absolute, outside → prompt
      *)  allow "in-workspace edit (relative to cwd)" ;;
    esac ;;
  Bash)
    c="$(printf '%s' "$payload" | jq -r '.tool_input.command // .input.command // .params.command // .command // ""' 2>/dev/null)"
    [[ -n "$c" ]] || ask
    _HS_MATCHED_SEG=''   # reset per invocation; a stale value would authorise the wrong text
    if [[ "${FLEET_FIRMWARE_GATE:-on}" != "off" ]] && hs_bash "$c"; then
      # PASS THE MATCHED SEGMENT, NEVER THE WHOLE COMMAND — see the laundering note in
      # _hs_authorized. Empty means hs_bash matched by a path that failed to record which
      # segment did it: FAIL CLOSED rather than fall back to whole-command matching,
      # because that fallback IS the defect.
      if [[ -n "$_HS_MATCHED_SEG" ]] && _hs_authorized "$_HS_MATCHED_SEG"; then
        allow "firmware op under a live per-operation authorization (see .fleet/flash-authorization)"
      fi
      deny "firmware flash / firmware sign / key-mint operation — report to the supervisor with the exact artifact + target + authority + reason; do not auto-run"
    fi
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
