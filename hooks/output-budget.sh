#!/usr/bin/env bash
# output-budget.sh — PostToolUse hook. Keeps a single fat tool result from taking up
# permanent residence in a worker's context window.
#
# WHY THIS EXISTS (measured, r2-hive lane, 29,364 turns of its own transcript):
#   mean context re-processed per turn      406,780 tokens
#   total input re-processed, one lane      11.94 billion tokens
#   tool results over 4KB                   4.7% of results, 45% of all result bytes
# A 50KB command output is ~12k tokens. It is read ONCE by the agent and then re-sent
# on every subsequent turn until the next compaction — several hundred turns later. The
# cost of a tool result is not what it costs to receive; it is that number multiplied by
# how long it then sits in the window.
#
# NOT TRUNCATION — SPILL. Silent truncation is the exact defect class this fleet keeps
# killing: a token win bought with information loss, where the dropped middle is
# precisely the failing assertion. So nothing is destroyed. The full output is written
# to disk, the head and tail (where errors and summaries live) stay inline, and the
# elision states exactly how many lines and bytes were moved and where to read them.
# Information is DEFERRED, never lost — the agent can Read the spill file if the middle
# turns out to matter, and pays for it only then.
#
# Fails open, always: any error, any unparseable payload, any unwritable spill path
# leaves the output completely untouched. A hook that eats a tool result is worse than
# a hook that saves nothing.
#
#   FLEET_OUTPUT_BUDGET=off         disable entirely
#   FLEET_OUTPUT_BUDGET_BYTES=4000  inline budget before spilling (head+tail share it)
#   FLEET_OUTPUT_SPILL_KEEP=200     spill files to retain per workspace
set -uo pipefail

