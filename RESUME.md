# RESUME — claude-fleet repo expert (fleet-fix2 lane)

## Current objective
The narrow follow-up for the confirmed **`fleet ask` transient-window allocation collision** is
complete. The commit containing this handoff is branch HEAD directly above unchanged `c4d94d4`
(run `git log -1` for its exact hash). No history was rewritten and nothing was pushed.

## Last verified state (2026-07-13)
- Branch: `fix/fleet-robustness-batch`; base commit `c4d94d4bb39ece994732a98f86a45bc677a37e7f`.
- Live reproduction before the fix: with regular client on fleet window 0, external caller context
  inherited from window 1, and windows through 12 occupied, `tmux new-window -t fleet ...` returned
  `create window failed: index 12 in use`.
- `tests/ask-isolation.sh`: **61/61 passed**, including the client-w0 / caller-pane-w1 / occupied-w12
  integration path, exact `session:` target assertion, isolated responder answer, unchanged w12,
  provider argv controls, cwd-boundary rejection, non-git isolation, and fail-closed isolation.
- `bash tests/faculty.sh`: **99/99 passed**.
- `bash tests/smoke.sh`: **93/93 passed** (direct invocation).
- Pre-existing dirty `bin/fleet-watchdog.sh` and `lib/comms.sh` are unrelated user work. Preserve them
  unstaged; they were neither edited nor included in this follow-up.

## Transient ask-window follow-up
1. `bin/fleet` now targets `"$FLEET_TMUX_SESSION:"` for the transient responder. The explicit empty
   window component tells tmux to allocate the next unused index instead of resolving a split inherited
   `TMUX`/`TMUX_PANE` context to an occupied worker index.
2. `tests/ask-isolation.sh` builds windows 0..12 on a private socket, attaches the regular client while
   only w0 exists, creates w1..w12 detached so that client remains on w0, and invokes `fleet ask`
   externally with `TMUX_PANE` from w1. It asserts successful answer delivery and preservation of w12.
3. Provider isolation controls were not changed: `lib/provider.sh`, `lib/responder.sh`, `lib/faculty.sh`,
   and `docs/FACULTY-ADAPTER-CONTRACT.md` are untouched by this follow-up.
4. Changed files in the follow-up: `bin/fleet`, `tests/ask-isolation.sh`, and `RESUME.md`.

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
- The private integration fixture is platform-context-sensitive, so the exact target syntax is also
  asserted statically; the failure itself was independently reproduced against the live tmux server.
- The focused regression now requires the standard `script` utility to hold a regular pseudo-terminal
  client. The production change itself uses documented tmux target syntax supported by tmux >= 3.0.
- Stub tests prove the exact flags and cwd passed, not the providers' internal enforcement. Local CLI
  help validates flag compatibility; the independent cwd-isolation layer remains the primary floor.
- Denying `Bash` means a Claude responder cannot execute `git log` despite the stale-context primer;
  it can still use built-in `Read`/`Grep`/`Glob` on the committed isolated worktree.
- An empty-dir Codex fallback may be limited by Codex's repo check; this is availability degradation,
  not a write-safety fallback. The adapter still binds the directory and stays read-only/non-interactive.
- No separate opposite-provider refuter was launched for this one-line allocation fix; the operator
  repeatedly challenged and corrected the fixture against live `list-panes`/`list-clients` ground truth.
  Strongest open attack: run the same regression on the oldest supported tmux (3.0) and macOS/BSD
  `script`; the local verified host used tmux 3.7b on Linux.
