# shellcheck shell=bash
# macscan.sh — MAC-shaped VALUE detection, shared by the mail path and the test suite.
#
# WHY THIS FILE EXISTS (2026-07-28, supervisor; authorised by Roy).
#
# `fleet send` had NO content scan of any kind. Measured before writing this: 83 unique
# non-allowlisted MAC-shaped values sitting in .fleet/inbox + .fleet/history. Nothing had
# leaked — .fleet/ is gitignored AND is not inside a git repo — so this closes an UNGUARDED
# VECTOR, not an incident.
#
# ★ THE ROOT CAUSE WAS NOT THE MISSING SCAN, IT WAS THAT THE RULE COULD NOT BE CALLED.
# The MAC rule lived INLINE inside hooks/git/pre-push, so no other tool could reuse it.
# Taking the measurement above required COPYING the filter chain — which is exactly the
# "a control must call production, not a copy" defect this fleet has burned itself on before.
# A control nobody can call gets copied or skipped.
#
# ★★ AND THE CLEAN FIX IS NOT AVAILABLE, WHICH IS STATED RATHER THAN QUIETLY WORKED AROUND.
# pre-push CANNOT source this file. It is installed STANDALONE into .git/hooks/pre-push across
# seven repos (see lib/githooks.sh), where lib/ is not at any predictable relative path — that
# self-containment is deliberate and load-bearing. So ONE definition serving both callers is
# impossible today.
#
# What is done instead: this file is the CANONICAL definition, pre-push keeps its own inline
# copy, and tests/smoke.sh asserts the two AGREE AT THE BOUNDARY over a shared fixture corpus
# (behavioural equivalence, not textual — a text comparison would break on formatting and
# prove nothing about behaviour). The duplication is acknowledged and MECHANICALLY POLICED
# rather than trusted. If they ever diverge, the suite fails.
#
# Rule and allowlist are copied VERBATIM from hooks/git/pre-push (the MAC scan, §3) so the
# equivalence test starts from parity. Do not "improve" one side alone — change both, and let
# the equivalence test prove it.

# fleet_mac_values <text>
#   Prints unique, non-allowlisted, MAC-shaped values from <text>, one per line.
#   Empty output = nothing found. Never fails: a no-match grep exits 1 and that is NOT an error.
fleet_mac_values() {
  local text="${1:-}"
  # NOTE ON SHAPE: herestrings, not `printf | grep`, for the first stage. A previous defect in
  # this repo had `printf '%s' "$BIG" | grep -q` take SIGPIPE(141) under `pipefail` when grep
  # exited early, turning a match into a false failure. `grep -o` reads to EOF so it could not
  # bite here — the herestring removes the class anyway rather than relying on that argument.
  grep -oiE '\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b' <<<"$text" \
    | grep -viE '^(02:|aa:bb:cc:|de:ad:be:ef)' \
    | grep -vxiE '00:00:00:00:00:00|ff:ff:ff:ff:ff:ff|11:22:33:44:55:66' \
    | grep -vxiE '00:00:00:00:00:[0-9a-f]{2}' \
    | grep -viE ':00:00:00$' \
    | sort -u || true
}

# fleet_mac_warn <text> [context]
#   Warns on stderr if <text> carries MAC-shaped values. ALWAYS returns 0.
#
# ★ WARN, NEVER BLOCK — a DECLARED permissive default, argued rather than inherited:
#   · Mail NEVER publishes. .fleet/ is gitignored and not in a repo, so this path has no
#     publication boundary to defend. The risk it addresses is PROPAGATION — a value copied
#     OUT of mail into a doc that does get pushed — and pre-push already guards that boundary
#     (it refused the supervisor's own leak on 2026-07-27).
#   · So this is ERROR-DEFENCE, NOT A CONTROL. It stops an honest paste. It stops nobody
#     determined, and it MUST NOT be recorded as closing the leak class — labelling a
#     mitigation as security is how it becomes a believed control.
#   · A gate whose false positives block REMEDIATION is worse than no gate at that moment.
#     Blocking mail can wedge a lane mid-task, for a threat a downstream gate already catches.
#
# It reports the COUNT and the OUI (vendor prefix) only — never a device-unique value — so the
# warning itself cannot become the leak it is warning about.
fleet_mac_warn() {
  local text="${1:-}" ctx="${2:-message}" macs n first oui
  [[ "${FLEET_MAC_SCAN:-on}" == "off" ]] && return 0
  macs="$(fleet_mac_values "$text")"
  [[ -n "$macs" ]] || return 0
  n="$(grep -c . <<<"$macs" || true)"
  IFS=$'\n' read -r first _ <<<"$macs"
  oui="${first%:*:*:*}"
  printf 'fleet: WARNING — %s carries %s real-looking MAC value(s) (first OUI %s:…). Refer by LABEL, not value. Mail was DELIVERED; this is a warning, not a block. FLEET_MAC_SCAN=off to silence.\n' \
    "$ctx" "$n" "$oui" >&2
  return 0
}
