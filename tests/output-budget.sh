#!/usr/bin/env bash
# output-budget.sh — tests for the PostToolUse output-budget hook.
#
# The hook's whole claim is "smaller context, nothing lost". Both halves are asserted
# here, because only the first half is easy: a hook that simply truncated would pass a
# size check and fail the fleet. So every run also proves the spill file is BYTE-IDENTICAL
# to the original, and that the two ends the agent reasons from survive verbatim.
#
# Two controls that must fire, or the green above means nothing:
#   * outside a .fleet workspace the hook must not touch output at all
#   * when the spill cannot be written the hook must pass the output through WHOLE —
#     a token saving is never worth an unreachable middle
#
# Hermetic: throwaway workspaces, no fleet, no tmux. Requires: bash >= 4, jq.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/output-budget.sh"

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }

WS="$(mktemp -d)"; WS2="$(mktemp -d)"
trap 'rm -rf "$WS" "$WS2"' EXIT
mkdir -p "$WS/.fleet" "$WS2/.fleet"

run() { printf '%s' "$1" | "$HOOK" 2>/dev/null; }
payload() { jq -nc --arg t "$1" --arg c "$2" --arg s "$3" '{tool_name:$t,cwd:$c,tool_response:{stdout:$s}}'; }

# A result far over budget, with unmistakable markers at each end. The markers are what
# prove "verbatim" rather than "approximately preserved".
BIG="HEAD-MARKER-ALPHA"$'\n'
for i in $(seq 1 900); do BIG+="filler line $i ------------------------------------------------------------"$'\n'; done
BIG+="TAIL-MARKER-OMEGA"

section "1. budget threshold"
if [[ -z "$(run "$(payload Bash "$WS" "tiny output")")" ]]; then ok "under budget: output left untouched"; else no "under budget: hook rewrote it"; fi

