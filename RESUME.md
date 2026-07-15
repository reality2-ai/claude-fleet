# RESUME — claude-fleet repo expert (fleet-fix2 lane)

## Current objective
**#66 (window allocator) is FIXED and verified live** — this was the blocker on specs' twin-reviews.
The `fleet ask` live-checkout isolation defect was already fixed earlier (see re-verification below).
No history was rewritten and nothing was pushed.

## #66 window allocator — ROOT CAUSE (2026-07-15). The earlier diagnosis was WRONG.
**Symptom**: every spawn (`refute`/`up`/`dispatch`/`pair`) died with `create window failed: index N
in use`, deterministically.

**Actual root cause**: `tmux new-window -t "$FLEET_TMUX_SESSION"` (a BARE session name) is parsed by
tmux as a target-**WINDOW** and resolved by window-**NAME** match, which PREFIX-matches any window
named like the session — session `fleet` matches the window **`fleet-fix`** (this lane's own window).
new-window then tries to create AT that window's index → "index N in use". Adding the explicit EMPTY
window component (`-t "$FLEET_TMUX_SESSION:"`) forces session-only resolution → next unused index.

**Evidence** (the index TRACKS the fleet-fix window; it is not base-index/renumber/phantom/count):
- Live `fleet refute --provider codex --id fleetfix-probe66 supervisor "probe"` → `index 11 in use`,
  while `fleet-fix` sat at index 11. The supervisor saw `index 12 in use` earlier, when it sat at 12.
- Hermetic proof + control: with a window named `fleet-fix` at index 4, `-t "fleet"` → `index 4 in
  use`; `-t "fleet:"` → OK; **kill the `fleet-*` window and `-t "fleet"` succeeds**.
- Live re-run AFTER the fix: the same refute command SUCCEEDS (allocated the free index 2). Probe
  window + state doc were cleaned up.

**Refuted hypotheses (do not re-chase)**: base-index (it is 0) / renumber-windows (off) / phantom
members (clearing them changed nothing) / member-count / inherited `TMUX`+`TMUX_PANE` context /
attached-client state. Each was tested and did NOT reproduce. Also note the supervisor's diagnostic
"12 = your own fleet-fix window" was stale — 12 was `website-merge`; fleet-fix was 13, then 11.

**Fix**: `-t "$FLEET_TMUX_SESSION:"` at the remaining spawn sites — `lib/tmux.sh` (both the argv-file
and inline branches of `fleet_tmux_new_agent_window`) and `lib/faculty-bg.sh`. `bin/fleet` `cmd_ask`
already had it from `8ac37cc`, which was therefore a CORRECT fix, not a placebo.

**Trap for the next agent**: a fixture whose windows are named generically (`w0`, `w1`, …) CANNOT
reproduce this and passes against broken code — that is exactly how it survived a fix round. Any
regression fixture MUST name a window after the session. `tests/window-alloc.sh` does, and was
verified to FAIL 5/10 against unfixed HEAD before passing 24/24 fixed.

**Also landed**: `fleet_valid_member_id` in `lib/registry.sh` rejects empty / leading-`-` / `/` / `..`
ids at registration (`fleet_state_ensure` dies). This stops the phantom members seen live
(`.fleet/state/--help.json`, `--.json`) and closes a `fleet_state_path` traversal.

## Re-verification (2026-07-15) — isolation defect already fixed; NO new fix was warranted

## Re-verification (2026-07-15) — isolation defect already fixed; NO new fix was warranted
A tasking arrived on 2026-07-15 to "fix the confirmed `fleet ask` live-checkout isolation defect".
Ground-truth check found the defect **already fixed in committed code**; the tasking premise was
stale. No code change was made — a fix commit would have been fabricated work. Evidence:
- `lib/responder.sh` establishes an isolated cwd (detached worktree at HEAD, else empty temp dir) and
  routes every unrecoverable `mktemp`/`cd` failure to `_isolation_abort` — no live-checkout fallthrough.
- `lib/provider.sh:179` fails closed: `fleet_agent_headless_answer` returns 3 unless `cwd` names an
  existing dir, so neither provider can launch onto the caller's live cwd. Claude gets
  `--safe-mode --permission-mode dontAsk --tools Read,Grep,Glob --disallowedTools Edit,Write,NotebookEdit,Bash`;
  Codex gets `--cd <isolate> --sandbox read-only --ask-for-approval never`.
- Regression coverage already exists in `tests/ask-isolation.sh` (sections A/A2/B/C/C2/D).
- **New check not previously recorded**: `tests/ask-isolation.sh` was run in a throw-away detached
  worktree at clean `HEAD` (`204cf97`) — **59/59 passed**, proving the fix holds in committed state
  alone and is not masked by the dirty `bin/fleet-watchdog.sh` / `lib/comms.sh` work.
- Bypass hunt found none: `lib/faculty.sh:99` routes *all* adapters (`cli-tmux|*`) through
  `fleet_agent_headless_answer`, and `lib/faculty-bg.sh` — which launches provider bins directly —
  is not reachable from the ask path (`bin/fleet:1975` → `responder.sh` only).
- Re-run at working HEAD: `tests/ask-isolation.sh` 59/59, `tests/smoke.sh` 93/93, `tests/faculty.sh` 99/99.

## Last verified state (2026-07-13)
- Branch: `fix/fleet-robustness-batch`; follow-up parent
  `8ac37ccbccfcf70b91f747a9be9934304c88248a` (original follow-up base:
  `c4d94d4bb39ece994732a98f86a45bc677a37e7f`).
- Live reproduction before the fix: with regular client on fleet window 0, external caller context
  inherited from window 1, and windows through 12 occupied, `tmux new-window -t fleet ...` returned
  `create window failed: index 12 in use`.
- Independent post-commit verification of `8ac37cc` found **59/61**: only the regular pseudo-terminal
  client attachment/movement assertions failed in both escalated and tty runs; allocation, the exact
  `session:` assertion, responder answer, and w12 preservation all passed.
- `tests/ask-isolation.sh`: **59/59 passed** after removing that non-hermetic `script`/FIFO client
  layer. Stable coverage retains detached windows 0..12, external inherited `TMUX`/`TMUX_PANE`
  context, exact target syntax, isolated responder answer, unchanged w12, provider argv controls,
  cwd-boundary rejection, non-git isolation, and fail-closed isolation.
- `bash tests/faculty.sh`: **99/99 passed**.
- `bash tests/smoke.sh`: **93/93 passed** (direct invocation).
- Pre-existing dirty `bin/fleet-watchdog.sh` and `lib/comms.sh` are unrelated user work. Preserve them
  unstaged; they were neither edited nor included in this follow-up.

## Transient ask-window follow-up
1. `bin/fleet` now targets `"$FLEET_TMUX_SESSION:"` for the transient responder. The explicit empty
   window component tells tmux to allocate the next unused index instead of resolving a split inherited
   `TMUX`/`TMUX_PANE` context to an occupied worker index.
2. `tests/ask-isolation.sh` builds windows 0..12 detached on a private socket and invokes `fleet ask`
   externally with `TMUX` bound to that server and `TMUX_PANE` from w1. It asserts successful answer
   delivery, the exact `session:` source target, and preservation of w12 without requiring a client PTY.
3. Provider isolation controls were not changed: `lib/provider.sh`, `lib/responder.sh`, `lib/faculty.sh`,
   and `docs/FACULTY-ADAPTER-CONTRACT.md` are untouched by this follow-up.
4. `8ac37cc` changed `bin/fleet`, `tests/ask-isolation.sh`, and `RESUME.md`; this verification follow-up
   changes only `tests/ask-isolation.sh` and `RESUME.md`. It also waits for the responder window to
   close before temp cleanup, avoiding a mailbox recreation/removal race exposed by the faster fixture.

## Prior isolation hardening retained from `c4d94d4`
1. `lib/responder.sh` (`14cb8d6`) creates a detached worktree or empty temp-dir isolate, aborts with an
   error answer on unrecoverable `mktemp`/`cd` failures, and passes `$_ask_cwd` through
   `faculty_headless_answer`. Non-git targets skip the worktree retry loop. Review on 2026-07-13 found
   no live-checkout fallback: the functional forced-`mktemp` attack did not invoke the provider and
   left the live checkout intact.
2. `lib/provider.sh` follow-up requires the fifth `cwd` argument to name an existing directory before
   either provider can launch:
   - Claude: launch from that cwd with `--safe-mode --permission-mode dontAsk --tools Read,Grep,Glob
     --disallowedTools Edit,Write,NotebookEdit,Bash`.
   - Codex: launch with `--cd <isolate> --sandbox read-only --ask-for-approval never` before
     `exec [resume]`.
3. `lib/faculty.sh` remains unchanged; its exact delegate forwards the cwd argument.
4. `tests/ask-isolation.sh` functionally covers omitted and nonexistent cwd for both providers,
   exact provider argv, end-to-end isolated cwd, non-git degradation, and forced `mktemp` failure.
   `tests/smoke.sh` also pins its default provider so its Claude fixtures remain hermetic in a Codex lane.
5. `docs/FACULTY-ADAPTER-CONTRACT.md` records the required adapter boundary and exact controls.

## Prior work — robustness batch (`af290a3`)
`af290a3` is the earlier five-fix robustness commit; retain this information during future handoffs:
1. `bin/fleet`: Codex companions default to `read-only` plus approval `never`, avoiding stranded
   adversarial panes while retaining per-child manifest precedence.
2. `bin/fleet-watchdog.sh`: idle nudge became opt-in (`FLEET_IDLE_NUDGE=on`, default off); doctor
   oversight remains active unless separately disabled.
3. `hooks/git/pre-push`: the content secret scan excludes vendored `**/vectors/**.json` and
   `testing/test-vectors/**.json` KAT data, while the filename scan still rejects secret-bearing names.
4. `lib/restart.sh`: direct restart gets safe unset-variable defaults (`SUP_MAX_SECONDS=3600`,
   `SUP_MAX_RESTARTS=5`).
5. `lib/tmux.sh`: argv spill threshold was lowered from 20000 to 12000, below tmux's 16384-byte imsg
   ceiling, so oversized prompts use the NUL-delimited argv file path.

## Next actions
- Await explicit authorization before any push.
- Tell supervisor #66 is landed so its queued codex reverse-calibration refuter can spawn.
- OPEN (not mine to assume): the live fleet has LOST windows — `specs`, `core`, `android`,
  `core-codex`, `composer-codex`, `android-codex` are absent from the window list while state docs
  remain. #66 plausibly explains the failed (re)spawns; with the allocator fixed, a `fleet reap` /
  `fleet up` should be able to restore them. Supervisor should confirm before mass-restart.
- Phantom state docs still on disk (`.fleet/state/--help.json`, `--.json`, and stale
  `*-refute.json`): the new guard prevents NEW ones but does not delete existing docs. Clean
  deliberately, not blindly — some may be live lanes.
- Supervisor asked for a merge of `origin/master` (decision-ledger + README pass) into this branch.
  NOT done — it is a separate change and this branch is mid-review. Do it as its own commit.
- **Do not re-open the isolation defect without new falsifying evidence** — a 2026-07-15 tasking
  asserted it was still open; ground truth refuted that. Re-run `tests/ask-isolation.sh` at clean
  HEAD first and challenge the premise before editing.

## Do-not-assume / risks
- Do not stage or overwrite the unrelated dirty `bin/fleet-watchdog.sh` and `lib/comms.sh` changes.
- The private integration fixture intentionally does not claim to reproduce every live-client target
  resolution detail; the exact target syntax is asserted statically, and the failure itself was
  independently reproduced against the live tmux server.
- Stub tests prove the exact flags and cwd passed, not the providers' internal enforcement. Local CLI
  help validates flag compatibility; the independent cwd-isolation layer remains the primary floor.
- Denying `Bash` means a Claude responder cannot execute `git log` despite the stale-context primer;
  it can still use built-in `Read`/`Grep`/`Glob` on the committed isolated worktree.
- An empty-dir Codex fallback may be limited by Codex's repo check; this is availability degradation,
  not a write-safety fallback. The adapter still binds the directory and stays read-only/non-interactive.
- Independent `supervisor-codex` verification found and killed the pseudo-terminal-client auxiliary;
  the production `session:` fix and stable integration assertions survived that attack.
  Strongest open attack: exercise a real-provider `fleet ask` from the original live supervisor
  split-context on the oldest supported tmux (3.0); local verification used tmux 3.7b on Linux.