[[ "${FLEET_OUTPUT_BUDGET:-on}" == "off" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat 2>/dev/null || true)"
[[ -n "$payload" ]] || exit 0

cwd="$(printf '%s' "$payload" | jq -r '.cwd // .working_directory // ""' 2>/dev/null)" || exit 0
[[ -n "$cwd" ]] || cwd="$PWD"

# Scope to a fleet workspace, so a user-level install never rewrites output in an
# unrelated project. Cheap walk-up, no external commands (same idiom as auto-approve).
ws=""; d="$cwd"
while [[ -n "$d" ]]; do
  [[ -d "$d/.fleet" ]] && { ws="$d"; break; }
  [[ "$d" == "/" ]] && break
  d="${d%/*}"; [[ -z "$d" ]] && d="/"
done
[[ -n "$ws" ]] || exit 0

budget="${FLEET_OUTPUT_BUDGET_BYTES:-4000}"
[[ "$budget" =~ ^[0-9]+$ ]] || exit 0
(( budget >= 1000 )) || exit 0        # a budget too small to hold a head and a tail is a bug, not a setting

# The Bash tool reports {stdout, stderr, ...}; other tools report a bare string. Render
# an object to the text the model would have seen, so the two shapes share one path.
text="$(printf '%s' "$payload" | jq -r '
  (.tool_response // .tool_result // .output // empty) as $r
  | if ($r|type) == "string" then $r
    elif ($r|type) == "object" then
      [ ($r.stdout // empty), ($r.stderr // empty) ] | map(select(. != "" and . != null)) | join("\n")
    else empty end' 2>/dev/null)" || exit 0
[[ -n "$text" ]] || exit 0

nbytes=${#text}
(( nbytes > budget )) || exit 0          # under budget: leave it completely alone

tool="$(printf '%s' "$payload" | jq -r '.tool_name // .tool // "tool"' 2>/dev/null)"
[[ -n "$tool" ]] || tool=tool

# --- spill the whole thing to disk BEFORE eliding anything ---------------------
# If this write fails the hook exits 0 and the output passes through at full size.
# Trading a token saving for an unreachable middle is the one outcome not on offer.
spill_dir="$ws/.fleet/spill"
mkdir -p "$spill_dir" 2>/dev/null || exit 0
ts="$(date +%Y%m%d-%H%M%S)"
spill="$spill_dir/${FLEET_CHILD_ID:-adhoc}-${tool}-${ts}-$$.txt"
printf '%s' "$text" > "$spill" 2>/dev/null || exit 0

# Retain a bounded number of spills; the oldest are the least likely to be wanted.
keep="${FLEET_OUTPUT_SPILL_KEEP:-200}"
[[ "$keep" =~ ^[0-9]+$ ]] || keep=200
# shellcheck disable=SC2012  # filenames here are hook-generated and contain no newlines
ls -1t "$spill_dir" 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r old; do
  rm -f "$spill_dir/$old" 2>/dev/null || true
done

# --- head + tail, with an honest account of the gap ---------------------------
# Split the budget between the two ends: a command's verdict is at the bottom (exit
# status, failure summary, last error) and its subject at the top (what ran, headers).
# The middle of a 50KB dump is where repetition lives — and where a decisive line
# might also live, which is why the spill path is quoted rather than assumed dispensable.
#
# HEAD+TAIL ALONE WAS NOT ENOUGH, AND THE ATTACK THAT SHOWED IT IS WORTH RECORDING.
# Replaying 161 real over-budget results from a live lane's transcript through this
# elision: **10.6% had a decisive line — an error, a failure, a verdict — that existed
# ONLY in the elided middle**, with nothing in either end to hint at it. Two classes
# accounted for all of them, and both are line-oriented output where every line is a
# record and there is no verdict at the bottom:
#   `fleet inbox`  7/27   — each peer message is its own finding
#   grep results   8/68   — the match you wanted is at whatever line it is at
# Carrying the decisive middle lines inline drops that to 0/161, at a cost of 3
# percentage points of saving (53% -> 50%). Cheap, and it is the difference between a
# compression and a capability loss.
half=$(( budget / 2 ))
head_txt="${text:0:half}"
tail_txt="${text: -half}"
middle_txt="${text:half:$(( nbytes - 2 * half ))}"

# Deliberately broad — a false highlight costs one line, a missed one costs the finding.
_decisive='(error|errors|fatal|panic|failed|failure|assert|traceback|exception|denied|refused|rejected|conflict|cannot|unable to|not found|undefined|unresolved|warning|deprecated|timeout|timed out|abort|segfault|core dumped|exit code|exit status|no such file)|^(ok|not ok) |tests? (passed|failed)|^(---|\+\+\+) |^@@ '
_hl_max="${FLEET_OUTPUT_HL_MAX:-12}"
[[ "$_hl_max" =~ ^[0-9]+$ ]] || _hl_max=12
hl_total="$(printf '%s' "$middle_txt" | grep -ciE "$_decisive" 2>/dev/null || true)"
[[ "$hl_total" =~ ^[0-9]+$ ]] || hl_total=0
highlights=""
if (( hl_total > 0 && _hl_max > 0 )); then
  highlights="$(printf '%s' "$middle_txt" | grep -iE "$_decisive" 2>/dev/null | head -n "$_hl_max" | cut -c1-200)"
  if (( hl_total > _hl_max )); then
    # No silent caps. If the highlights are themselves truncated, say by how much.
    highlights="$highlights
  … and $(( hl_total - _hl_max )) further flagged line(s) in the middle — read the spill file."
  fi
  highlights="
FLAGGED LINES RECOVERED FROM THE ELIDED MIDDLE ($hl_total matched; showing up to $_hl_max, truncated to 200 cols):
$highlights
"
fi
total_lines="$(printf '%s' "$text" | wc -l | tr -d ' ')"
head_lines="$(printf '%s' "$head_txt" | wc -l | tr -d ' ')"
tail_lines="$(printf '%s' "$tail_txt" | wc -l | tr -d ' ')"
gap_bytes=$(( nbytes - ${#head_txt} - ${#tail_txt} ))
gap_lines=$(( total_lines - head_lines - tail_lines ))
(( gap_lines < 0 )) && gap_lines=0

new="$(printf '%s\n\n[fleet output-budget] %s bytes / %s lines elided from the MIDDLE of this result (it was %s bytes; head and tail are verbatim above and below).\nNOTHING WAS DISCARDED — the complete output is at:\n  %s\nRead that file if the middle matters; do not re-run the command to recover it.\n%s\n%s' \
  "$head_txt" "$gap_bytes" "$gap_lines" "$nbytes" "$spill" "$highlights" "$tail_txt")"

jq -nc --arg o "$new" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",updatedToolOutput:$o}}' 2>/dev/null || exit 0
exit 0
