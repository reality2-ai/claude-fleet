#!/usr/bin/env bash
# faculty.sh — unit tests for the faculty-adapter seam (lib/faculty.sh).
#
# Verifies the contract surface exists, the capability matrix is correct, the action
# verbs delegate to the pre-existing functions (zero behaviour change), recall reads
# the durable head, and the not-yet-implemented verbs fail honestly.
#
# Hermetic: no real fleet, a throwaway workspace, an unused tmux socket (so liveness
# resolves to "dead" without touching anything). Requires: bash >= 4, jq.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0; fail=0
_grn=$'\033[32m'; _red=$'\033[31m'; _rst=$'\033[0m'
ok() { printf '  %sok%s   %s\n' "$_grn" "$_rst" "$1"; pass=$((pass+1)); }
no() { printf '  %sFAIL%s %s\n' "$_red" "$_rst" "$1"; fail=$((fail+1)); }
section() { printf '\n%s\n' "$1"; }
# assert exit status: want 0 (true) / non-0 (false)
true_()  { if "$@" >/dev/null 2>&1; then ok "$1 [delegated]"; else no "$1"; fi; }   # unused placeholder
istrue() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
isfalse(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then no "$d"; else ok "$d"; fi; }
eq()     { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (got '$2' want '$3')"; fi; }

# --- hermetic env -----------------------------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export TOOL_ROOT="$ROOT"
export FLEET_TMUX_USER_SCOPE=off
export FLEET_TMUX_SOCKET="facultytest$$" FLEET_TMUX_SESSION="facultytest$$"
# path globals (what fleet_load_paths would set), pointed into the temp dir
export WORKSPACE="$TMP/ws"; export STATE_DIR="$WORKSPACE/.fleet"
export CHILDSTATE_DIR="$STATE_DIR/state" RUN_DIR="$STATE_DIR/run" LOG_FILE="$STATE_DIR/log/fleet.log"
export MANIFEST="$STATE_DIR/fleet.toml"
mkdir -p "$CHILDSTATE_DIR" "$RUN_DIR" "$(dirname "$LOG_FILE")" "$STATE_DIR/memory"

# source the libs the way bin/fleet does (functions resolve at call time)
# shellcheck disable=SC1091
for lib in common manifest registry provider tmux comms transport faculty faculty-bg; do
  source "$ROOT/lib/$lib.sh" || { echo "cannot source lib/$lib.sh"; exit 1; }
done

# --- 1. syntax + contract surface -------------------------------------------
section "1. syntax + contract surface"
if bash -n "$ROOT/lib/faculty.sh" 2>/dev/null; then ok "bash -n clean"; else no "bash -n clean"; fi
for v in faculty_capability faculty_capabilities faculty_mount faculty_resume \
         faculty_unmount faculty_liveness faculty_deliver faculty_headless_answer \
         faculty_spawn_tool faculty_attach faculty_stream faculty_recall; do
  if declare -F "$v" >/dev/null 2>&1; then ok "verb defined: $v"; else no "verb MISSING: $v"; fi
done

# --- 2. capability matrix (verified 2026-06-29) -----------------------------
section "2. capability matrix"
istrue  "cli-tmux: durable_body"        faculty_capability durable_body cli-tmux
istrue  "cli-tmux: attachable"          faculty_capability attachable cli-tmux
istrue  "cli-tmux: native_tui"          faculty_capability native_tui cli-tmux
isfalse "cli-tmux: NOT native_delivery" faculty_capability native_delivery cli-tmux
isfalse "cli-tmux: NOT event_stream"    faculty_capability event_stream cli-tmux
istrue  "claude-bg: native_delivery"    faculty_capability native_delivery claude-bg
istrue  "codex-daemon: event_stream"    faculty_capability event_stream codex-daemon
isfalse "unknown cap is false"          faculty_capability no_such_cap cli-tmux
isfalse "unknown adapter is all-false"  faculty_capability durable_body no-such-adapter
eq "default adapter is cli-tmux" "$FLEET_FACULTY_ADAPTER" "cli-tmux"

# --- 3. delegation (zero behaviour change) ----------------------------------
section "3. delegation"
# liveness of an unknown id must equal fleet_liveness's answer ("dead": no doc, no window)
got_f="$(faculty_liveness ghost 2>/dev/null)"; got_l="$(fleet_liveness ghost 2>/dev/null)"
eq "liveness delegates to fleet_liveness" "$got_f" "$got_l"
eq "liveness of unknown id is dead" "$got_f" "dead"
# the verb bodies call the pre-existing functions verbatim
if declare -f faculty_mount   | grep -q 'fleet_tmux_start_child'; then ok "mount → fleet_tmux_start_child"; else no "mount delegation"; fi
if declare -f faculty_unmount | grep -q 'fleet_tmux_stop_child';  then ok "unmount → fleet_tmux_stop_child"; else no "unmount delegation"; fi
if declare -f faculty_deliver | grep -q 'transport_deliver';      then ok "deliver → transport_deliver"; else no "deliver delegation"; fi
if declare -f faculty_headless_answer | grep -q 'fleet_agent_headless_answer'; then ok "headless_answer → fleet_agent_headless_answer"; else no "headless_answer delegation"; fi

# --- 4. recall reads the durable head ---------------------------------------
section "4. recall (durable head)"
printf 'HEAD-MEMORY-MARKER\n' > "$STATE_DIR/memory/alpha.md"
out="$(faculty_recall alpha 2>/dev/null)"
if [[ "$out" == *HEAD-MEMORY-MARKER* ]]; then ok "recall returns the entity-memory head"; else no "recall head"; fi
isfalse "recall of an entity with no head fails" faculty_recall nobody
# RESUME.md fallback via the state doc's cwd
mkdir -p "$WORKSPACE/repoB"
printf 'RESUME-FALLBACK-MARKER\n' > "$WORKSPACE/repoB/RESUME.md"
fleet_state_ensure beta "$WORKSPACE/repoB" true
out="$(faculty_recall beta 2>/dev/null)"
if [[ "$out" == *RESUME-FALLBACK-MARKER* ]]; then ok "recall falls back to repo RESUME.md"; else no "recall RESUME fallback"; fi

# --- 4b. claude-bg adapter slice (Model B delivery primitive) ----------------
section "4b. claude-bg adapter (delivery primitive)"
for v in fleet_bg_deliver_turn fleet_bg_drain; do
  if declare -F "$v" >/dev/null 2>&1; then ok "claude-bg fn defined: $v"; else no "claude-bg fn MISSING: $v"; fi
done
istrue  "claude-bg: durable_body"    faculty_capability durable_body claude-bg
istrue  "claude-bg: native_delivery" faculty_capability native_delivery claude-bg
# faculty_deliver routes to the bg drain under the claude-bg adapter
if declare -f faculty_deliver | grep -q 'claude-bg'; then ok "faculty_deliver has claude-bg branch"; else no "no claude-bg deliver branch"; fi
# claude-bg is CLAUDE-ONLY (codex = refuter, not a per-worker brain): the drain delivers
# via the claude primitive and must NOT dispatch to codex.
if declare -f fleet_bg_drain | grep -q 'fleet_bg_deliver_turn' && ! declare -f fleet_bg_drain | grep -q 'fleet_codex_deliver_turn'; then ok "fleet_bg_drain is claude-only (no codex dispatch)"; else no "drain still dispatches codex"; fi
# fleet_bg_mount diverts a codex worker to the cli-tmux path (refuter-only on bg)
if declare -f fleet_bg_mount | grep -q 'fleet_tmux_start_child'; then ok "fleet_bg_mount diverts codex → cli-tmux"; else no "mount has no codex divert"; fi
# unmount reaps the controller (orphaned/duplicate-controller fix) via the pidfd `signal`
# path — exact argv identity + pidfd (closes the discovery->signal pid-reuse window), NOT an
# id-interpolated `pkill` regex and NOT a bare discover-then-`kill` fallback (that would
# reopen the reuse window). See tests/window-alloc.sh sections F + H.
if declare -F fleet_bg_unmount >/dev/null 2>&1 \
   && declare -f fleet_bg_unmount | grep -qE 'signal|fleet_safeio_available' \
   && ! declare -f fleet_bg_unmount | grep -q 'pkill' \
   && ! declare -f fleet_bg_unmount | grep -qE '\bkill "\$_pid"'; then
  ok "fleet_bg_unmount reaps via the pidfd signal path (no pkill regex, no discover-then-kill)"
else
  no "fleet_bg_unmount does not reap via pidfd (or still uses pkill / a discover-then-kill fallback)"
fi
if declare -f faculty_unmount | grep -q '_faculty_adapter_for'; then ok "faculty_unmount resolves adapter per-worker"; else no "faculty_unmount uses global adapter"; fi
for v in fleet_bg_start_session fleet_bg_mount fleet_bg_unmount fleet_bg_has_mail; do
  if declare -F "$v" >/dev/null 2>&1; then ok "claude-bg lifecycle fn: $v"; else no "missing: $v"; fi
done
# codex primitives retained but DORMANT (proven building block for a future codex-bg adapter)
for v in fleet_codex_start_session fleet_codex_deliver_turn; do
  if declare -F "$v" >/dev/null 2>&1; then ok "codex primitive retained (dormant): $v"; else no "missing: $v"; fi
done
if declare -f faculty_mount | grep -q 'fleet_bg_mount'; then ok "faculty_mount has claude-bg branch"; else no "no claude-bg mount branch"; fi
# no durable session id → drain keeps mail queued (returns non-zero), never crashes
mkdir -p "$STATE_DIR/inbox"; printf '{"from":"x","to":"node9","text":"hi","delivered":false}\n' > "$STATE_DIR/inbox/node9.jsonl"
fleet_state_ensure node9 "$TMP" true   # no session_id
isfalse "bg_drain with no session id keeps mail queued" fleet_bg_drain node9
# mixed-adapter guard: the cli-tmux mail path must SKIP a claude-bg worker
fleet_state_ensure bgw "$TMP" true; fleet_state_jq bgw '.faculty="claude-bg"' >/dev/null
printf '{"from":"x","to":"bgw","text":"hi","delivered":false}\n' > "$(fleet_inbox_file bgw)"
isfalse "fleet_drain_inbox skips a claude-bg worker"  fleet_drain_inbox bgw
isfalse "fleet_inject skips a claude-bg worker"        fleet_inject bgw x "hi"
# per-worker adapter resolution (mixable claude-bg + cli-tmux in one fleet)
eq "adapter from state .faculty"      "$(_faculty_adapter_for bgw)" "claude-bg"
eq "adapter falls back to global"     "$(FLEET_FACULTY_ADAPTER=cli-tmux _faculty_adapter_for ghostX)" "cli-tmux"
cat > "$STATE_DIR/m.toml" <<TOML
[[child]]
id = "mw"
adapter = "claude-bg"
TOML
fleet_manifest_load "$STATE_DIR/m.toml"
eq "adapter from manifest field wins" "$(_faculty_adapter_for mw)" "claude-bg"
if declare -f faculty_mount | grep -q '_faculty_adapter_for'; then ok "faculty_mount routes per-worker"; else no "faculty_mount not per-worker"; fi

# --- 4c. proactive compaction (token optimisation) --------------------------
section "4c. proactive compaction"
if declare -F fleet_compact >/dev/null 2>&1; then ok "fleet_compact defined"; else no "fleet_compact MISSING"; fi
# contract: refuses claude-bg (controller window, not a TUI), sends /compact, guards on the window
if declare -f fleet_compact | grep -q 'claude-bg'; then ok "fleet_compact refuses claude-bg"; else no "fleet_compact has no claude-bg guard"; fi
if declare -f fleet_compact | grep -q '/compact'; then ok "fleet_compact sends /compact"; else no "fleet_compact does not send /compact"; fi
if declare -f fleet_compact | grep -q 'fleet_tmux_has_window'; then ok "fleet_compact guards on window present"; else no "fleet_compact no window guard"; fi
# behavioural: no tmux window (unused socket) → returns non-zero, never crashes
isfalse "fleet_compact with no window returns non-zero" fleet_compact ghostC
# the on-stop hook compacts by CONTEXT SIZE (primary, adaptive) with a turn-count backstop
if grep -q 'FLEET_COMPACT_AT_PCT' "$ROOT/hooks/on-stop.sh"; then ok "on-stop hook has size trigger (FLEET_COMPACT_AT_PCT)"; else no "on-stop hook missing size trigger"; fi
if grep -q 'fleet_ctx_tokens' "$ROOT/hooks/on-stop.sh"; then ok "on-stop hook reads ctx size for the trigger"; else no "on-stop hook does not read ctx size"; fi
# The backstop must be ON by default. Asserting only that the NAME appears in the file was
# a false green for weeks: FLEET_COMPACT_EVERY was defaulted to 0 (disabled) three lines
# below a comment promising 40, and this line stayed green throughout. Assert the DEFAULT.
if grep -qE 'FLEET_COMPACT_EVERY:-[1-9][0-9]*' "$ROOT/hooks/on-stop.sh"; then ok "on-stop turn backstop is enabled by default"; else no "on-stop turn backstop defaults to disabled"; fi
# ...and that it is gated on a BLIND meter, not run as a second unconditional schedule
if grep -qE '_ctx == 0 && _compact_every' "$ROOT/hooks/on-stop.sh"; then ok "turn backstop fires only when ctx unreadable"; else no "turn backstop not gated on unreadable ctx"; fi
if grep -q 'turns_since_compact' "$ROOT/hooks/on-stop.sh" && declare -f fleet_compact >/dev/null; then ok "on-stop hook tracks turns_since_compact"; else no "on-stop hook no turn counter"; fi
# the counter mechanism the hook relies on: state round-trips an integer
fleet_state_ensure cmpw "$TMP" true
fleet_state_jq cmpw --argjson t 3 '.turns_since_compact=$t' >/dev/null 2>&1
eq "turns_since_compact round-trips in state" "$(fleet_state_get cmpw '.turns_since_compact' 0)" "3"

# --- 4c-bis. the METER itself, per provider ---------------------------------
# fleet_ctx_tokens is the instrument the size trigger and `fleet tokens` both read. It
# returned 0 for every codex lane because it only knew Claude's field names, and 0 is
# ALSO the legitimate "unknown" answer — so nothing anywhere reported the blindness.
# Real transcript fixtures, one per provider, plus a negative control that must read 0.
section "4c-bis. fleet_ctx_tokens reads BOTH providers"
export CLAUDE_PROJECTS_DIR="$TMP/projects" CODEX_HOME="$TMP/codex"
mkdir -p "$CODEX_HOME/sessions"

# claude: per-turn context = cache_read + cache_creation
_csid="11111111-2222-3333-4444-555555555555"
_cdir="$CLAUDE_PROJECTS_DIR/$(fleet_encode_path "$TMP")"; mkdir -p "$_cdir"
printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":7,"cache_read_input_tokens":120000,"cache_creation_input_tokens":3456}}}' > "$_cdir/$_csid.jsonl"
fleet_state_ensure ctxc "$TMP" true >/dev/null 2>&1
fleet_state_jq ctxc --arg s "$_csid" '.session_id=$s | .provider="claude"' >/dev/null 2>&1
eq "claude ctx = cache_read + cache_creation" "$(fleet_ctx_tokens ctxc)" "123456"

# codex: per-turn context = last_token_usage.input_tokens. The line also carries
# total_token_usage (CUMULATIVE, 32.6M on a real lane) — reading the bare
# "input_tokens" key would pick that up and trip every threshold on turn one.
_xsid="019f81fb-7311-7f63-8a8e-c36f0acaa87c"
printf '%s\n' '{"type":"turn_context","info":{"total_token_usage":{"input_tokens":32501144,"cached_input_tokens":30416640,"total_tokens":32601334},"last_token_usage":{"input_tokens":79676,"cached_input_tokens":78592,"output_tokens":46,"total_tokens":79722}}}' > "$CODEX_HOME/sessions/rollout-2026-07-21T12-02-47-$_xsid.jsonl"
fleet_state_ensure ctxx "$TMP" true >/dev/null 2>&1
fleet_state_jq ctxx --arg s "$_xsid" '.session_id=$s | .provider="codex"' >/dev/null 2>&1
eq "codex ctx = last_token_usage.input_tokens (not the cumulative total)" "$(fleet_ctx_tokens ctxx)" "79676"

# negative control: the meter must be able to READ ZERO, or the two greens above prove nothing
_nsid="99999999-9999-9999-9999-999999999999"
printf '%s\n' '{"type":"assistant","message":{"content":"no usage record here"}}' > "$_cdir/$_nsid.jsonl"
fleet_state_ensure ctxn "$TMP" true >/dev/null 2>&1
fleet_state_jq ctxn --arg s "$_nsid" '.session_id=$s | .provider="claude"' >/dev/null 2>&1
eq "negative control: a transcript with no usage reads 0" "$(fleet_ctx_tokens ctxn)" "0"
unset CLAUDE_PROJECTS_DIR CODEX_HOME

# --- 4d. inject defer / stuck-message guard ---------------------------------
section "4d. inject defer (stuck+truncated message fix)"
for v in fleet_input_busy _fleet_line_has_real_input; do
  if declare -F "$v" >/dev/null 2>&1; then ok "defined: $v"; else no "MISSING: $v"; fi
done
# no window (unused socket) → capture fails → conservative "not busy" (delivery not blocked)
isfalse "fleet_input_busy with no window → not busy (errs toward delivering)" fleet_input_busy ghostI
# --- dim discrimination (deterministic, the crux): Claude Code renders ghost/placeholder
# text DIM (\e[2m…) in an EMPTY box; real typed input is NON-dim. Only NON-dim = occupied.
_E=$'\e'; _NB=$' '
isfalse "empty box (prompt+NBSP) → not busy"                    _fleet_line_has_real_input "${_E}[39m❯${_NB} "
isfalse "dim ghost '<no suggestion>' → not busy"               _fleet_line_has_real_input "${_E}[39m❯${_NB} ${_E}[2m<no suggestion>${_E}[0m"
# the live regression: a dim run with an INTERMEDIATE SGR code (\e[2m\e[39mText\e[0m) — a
# naive [^\e]* stops at the inner \e and leaks the ghost text as "occupied"
isfalse "dim ghost w/ intermediate SGR → not busy (core-style)" _fleet_line_has_real_input "${_E}[38;5;246m❯${_NB} ${_E}[2m${_E}[39mPress up to edit queued messages${_E}[0m"
istrue  "non-dim real input → busy"                            _fleet_line_has_real_input "${_E}[39m❯${_NB} ZZREAL typed by a human"
istrue  "dim hint + trailing real text → busy"                 _fleet_line_has_real_input "${_E}[39m❯${_NB} ${_E}[2mhint${_E}[0m realtext"
if declare -f _fleet_line_has_real_input | grep -qF $' '; then ok "strips NBSP padding"; else no "does NOT strip NBSP (would defer forever)"; fi
# fleet_inject defers (distinct code 2) on an occupied box instead of typing onto it
if declare -f fleet_inject | grep -q 'fleet_input_busy'; then ok "fleet_inject has the defer guard"; else no "fleet_inject missing defer guard"; fi
if declare -f fleet_inject | grep -q 'FLEET_INJECT_DEFER'; then ok "defer guard is toggleable (FLEET_INJECT_DEFER)"; else no "no FLEET_INJECT_DEFER toggle"; fi
if declare -f fleet_inject | grep -q 'return 2'; then ok "fleet_inject defers with distinct code 2"; else no "defer not a distinct return code"; fi
# the drain treats a deferred (rc 2) message as backpressure, NOT an inject failure
if declare -f fleet_drain_inbox | grep -q 'deferred_count'; then ok "drain counts defers separately (not failures)"; else no "drain conflates defer with failure"; fi
# a paste that did not LAND is dropped from the tmux buffer and requeued (rc 1), not Entered
if declare -f fleet_inject | grep -q 'delete-buffer'; then ok "fleet_inject drops a non-landed paste buffer (no Enter into nothing)"; else no "fleet_inject doesn't clean a non-landed paste"; fi
# anything left in the box after submit is handled by the Stop-hook flush, never C-u'd (C-u is
# ineffective mid-turn and Ctrl-C would abort the worker's turn)
if grep -q 'fleet_flush_stuck_box' hooks/on-stop.sh && declare -F fleet_flush_stuck_box >/dev/null 2>&1; then ok "stray box content handled by Stop-hook flush (not C-u)"; else no "no flush backstop for stray box content"; fi

# active-work detector exists + is precise (used by the idle check / flush, not as an inject gate)
if declare -F fleet_pane_is_working >/dev/null 2>&1; then ok "defined: fleet_pane_is_working"; else no "fleet_pane_is_working missing"; fi
# it must NOT key on the always-present permission glyph / spinner glyphs (those read busy forever)
if declare -f fleet_pane_is_working | grep -qE '⏵⏵|✻|✶|✽'; then no "active-work detector keys on always-present glyph → strands all mail"; else ok "active-work detector ignores always-present glyphs (⏵⏵/spinners)"; fi
# fleet_pane_is_idle must recognise the current Claude Code prompt box (❯) — not just old styles
if declare -f fleet_pane_is_idle | grep -q '❯'; then ok "fleet_pane_is_idle recognises the ❯ prompt box"; else no "fleet_pane_is_idle blind to ❯ box → every pane reads busy"; fi
# GROUND-TRUTH: Enter-while-busy is QUEUED by Claude Code, not swallowed — so the inject must
# NOT gate the submit on idle (doing so skipped the Enter and stranded the message as box text).
if declare -f fleet_inject | grep -qE 'if .*fleet_pane_is_working.*; then.*return 2'; then no "fleet_inject still gates delivery on working → strands queued messages"; else ok "fleet_inject does not idle-gate the submit (Enter-while-busy queues fine)"; fi
# atomic bracketed-paste insertion replaces chunked typing (no truncation, multi-line safe)
if declare -f fleet_inject | grep -q 'paste-buffer -d -p'; then ok "fleet_inject inserts via atomic bracketed paste"; else no "fleet_inject not using bracketed paste"; fi
if declare -f fleet_inject | grep -q 'FLEET_INJECT_PASTE'; then ok "paste path is toggleable (FLEET_INJECT_PASTE=off → legacy typing)"; else no "no FLEET_INJECT_PASTE toggle"; fi
# confirm-landed: before Enter, fleet_inject requires its content to actually be in the box,
# else an empty box (paste silently dropped) would be marked submitted = SILENT LOSS.
if declare -f fleet_inject | grep -q 'landed'; then ok "fleet_inject confirms the insert landed before submitting (anti silent-loss)"; else no "fleet_inject doesn't confirm landing → silent-loss risk"; fi
# head-of-line: a poison message is dead-lettered after a budget instead of blocking the queue
if declare -f fleet_drain_inbox | grep -q 'FLEET_INJECT_MAX_ATTEMPTS'; then ok "drain bounds per-message attempts (FLEET_INJECT_MAX_ATTEMPTS)"; else no "drain has no attempt budget → head-of-line block"; fi
if declare -f fleet_drain_inbox | grep -q 'dead=true'; then ok "drain dead-letters an undeliverable message (quarantine, not silent block)"; else no "drain doesn't dead-letter poison messages"; fi
if declare -f fleet_drain_inbox | grep -q 'dead_count'; then ok "drain records dead-letters to state (visible)"; else no "dead-letters not recorded"; fi

# submit-verify is the dim-aware empty-box test (multi-line / placeholder safe), not a tail grep:
# the re-Enter loop now exits on `fleet_input_busy ... || return 0`, and the old tail-text
# marker grep is gone (it broke on wrapped lines / paste placeholders).
if declare -f fleet_inject | grep -qE 'fleet_input_busy "\$to"'; then ok "submit-verify uses dim-aware empty-box test"; else no "submit-verify not empty-box based"; fi
# never skip the Enter: a pre-submit check must not be able to bail before pressing Enter
# (the overnight stuck was exactly that). And an extra Enter follows each message (Roy's trick).
if declare -f fleet_inject | grep -cE 'send-keys -t "\$tgt" Enter' | grep -qE '^[2-9]'; then ok "fleet_inject always sends Enter + an extra one (never skips the submit)"; else no "fleet_inject can skip the Enter → stuck-in-box risk"; fi
# submit only when idle (never fight a working pane with Enter), with a Stop-hook flush backstop
if declare -F fleet_flush_stuck_box >/dev/null 2>&1; then ok "defined: fleet_flush_stuck_box (Stop-hook backstop submits a stuck-in-box inject)"; else no "fleet_flush_stuck_box missing"; fi
if grep -q 'fleet_flush_stuck_box' hooks/on-stop.sh; then ok "on-stop hook flushes a stuck box at idle"; else no "on-stop doesn't flush stuck box"; fi
if declare -F fleet_box_has_stuck_inject >/dev/null 2>&1; then ok "tag-gate fleet_box_has_stuck_inject defined (auto-Enter only on injects, not human text)"; else no "no tag-gate → auto-Enter could submit human typing"; fi
if declare -f fleet_flush_stuck_box | grep -q "fleet_box_has_stuck_inject"; then ok "flush is tag-gated (never submits human typing)"; else no "flush not tag-gated"; fi
if declare -f fleet_inject | grep -q 'marker='; then no "old tail-text marker verify still present"; else ok "old tail-text marker verify removed"; fi

# --- 5. honest unimplemented verbs ------------------------------------------
section "5. unimplemented verbs fail honestly"
isfalse "spawn_tool returns non-zero (unimplemented)" faculty_spawn_tool x "task"
isfalse "stream returns non-zero (unimplemented)"     faculty_stream x

# --- summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]

# --- 4c-ter. fleet_compact must never keystroke into a busy pane ---------------
# A slash command typed mid-turn is QUEUED AS A MESSAGE, not executed. Live evidence
# (composer, 2026-08-07): 7 attempts, 5 stacked `/compact` lines in the input box,
# context climbing 897k -> 950k throughout. The guard existed; this function never
# called it.
section "4c-ter. compact defers on a busy pane"
if declare -f fleet_compact | grep -q 'fleet_pane_is_working'; then ok "fleet_compact consults the working-state guard"; else no "fleet_compact can still type into a mid-turn pane"; fi
if declare -f fleet_compact | grep -q 'fleet_input_busy'; then ok "fleet_compact consults the input-box guard"; else no "fleet_compact can still paste onto pending input"; fi
# Behavioural: force "working" true and prove compact refuses WITHOUT sending keys.
_sent=0
fleet_pane_is_working() { return 0; }
fleet_tmux_has_window() { return 0; }
fleet_tmux() { case "${1:-}" in send-keys) _sent=1 ;; esac; return 0; }
isfalse "compact returns non-zero when the pane is working" fleet_compact busyw
eq "compact sent NO keystrokes to a working pane" "$_sent" "0"
# ...and that the same stubs let it through once the pane is idle (so the test above
# proves the guard, not a broken harness).
fleet_pane_is_working() { return 1; }
fleet_input_busy() { return 1; }
_sent=0; fleet_compact idlew >/dev/null 2>&1
eq "control: an idle pane still receives the keystrokes" "$_sent" "1"
unset -f fleet_pane_is_working fleet_input_busy fleet_tmux fleet_tmux_has_window
