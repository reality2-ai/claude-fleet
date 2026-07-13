# RESUME — claude-fleet repo expert (fleet-fix lane)

## Current objective
The follow-up hardening for the confirmed **`fleet ask` live-checkout isolation defect** is complete.
The structural fix is in `14cb8d6`; the branch HEAD (see `git log -1`) is a narrow follow-up above
independent commit `0ee94dc` correcting the provider boundary/flags, functional tests,
adapter-contract documentation, and this handoff. Neither existing commit was rewritten; nothing
was pushed.

## Last verified state (2026-07-13)
- Branch: `fix/fleet-robustness-batch`; the follow-up containing this handoff is branch HEAD,
  directly above unchanged `0ee94dc` (original isolation commit: `14cb8d6`).
- Local installed CLI help confirms the requested flags exist: Claude `--safe-mode`,
  `--permission-mode dontAsk`, `--tools`, `--disallowedTools`; Codex `--cd`,
  `--sandbox read-only`, `--ask-for-approval never` before `exec`.
- `bash -n`: clean across bash files under `bin/`, `lib/`, `hooks/`, and `tests/`.
- `tests/ask-isolation.sh`: **54/54 passed** (exact provider argv; omitted/nonexistent cwd rejection;
  isolated worktree; non-git isolate; functional forced-`mktemp` abort).
- `bash tests/faculty.sh`: **99/99 passed**.
- `bash tests/smoke.sh`: **93/93 passed**, including the forked responder.
- The first responder/smoke attempts inherited ambient `FLEET_AGENT_PROVIDER=codex`, bypassed their
  Claude stubs, and were terminated. Xtrace confirmed the wrong provider selection before the fixtures
  were changed; both tests now pin their intended default and pass in this Codex takeover lane.
- Pre-existing dirty `bin/fleet-watchdog.sh` and `lib/comms.sh` are unrelated user work. Preserve them
  unstaged; they are not part of the follow-up commit.

## Isolation fix and follow-up scope
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
- Optional availability check: a real-provider `fleet ask` once the fleet can be exercised safely.
  It was deliberately not run here because the operator prohibited `fleet ask`/`fleet refute`.

## Do-not-assume / risks
- Stub tests prove the exact flags and cwd passed, not the providers' internal enforcement. Local CLI
  help validates flag compatibility; the independent cwd-isolation layer remains the primary floor.
- Denying `Bash` means a Claude responder cannot execute `git log` despite the stale-context primer;
  it can still use built-in `Read`/`Grep`/`Glob` on the committed isolated worktree.
- An empty-dir Codex fallback may be limited by Codex's repo check; this is availability degradation,
  not a write-safety fallback. The adapter still binds the directory and stays read-only/non-interactive.
- No independent refuter was used because the operator explicitly prohibited `fleet ask`/`fleet refute`.
  Strongest open attack: an end-to-end real-provider resumed session that attempts to restore its
  original cwd and mutate it; current coverage uses argv-recording/mutating stubs plus CLI-help validation.