section "2. over budget: smaller AND lossless"
OUT="$(run "$(payload Bash "$WS" "$BIG")")"
NEW="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedToolOutput // empty' 2>/dev/null)"
if [[ -n "$NEW" ]]; then ok "over budget: hook returned updatedToolOutput"; else no "over budget: no rewrite emitted"; fi
if (( ${#NEW} < ${#BIG} )); then ok "result shrank (${#BIG} -> ${#NEW} bytes)"; else no "result did not shrink"; fi
if grep -q 'HEAD-MARKER-ALPHA' <<<"$NEW"; then ok "head preserved verbatim"; else no "head lost"; fi
if grep -q 'TAIL-MARKER-OMEGA' <<<"$NEW"; then ok "tail preserved verbatim (where the verdict line lives)"; else no "tail lost"; fi
if grep -q 'elided from the MIDDLE' <<<"$NEW"; then ok "elision is announced, never silent"; else no "elision not announced"; fi

SPILL="$(grep -oE '/[^ ]*/\.fleet/spill/[^ ]+\.txt' <<<"$NEW" | head -1)"
if [[ -n "$SPILL" && -f "$SPILL" ]]; then ok "spill path is cited and exists"; else no "spill path missing or wrong ('$SPILL')"; fi
# THE assertion. Everything else is comfort; this is the one that says nothing was lost.
if [[ -n "$SPILL" && "$(cat "$SPILL" 2>/dev/null)" == "$BIG" ]]; then ok "spill is byte-identical to the original"; else no "spill differs from the original — INFORMATION LOST"; fi

section "2b. the attack head+tail alone failed"
# Replaying 161 real over-budget results from a live transcript, 10.6% had their only
# decisive line in the elided middle — `fleet inbox` (7/27) and grep output (8/68),
# both line-oriented with no verdict at the bottom. This is that shape, minimised: a
# failure buried mid-stream with entirely innocuous ends.
MID="START-OF-OUTPUT"$'\n'
for i in $(seq 1 400); do MID+="routine line $i ------------------------------------------------------------"$'\n'; done
MID+="fatal: refusing to merge unrelated histories"$'\n'
for i in $(seq 1 400); do MID+="routine line $i ------------------------------------------------------------"$'\n'; done
MID+="END-OF-OUTPUT"
MOUT="$(run "$(payload Bash "$WS" "$MID")")"
MNEW="$(printf '%s' "$MOUT" | jq -r '.hookSpecificOutput.updatedToolOutput // empty' 2>/dev/null)"
if grep -q 'fatal: refusing to merge unrelated histories' <<<"$MNEW"; then ok "decisive middle line is recovered inline"; else no "DECISIVE MIDDLE LINE LOST — the attack still lands"; fi
if grep -q 'FLAGGED LINES RECOVERED' <<<"$MNEW"; then ok "recovered lines are labelled as coming from the middle"; else no "recovered lines not labelled"; fi
if (( ${#MNEW} < ${#MID} )); then ok "still shrank despite carrying highlights (${#MID} -> ${#MNEW})"; else no "highlights defeated the saving"; fi
# No silent caps: more flagged lines than the cap must announce the remainder.
MANY="START"$'\n'
for i in $(seq 1 60); do MANY+="line $i: error: something went wrong number $i ------------------------------"$'\n'; done
for i in $(seq 1 400); do MANY+="routine padding line $i ---------------------------------------------------"$'\n'; done
MANY+="END"
MANYOUT="$(run "$(payload Bash "$WS" "$MANY")" | jq -r '.hookSpecificOutput.updatedToolOutput // empty' 2>/dev/null)"
if grep -qE 'further flagged line\(s\) in the middle' <<<"$MANYOUT"; then ok "over the highlight cap: the remainder is announced, not silently dropped"; else no "highlight cap is silent"; fi

section "3. controls (these must fire, or section 2 proves nothing)"
if [[ -z "$(printf '%s' "$(payload Bash / "$BIG")" | "$HOOK" 2>/dev/null)" ]]; then ok "no .fleet workspace: output untouched"; else no "rewrote output outside a fleet workspace"; fi
# A regular FILE where the spill directory must go: mkdir -p fails, so the hook must
# choose the whole output over a saving it cannot make safely.
: > "$WS2/.fleet/spill"
if [[ -z "$(run "$(payload Bash "$WS2" "$BIG")")" ]]; then ok "fail-open: unwritable spill -> output passes through whole"; else no "ate the output when the spill failed"; fi
if [[ -z "$(run "$(jq -nc --arg c "$WS" --arg s "$BIG" '{tool_name:"Bash",cwd:$c}')")" ]]; then ok "missing tool_response: untouched"; else no "rewrote a payload with no tool_response"; fi

section "4. payload shapes"
STR="$(run "$(jq -nc --arg c "$WS" --arg s "$BIG" '{tool_name:"Grep",cwd:$c,tool_response:$s}')")"
if [[ -n "$(printf '%s' "$STR" | jq -r '.hookSpecificOutput.updatedToolOutput // empty' 2>/dev/null)" ]]; then ok "bare-string tool_response handled"; else no "string-shaped tool_response not handled"; fi

section "5. wiring"
if grep -q 'output-budget.sh' "$ROOT/bin/fleet"; then ok "fleet init wires the hook"; else no "fleet init does not wire the hook"; fi
# Claude-only by design: updatedToolOutput is a Claude Code hook contract and codex has
# no verified equivalent. Assert the codex renderer does NOT wire it.
if ! sed -n '/_render_codex_hooks_json/,/^}/p' "$ROOT/bin/fleet" | grep -q 'output-budget.sh'; then ok "codex hooks do NOT wire it (unverified contract)"; else no "codex hooks wire an unverified reply shape"; fi
# Assert the SHIPPING surface — the .gitignore `fleet init` generates — not this
# checkout's own `.fleet/.gitignore`, which is untracked runtime state that does not
# exist in a fresh clone. The first version of this line read that file and passed
# only because the developer's workspace happened to have one; on a clean worktree it
# failed, which is what a test asserting on local state always does eventually.
if sed -n '/claude-fleet runtime state/,/^GI$/p' "$ROOT/bin/fleet" | grep -q '^/spill/$'; then ok "fleet init's generated .gitignore excludes the spill directory"; else no "generated .gitignore would commit spill files"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
exit $(( fail > 0 ))
