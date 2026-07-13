# RESUME — claude-fleet repo expert (fleet-fix2 lane)

## Current objective
The independent-verification follow-up for the **`fleet ask` transient-window allocation collision**
is complete. The commit containing this handoff is branch HEAD directly above unchanged `8ac37cc`
(run `git log -1` for its exact hash); the production allocation fix remains in `8ac37cc`. No history
was rewritten and nothing was pushed.

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
- No implementation work remains for this narrow follow-up.

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
