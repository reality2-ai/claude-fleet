#!/usr/bin/env bash
# docs.sh — documentation drift guard.
#
# 101 of this repo's 137 FLEET_* variables were undocumented when this file was written.
# A knob nobody can discover cannot be tuned or turned off, which makes the tool
# unreproducible for anyone who is not the person who wrote it — and the count only ever
# grows, because adding a variable is a one-line change and documenting it is not.
#
# This guard closes the CONTEXT AND TOKEN cluster, the one that governs what a fleet
# costs to run: everything matching COMPACT / CTX / OUTPUT / CLOCK in shipping code must
# appear in docs/OPERATIONS.md. The list is DERIVED FROM THE CODE, not hard-coded here,
# so a new knob in that cluster fails this test until it is written up.
#
# The rest of the 101 are not covered yet. That is a known, stated debt rather than a
# silent one — extend PATTERN below as each further cluster gets documented.
#
# Requires: bash >= 4, grep.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/docs/OPERATIONS.md"
PATTERN='FLEET_(COMPACT|CTX|OUTPUT|CLOCK)[A-Z0-9_]*'

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }

section "1. the context/token cluster is documented"
mapfile -t VARS < <(grep -rhoE "$PATTERN" "$ROOT/bin/fleet" "$ROOT"/lib/*.sh "$ROOT"/hooks/*.sh 2>/dev/null | sort -u)
if (( ${#VARS[@]} >= 10 )); then ok "found ${#VARS[@]} cluster variables in shipping code"; else no "only ${#VARS[@]} cluster variables found — is the pattern still right?"; fi

_missing=()
for v in "${VARS[@]}"; do
  if grep -q "$v" "$DOC" 2>/dev/null; then ok "documented: $v"; else no "UNDOCUMENTED: $v"; _missing+=("$v"); fi
done

section "2. controls"
# Without this, "every variable was found" is equally consistent with "the grep matches
# anything", and the section above would stay green over an empty or deleted doc file.
if ! grep -q 'FLEET_THIS_DOES_NOT_EXIST' "$DOC" 2>/dev/null; then ok "control: a fabricated variable is NOT found in the doc"; else no "the doc matches a name that does not exist"; fi
if [[ -s "$DOC" ]]; then ok "the documentation file is non-empty"; else no "documentation file missing or empty"; fi
# The defaults must be stated, not just the names: a knob you cannot see the default of
# still cannot be reasoned about before you change it.
# The default sits in the SAME table row as the name, not the line after it.
for v in FLEET_COMPACT_AT_PCT FLEET_COMPACT_HARD_PCT FLEET_OUTPUT_BUDGET_BYTES FLEET_CLOCK_DUE_H; do
  if grep "\`$v\`" "$DOC" 2>/dev/null | grep -qE '\|[[:space:]]*`(on|off|[0-9]+)`[[:space:]]*\|'; then ok "default stated for $v"; else no "no default stated for $v"; fi
done

section "3. the debt is stated, not hidden"
_all="$(grep -rhoE 'FLEET_[A-Z0-9_]+' "$ROOT/bin/fleet" "$ROOT"/lib/*.sh "$ROOT"/hooks/*.sh 2>/dev/null | sort -u | wc -l)"
_doc="$(grep -rhoE 'FLEET_[A-Z0-9_]+' "$ROOT"/docs/*.md "$ROOT/README.md" 2>/dev/null | sort -u | wc -l)"
printf '  note  %s FLEET_* variables in shipping code, %s appear somewhere in docs/ or README\n' "$_all" "$_doc"
printf '  note  this guard covers the %s in the context/token cluster; the remainder is open debt\n' "${#VARS[@]}"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( ${#_missing[@]} )) && printf 'undocumented: %s\n' "${_missing[*]}"
exit $(( fail > 0 ))
