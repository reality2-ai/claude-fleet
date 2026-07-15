#!/usr/bin/env bash
# githooks.sh — install + drift-check the repo-level git hooks (hooks/git/*).
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

# The source-of-truth hook shipped by THIS checkout.
#
# ⚠ SEQUENCING TRAP: TOOL_ROOT follows the `fleet` symlink back to whatever checkout it
# points at, on whatever branch that checkout happens to be on — NOT origin/master. So the
# hook you deploy is the hook in the running checkout's working tree. Check out the branch
# you intend to deploy FIRST. fleet_git_hook_provenance() exists so this is printed on every
# install rather than trusted to memory.
fleet_git_hook_src() { printf '%s\n' "$TOOL_ROOT/hooks/git/pre-push"; }

# A one-line provenance banner for the source checkout: branch, short sha, and whether the
# hook file itself is locally modified (i.e. you are about to deploy uncommitted changes).
fleet_git_hook_provenance() {
  local br sha dirty=""
  br="$(git -C "$TOOL_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  sha="$(git -C "$TOOL_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"
  if ! git -C "$TOOL_ROOT" diff --quiet -- hooks/git/pre-push 2>/dev/null; then
    dirty=" (LOCALLY MODIFIED — deploying uncommitted hook changes)"
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

# Is this pre-push OURS (any version of it) rather than a foreign repo-local hook?
# Marker: the bypass env var, which only our hook defines.
fleet_git_hook_is_ours() { grep -q 'FLEET_SKIP_SECRET_SCAN' "$1" 2>/dev/null; }

# Drift state of one repo's deployed pre-push vs source-of-truth.
# Echoes exactly one of: ok | drift | missing | notgit
fleet_hook_drift_state() {
  local repo="$1" hk dep src
  src="$(fleet_git_hook_src)"
  [[ -f "$src" ]] || { printf 'notgit\n'; return 0; }
  hk="$(fleet_git_hook_dir "$repo")" || { printf 'notgit\n'; return 0; }
  dep="$hk/pre-push"
  [[ -f "$dep" ]] || { printf 'missing\n'; return 0; }
  if [[ "$(sha256sum "$dep" 2>/dev/null | cut -d' ' -f1)" == "$(sha256sum "$src" 2>/dev/null | cut -d' ' -f1)" ]]; then
    printf 'ok\n'
  else
    printf 'drift\n'
  fi
}

# Install the source hook into one repo. Idempotent and safe to re-run.
# $2 = "dry" to report the action without touching anything.
# Echoes one of: current | updated | installed | preserved | notgit
#
# A pre-existing FOREIGN hook is moved to pre-push.local rather than clobbered — our hook
# chains to pre-push.local on exit, so the repo's own hook keeps running. That is why the
# backup name is not .bak: .local is load-bearing, not an archive.
fleet_install_git_hook() {
  local repo="$1" mode="${2:-}" hk dep src action
  src="$(fleet_git_hook_src)"
  [[ -f "$src" ]] || { printf 'notgit\n'; return 1; }
  hk="$(fleet_git_hook_dir "$repo")" || { printf 'notgit\n'; return 0; }

  if [[ -f "$hk/pre-push" ]]; then
    if [[ "$(sha256sum "$hk/pre-push" 2>/dev/null | cut -d' ' -f1)" == "$(sha256sum "$src" 2>/dev/null | cut -d' ' -f1)" ]]; then
      action=current
    elif fleet_git_hook_is_ours "$hk/pre-push"; then
      action=updated
    else
      action=preserved
    fi
  else
    action=installed
  fi

  if [[ "$mode" != dry && "$action" != current ]]; then
    mkdir -p "$hk"
    [[ "$action" == preserved ]] && mv -f "$hk/pre-push" "$hk/pre-push.local" && chmod +x "$hk/pre-push.local"
    cp -f "$src" "$hk/pre-push"
    chmod +x "$hk/pre-push"
  fi
  printf '%s\n' "$action"
}
