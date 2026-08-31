#!/usr/bin/env bash
# githooks.sh — install + drift-check the repo-level Git hooks.
#
# WHY THIS FILE EXISTS (2026-07-15). The git hooks were hand-copied into each repo's
# .git/hooks/ once, in 2026-07-07, and never synced again. Nothing in this tool referenced
# hooks/git/ at all — no installer, no check. So source-of-truth and deployed drifted
# silently: a MAC-value scan lived in master while running in ZERO repos, and every gate
# still reported CLEAN. An un-installed hook protects nothing.
#
# The DRIFT CHECK matters more than the installer. The installer fixes today's state; the
# check is what makes this class of failure *detectable* forever — it is the thing that
# would have caught the original drift. Both live here so the command and `fleet doctor`
# compare the same way and cannot disagree.
#
# Used by: bin/fleet (cmd_install_git_hooks, cmd_doctor).

# The pre-push guard covers secret/MAC leakage and decision-log accountability;
# commit-msg preserves agent/session attribution. Both sources ship in THIS checkout.
#
# ⚠ SEQUENCING TRAP: TOOL_ROOT follows the `fleet` symlink back to whatever checkout it
# points at, on whatever branch that checkout happens to be on — NOT origin/master. So the
# hook you deploy is the hook in the running checkout's working tree. Check out the branch
# you intend to deploy FIRST. fleet_git_hook_provenance() exists so this is printed on every
# install rather than trusted to memory.
fleet_git_hook_names() { printf '%s\n' pre-push commit-msg; }
fleet_git_hook_src() { printf '%s/hooks/git/%s\n' "$TOOL_ROOT" "${1:-pre-push}"; }

# A one-line provenance banner for the source checkout: branch, short sha, and whether the
# hook file itself is locally modified (i.e. you are about to deploy uncommitted changes).
fleet_git_hook_provenance() {
  local br sha dirty=""
  br="$(git -C "$TOOL_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  sha="$(git -C "$TOOL_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"
  if ! git -C "$TOOL_ROOT" diff --quiet -- hooks/git/ 2>/dev/null; then
    dirty=" (LOCALLY MODIFIED — deploying uncommitted hooks)"
  fi
  printf '%s @ %s%s\n' "$br" "$sha" "$dirty"
}

