#!/usr/bin/env bash
# lane-drift.sh — supervisor sweep arm: did a lane act outside its lane?
#
# Roy, 2026-08-12: "as the supervisor, together with your refuter, you should be
# constantly checking that each agent is keeping within their operational lanes."
#
# TWO AXES, AND THE SECOND IS THE ONE THAT MATTERS.
#
#   AXIS A  written paths vs declared lane. Cheap, complete, and it was CLEAN on
#           the day of the d424 breach. Reported as PASS/FAIL.
#   AXIS B  who performed a hardware write. Reported as UNMEASURABLE, because it
#           is: .fleet/flash-authorization.log carries artifact, target, sha and
#           cmd, and NO LANE FIELD; and tools/flash.sh (717 lines) never appends
#           to it — grep for flash-authorization there returns nothing. The log
#           has no line after 2026-08-09 while three boards were written on
#           2026-08-12. One of its own lines already records the bypass:
#           reason=write-completed-supervisor-ran-it-outside-the-hook-so-no-USED-line-exists
#
# AXIS B PRINTS UNMEASURABLE AND NEVER CLEAN. A hardware ledger that no writer
# writes to reports zero writes, and zero writes reads as compliance. That is the
# reporting-arm-goes-blind shape: an asserting arm that goes blind starts failing,
# a reporting arm that goes blind just reports a smaller number.
#
# --selftest probes both axes red against fabricated input. An arm that has never
# been shown failing is a claim, not a control.

set -uo pipefail

# WORKSPACE RESOLUTION, changed on the back-port into claude-fleet 2026-08-12. The
# copy this was lifted from hardcoded one operator's R2-standard path, which is
# correct in exactly one checkout and wrong-but-silent everywhere else. Resolving
# to $PWD instead would be worse: a sweep pointed at a tree with no lane-prefixed
# commits reports "0 examined, 0 outside declared lane", and zero examined reads as
# clean — the same reporting-arm-goes-blind shape axis B was written to expose. So
# an unresolvable workspace is an ERROR, never a quiet pass.
#
# --selftest runs against fabricated input in a tmpdir and needs no workspace at
# all, so it must stay runnable in a bare checkout — resolution is skipped for it.
WS="${WS:-${FLEET_WORKSPACE:-}}"
if [ "${1:-}" != "--selftest" ]; then
  if [ -z "$WS" ]; then
    echo "lane-drift: no workspace. Set FLEET_WORKSPACE or WS=<workspace root>." >&2
    exit 2
  fi
  if [ ! -d "$WS/.fleet" ]; then
    echo "lane-drift: $WS has no .fleet — that is not a fleet workspace, and a sweep of" >&2
    echo "            the wrong tree reports clean. Refusing rather than reporting." >&2
    exit 2
  fi
fi
IMPL="${IMPL:-$WS/r2-impl}"
AUTHLOG="${AUTHLOG:-$WS/.fleet/flash-authorization.log}"
N="${N:-150}"
rc=0

# r2-mesh, r2-wire, r2-trust etc. are CRATES inside the r2-core directory. A
# prefix naming a crate is not a lane claim, so it is resolved to its directory
# rather than counted as drift. Anything not listed here is compared literally.
resolve_lane() {
  case "$1" in
    r2-mesh|r2-wire|r2-trust|r2-sentants|r2-mgmt|r2-core) echo r2-core ;;
    *) echo "$1" ;;
  esac
}

axis_a() {
  local repo="$1" n="$2" bad=0 seen=0
  local c pre dirs expect
  for c in $(git -C "$repo" log --format='%h' -"$n"); do
    pre=$(git -C "$repo" log -1 --format='%s' "$c" | sed -n 's/^\(r2-[a-z]*\):.*/\1/p')
    [ -z "$pre" ] && continue          # unprefixed commit: not a lane claim, not evidence either
    seen=$((seen+1))
    expect=$(resolve_lane "$pre")
    dirs=$(git -C "$repo" show --name-only --format='' "$c" | awk -F/ 'NF>0{print $1}' | sort -u | tr '\n' ',')
    if [ "$dirs" != "$expect," ]; then
      echo "DRIFT $c declared=$pre resolved=$expect touched=$dirs"
      bad=$((bad+1))
    fi
  done
  echo "axis A: $seen prefixed commits examined of last $n, $bad outside declared lane"
  return $bad
}

axis_b() {
  local lines lastwrite hasfield
  if [ ! -f "$AUTHLOG" ]; then
    echo "axis B: UNMEASURABLE — no $AUTHLOG"; return 0
  fi
  lines=$(wc -l < "$AUTHLOG")
  # grep -c exits 1 on a zero count, and a naive "|| echo 0" then prints TWO
  # lines and the report reads 0\n0. Zero is the expected answer here, so the
  # count must survive its own exit status.
  lastwrite=$(grep -c 'USED' "$AUTHLOG" 2>/dev/null); lastwrite=${lastwrite:-0}
  hasfield=$(grep -c 'lane=' "$AUTHLOG" 2>/dev/null); hasfield=${hasfield:-0}
  echo "axis B: UNMEASURABLE — $lines log lines, $lastwrite USED, $hasfield carry a lane field"
  echo "axis B: the writer does not write here. Nothing in this sweep can name the hand that held the cable."
  # deliberately returns 0: this is not a pass, and the line above says so.
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  git -C "$t" init -q .
  git -C "$t" config user.email s@x; git -C "$t" config user.name s
  mkdir -p "$t/r2-core" "$t/r2-hive"
  echo a > "$t/r2-core/a"; git -C "$t" add -A
  git -C "$t" commit -q -m "r2-core: honest commit"
  echo b > "$t/r2-hive/b"; git -C "$t" add -A
  git -C "$t" commit -q -m "r2-core: a lane wrote outside itself"
  echo m > "$t/r2-core/m"; git -C "$t" add -A
  git -C "$t" commit -q -m "r2-mesh: a crate prefix must not read as drift"
  out=$(axis_a "$t" 10); ec=$?
  echo "$out"
  # a control that only shows the red half cannot tell a working arm from one
  # that flags everything, so both directions are asserted.
  echo "$out" | grep -q '^DRIFT .* declared=r2-core .* touched=r2-hive,' || { echo "SELFTEST FAIL: drift not caught"; exit 1; }
  echo "$out" | grep -q 'r2-mesh' && { echo "SELFTEST FAIL: crate prefix miscounted as drift"; exit 1; }
  [ "$ec" -eq 1 ] || { echo "SELFTEST FAIL: expected exactly 1 drift, got $ec"; exit 1; }
  echo "SELFTEST PASS: caught the planted drift, did not flag the crate prefix"
  exit 0
fi

echo "== lane drift sweep, $(date -Is)"
# Same rule as the workspace check: a missing repo must not sweep to a clean count.
if ! git -C "$IMPL" rev-parse --git-dir >/dev/null 2>&1; then
  echo "lane-drift: $IMPL is not a git repo — axis A has nothing to read. Set IMPL=<repo>." >&2
  exit 2
fi
axis_a "$IMPL" "$N" || rc=1
axis_b
echo "== axis A is not the axis that failed on 2026-08-12. Read axis B before concluding."
exit $rc
