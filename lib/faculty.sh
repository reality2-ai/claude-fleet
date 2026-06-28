# shellcheck shell=bash
# faculty.sh — the FACULTY-ADAPTER contract (docs/FACULTY-ADAPTER-CONTRACT.md) as a
# SEAM over the current implementation.
#
# An ENTITY (a fleet member / proto-R2-sentant) MOUNTS swappable AI faculties
# ("brains"). A FACULTY is one provider's brain; a LEAF is a running instance of it.
# This file names the verbs an adapter must implement so the entity layer can mount,
# observe, message, and fail over brains without caring which provider hosts them.
#
# Today there is ONE adapter — `cli-tmux` — and every action verb delegates VERBATIM
# to the pre-existing function, so this file changes NO behaviour (a pure refactor
# behind a seam, exactly like transport.sh). Future adapters (Claude background
# sessions, a Codex app-server daemon, a local lmstudio body) become additional
# branches under each verb, selected by $FLEET_FACULTY_ADAPTER; nothing above the
# seam changes. See ADR-002 (docs/ADR-002-multibrained-entity-fleet.md).
#
# Requires: registry.sh + tmux.sh + provider.sh + comms.sh + transport.sh sourced.

# Which adapter hosts the brains. Only `cli-tmux` is implemented; an unknown value
# falls back to it so a typo can never silently drop the oversight wire.
FLEET_FACULTY_ADAPTER="${FLEET_FACULTY_ADAPTER:-cli-tmux}"

# --- capability declaration --------------------------------------------------
# What each adapter can do (verified 2026-06-29; see the matrix in
# docs/FACULTY-ADAPTER-CONTRACT.md). The entity layer queries these so it never
# promises a body an adapter can't keep. An UNKNOWN capability is FALSE (fail safe).
#
# `cli-tmux` is today's runtime (a provider CLI in a tmux window): durable+attachable
# via resume/tmux, but liveness/delivery are screen-scraped (not native) and there is
# no event stream. `claude-bg` / `codex-daemon` are the FUTURE native adapters whose
# richer capabilities are recorded here as ready-to-switch data, not yet wired.
_faculty_caps_cli_tmux="durable_body attachable headless_answer native_tui unattended_perms"
_faculty_caps_claude_bg="durable_body attachable headless_answer native_tui unattended_perms native_liveness native_delivery event_stream worktree_isolation"
_faculty_caps_codex_daemon="durable_body attachable headless_answer native_tui unattended_perms native_liveness native_delivery event_stream worktree_isolation"

# faculty_capability <cap> [adapter]  → exit 0 (true) / 1 (false)
faculty_capability() {
  local cap="$1" adapter="${2:-$FLEET_FACULTY_ADAPTER}" var list
  # cli-tmux gains NATIVE dead-detection (#{pane_dead}) once dead panes are kept
  # (FLEET_TMUX_REMAIN_ON_EXIT=on) — reflect that dynamically rather than claiming it
  # unconditionally for the default config (where liveness is still mtime/window-based).
  if [[ "$cap" == native_liveness && "$adapter" == cli-tmux && "${FLEET_TMUX_REMAIN_ON_EXIT:-off}" == on ]]; then
    return 0
  fi
  var="_faculty_caps_${adapter//-/_}"
  list="${!var:-}"
  [[ " $list " == *" $cap "* ]]
}

# faculty_capabilities [adapter]  → print the adapter's true capabilities (space-sep)
faculty_capabilities() {
  local adapter="${1:-$FLEET_FACULTY_ADAPTER}" var
  var="_faculty_caps_${adapter//-/_}"
  printf '%s\n' "${!var:-}"
}

# --- lifecycle ---------------------------------------------------------------
# mount/resume a brain for an entity. The cli-tmux adapter's start function already
# resumes from run/<id>.session when present, else seeds fresh — so mount and resume
# are the same call today; a durable native adapter may split them later.
faculty_mount()  { case "$FLEET_FACULTY_ADAPTER" in cli-tmux|*) fleet_tmux_start_child "$@" ;; esac; }
faculty_resume() { faculty_mount "$@"; }
faculty_unmount(){ case "$FLEET_FACULTY_ADAPTER" in cli-tmux|*) fleet_tmux_stop_child "$@" ;; esac; }

# liveness of the entity's brain: live|idle|dead|stopped|failed (+ throttled/exhausted
# surfaced separately via the comms helpers the doctor uses).
faculty_liveness(){ case "$FLEET_FACULTY_ADAPTER" in cli-tmux|*) fleet_liveness "$@" ;; esac; }

# --- work --------------------------------------------------------------------
# deliver queued mail to the entity's brain (routes through the transport seam, whose
# only branch today IS fleet_drain_inbox/fleet_inject).
faculty_deliver(){ case "$FLEET_FACULTY_ADAPTER" in cli-tmux|*) transport_deliver "$@" ;; esac; }

# one-shot forked answer that does NOT disturb the live body (the `ask` responder).
# Isolation is the adapter's responsibility; a native adapter does it via a worktree
# (structurally fixing the live-checkout-write hazard).
faculty_headless_answer(){ case "$FLEET_FACULTY_ADAPTER" in cli-tmux|*) fleet_agent_headless_answer "$@" ;; esac; }

# spawn_tool — a brain's bounded sub-task as an ephemeral leaf (native subagents),
# one level DOWN from the brain. Arrives with the native adapters.
faculty_spawn_tool(){ warn "faculty: spawn_tool not implemented by adapter '$FLEET_FACULTY_ADAPTER'"; return 2; }

# --- oversight & observation -------------------------------------------------
# attach-through: give a human the brain's own native TUI, where attachable. Keeps
# the rich formatted CLI at zero rebuild cost. (The interactive front-end remains
# cmd_attach; this is the capability-gated seam it will adopt.)
faculty_attach(){
  local id="$1"
  faculty_capability attachable || { warn "faculty: adapter '$FLEET_FACULTY_ADAPTER' is not attachable"; return 1; }
  case "$FLEET_FACULTY_ADAPTER" in
    cli-tmux|*)
      fleet_tmux_has_window "$id" || { warn "faculty: no live window for '$id'"; return 1; }
      fleet_tmux select-window -t "$FLEET_TMUX_SESSION:$id" 2>/dev/null || true
      ;;
  esac
}

# stream — normalized event stream for leaves where event_stream but not native_tui
# (ephemeral tools; future cloud/API leaves). Rendered as a COARSE entity view, never
# a fake terminal (docs/ENTITY-MEMORY + ADR-002 §7d). Not implemented by cli-tmux;
# today observation is faculty_attach + the coarse event log (fleet logs).
faculty_stream(){ warn "faculty: stream not implemented by adapter '$FLEET_FACULTY_ADAPTER'"; return 2; }

# recall — LAZY retrieval from the entity's durable memory (docs/ENTITY-MEMORY.md):
# the bounded HEAD (.fleet/memory/<id>.md, else the repo-local RESUME.md). Token-frugal
# by design — returns the head, never a transcript. The log-delta + repo-grep stages
# land with the memory store; this is the head-read floor. (query arg reserved.)
faculty_recall(){
  local id="$1" head cwd
  head="$STATE_DIR/memory/$id.md"
  if [[ ! -f "$head" ]]; then
    cwd="$(fleet_state_get "$id" '.cwd' "")"
    [[ -n "$cwd" && "$cwd" != "null" ]] && head="$cwd/${FLEET_RESUME_FILE:-RESUME.md}"
  fi
  [[ -f "$head" ]] && cat "$head" || return 1
}