# Resolve a repo's real hooks dir (honours worktrees / core.hooksPath). Empty + non-zero
# when $1 is not a git repo.
fleet_git_hook_dir() {
  local repo="$1" hk
  hk="$(git -C "$repo" rev-parse --git-path hooks 2>/dev/null)" || return 1
  [[ -n "$hk" ]] || return 1
  [[ "$hk" != /* ]] && hk="$repo/$hk"
  printf '%s\n' "$hk"
}

# Is this hook OURS (any version) rather than a foreign repo-local hook?
fleet_git_hook_is_ours() {
  local file="$1" name="${2:-pre-push}" marker
  case "$name" in
    pre-push) marker=FLEET_SKIP_SECRET_SCAN ;;
    commit-msg) marker=FLEET_COMMITMSG_VERSION ;;
    *) return 1 ;;
  esac
  grep -q "$marker" "$file" 2>/dev/null
}

# The declared version of one hook file, as a bare integer. Empty when absent/unparseable.
fleet_hook_version() {
  local file="$1" name="${2:-pre-push}" marker v
  case "$name" in
    pre-push)   marker=PREPUSH_VERSION ;;
    commit-msg) marker=FLEET_COMMITMSG_VERSION ;;
    *) return 1 ;;
  esac
  v="$(grep -m1 -oE "^# ${marker}: [0-9]+" "$file" 2>/dev/null | grep -oE '[0-9]+$')" || true
  printf '%s\n' "$v"
}

# Drift state of one repo's deployed named hook vs source-of-truth.
# Echoes exactly one of:
#   ok | missing | notgit
#   drift-stale     deployed is BEHIND source          → reinstall
#   drift-ahead     deployed is AHEAD of source        → DO NOT reinstall; promote the source
#   drift-tampered  same declared version, other bytes → reinstall (source owns its version)
#   drift-unknown   either version unparseable         → report, no remedy
#
# ‼ WHY THE DIRECTION IS MEASURED RATHER THAN ASSUMED. This check was written for one case —
#   source gains a scan while repos keep running the old file — and it named the other side
#   "source-of-truth", so its remedy was always "overwrite the deployed one". MEASURED
#   2026-09-01: r2-standard ran PREPUSH_VERSION 13 (55384 bytes) against a source at 12
#   (47222). THE DEPLOYED HOOK WAS NINE DAYS AHEAD. Its delta was the D-186 r2-impl fold
#   exemption — `IMPORTED HISTORY` appears 4 times deployed and 0 times in source — so the
#   advertised remedy would have DELETED a named exemption covering 1726 commits and made
#   every later push of that subtree fail the decision gate.
#
# ‼ A DRIFT CHECK THAT NAMES A SOURCE OF TRUTH WITHOUT MEASURING WHICH SIDE IS NEWER WILL
#   ALWAYS TELL YOU TO OVERWRITE THE NEWER ONE. The word "source" did the deciding, not a
#   comparison. Detecting a difference and knowing which side is stale are two findings and
#   only the first was ever computed.
fleet_hook_drift_state() {
  local repo="$1" name="${2:-pre-push}" hk dep src dv sv
  src="$(fleet_git_hook_src "$name")"
  [[ -f "$src" ]] || { printf 'notgit\n'; return 0; }
  hk="$(fleet_git_hook_dir "$repo")" || { printf 'notgit\n'; return 0; }
  dep="$hk/$name"
  [[ -f "$dep" ]] || { printf 'missing\n'; return 0; }
  if [[ "$(sha256sum "$dep" 2>/dev/null | cut -d' ' -f1)" == "$(sha256sum "$src" 2>/dev/null | cut -d' ' -f1)" ]]; then
    printf 'ok\n'; return 0
  fi
  dv="$(fleet_hook_version "$dep" "$name")"; sv="$(fleet_hook_version "$src" "$name")"
  if [[ -z "$dv" || -z "$sv" ]]; then printf 'drift-unknown\n'
  elif (( 10#$dv > 10#$sv ));      then printf 'drift-ahead\n'
  elif (( 10#$dv < 10#$sv ));      then printf 'drift-stale\n'
  else                                  printf 'drift-tampered\n'
  fi
}

# Install the source hook into one repo. Idempotent and safe to re-run.
# $2 = "dry" to report the action without touching anything.
# Echoes one of: current | updated | installed | preserved | notgit
#
# A pre-existing FOREIGN hook is moved to <name>.local rather than clobbered — both shipped
# hooks chain to that file, so the repo's own hook keeps running. `.local` is load-bearing,
# not an archive.
fleet_install_git_hook() {
  local repo="$1" mode="${2:-}" name="${3:-pre-push}" hk dep src action
  src="$(fleet_git_hook_src "$name")"
  [[ -f "$src" ]] || { printf 'notgit\n'; return 1; }
  hk="$(fleet_git_hook_dir "$repo")" || { printf 'notgit\n'; return 0; }

  dep="$hk/$name"
  if [[ -f "$dep" ]]; then
    if [[ "$(sha256sum "$dep" 2>/dev/null | cut -d' ' -f1)" == "$(sha256sum "$src" 2>/dev/null | cut -d' ' -f1)" ]]; then
      action=current
    elif [[ "$(fleet_hook_drift_state "$repo" "$name")" == drift-ahead ]]; then
      # ‼ REFUSE THE DOWNGRADE. doctor only advises; THIS function acts, so this is where the
      #   wrong remedy would actually have destroyed the exemption. No override env var is
      #   offered on purpose — the correct path is to promote the newer hook into the source,
      #   after which the deployed copy is behind and installs normally. A bypass here would
      #   be a way to lose a security control by typing one variable.
      printf 'refused-ahead\n'; return 0
    elif fleet_git_hook_is_ours "$dep" "$name"; then
      action=updated
    else
      action=preserved
    fi
  else
    action=installed
  fi

  if [[ "$mode" != dry && "$action" != current ]]; then
    mkdir -p "$hk"
    [[ "$action" == preserved ]] && mv -f "$dep" "$dep.local" && chmod +x "$dep.local"
    cp -f "$src" "$dep"
    chmod +x "$dep"
  fi
  printf '%s\n' "$action"
}
