# shellcheck shell=bash
# transport.sh — a thin SEAM in front of the message/liveness transport, so the
# four places that touch tmux directly route through named verbs instead. This
# is the down-payment on a future native-primitives migration (a branch swap,
# NOT a rewrite): when a native transport lands it becomes a second branch under
# each verb, selected by $FLEET_TRANSPORT, and nothing else changes.
#
# IMPORTANT: today the ONLY implementation is `tmux`, and each `tmux` branch
# calls the EXACT pre-existing function verbatim — this file changes NO
# behaviour. It is a pure refactor behind a seam.
#
# Requires: registry.sh + tmux.sh + comms.sh sourced (the verbs delegate to them).

# Which transport to use. Only `tmux` is implemented; an unknown value falls
# back to tmux so a typo can never silently drop the fleet's oversight wire.
FLEET_TRANSPORT="${FLEET_TRANSPORT:-tmux}"

# transport_register <id> — record which transport hosts this child. Called at
# spawn. Creates-only-friendly: never overwrites a more specific value.
transport_register() {
  local id="$1"
  case "$FLEET_TRANSPORT" in
    tmux|*)
      fleet_state_jq "$id" --arg t "tmux" '.transport = (.transport // $t)' >/dev/null 2>&1 || true
      ;;
  esac
}

# transport_liveness <id> — is the child present on the transport? (the "still
# here" signal that enumeration + liveness both lean on). Prints nothing; exit
# status only, mirroring fleet_tmux_has_window.
transport_liveness() {
  local id="$1"
  case "$FLEET_TRANSPORT" in
    tmux|*) fleet_tmux_has_window "$id" ;;
  esac
}

# transport_ids — enumerate the ids the transport currently hosts (one per line).
# This is the enumeration call site's ground-truth source.
transport_ids() {
  case "$FLEET_TRANSPORT" in
    tmux|*) fleet_tmux_window_ids ;;
  esac
}

# transport_enqueue <to> <from> <text> <hops> <kind> — push one message onto the
# child over the transport (the drain's inject step). Returns non-zero if it
# could not be confirmed delivered.
transport_enqueue() {
  case "$FLEET_TRANSPORT" in
    tmux|*) fleet_inject "$@" ;;
  esac
}

# transport_deliver <to> [force] — deliver all queued mail to <to> over the
# transport (the high-level deliver verb). Returns 0 if nothing is left queued.
transport_deliver() {
  case "$FLEET_TRANSPORT" in
    tmux|*) fleet_drain_inbox "$@" ;;
  esac
}