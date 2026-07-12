# RESUME — claude-fleet repo expert (fleet-fix lane)

## Current objective
Fix the confirmed **`fleet ask` live-checkout isolation defect**: a resumed Claude/Codex
fork (the off-thread responder) could restore the writer's original session cwd and mutate
the live checkout, because the provider adapter dropped the isolated cwd and passed no
read-only controls. **DONE this turn** — committed on `fix/fleet-robustness-batch`, not pushed.

## Last verified state (2026-07-12)
- Branch: `fix/fleet-robustness-batch` (off `master`).
- `bash -n` clean on all changed scripts.
- Focused test `tests/ask-isolation.sh`: **35/35 pass**.
- `tests/faculty.sh`: **99/99 pass**.  `tests/smoke.sh`: **93/93 pass** (incl. §9 forked responder).
- Two PRE-EXISTING dirty files (`bin/fleet-watchdog.sh`, `lib/comms.sh`) were UNRELATED user work —
  left unstaged / untouched, NOT part of this commit.

## What the fix does (structural, two layers — never prompt text)
1. `lib/responder.sh` — isolation now **fails closed**: any mktemp/`cd` failure calls
   `_isolation_abort` (enqueues an error answer to the asker; never launches from the live
   checkout). Removed the `cd … || true` fallthrough holes. Threads the isolated cwd
   (`$_ask_cwd`) into `faculty_headless_answer`. Non-git targets skip the worktree retry loop
   (saves 3s) and use a bare temp-dir isolate.
2. `lib/provider.sh` `fleet_agent_headless_answer` — new 5th arg `cwd`, bound explicitly:
   - **claude**: `--allowedTools Read Grep Glob --disallowedTools Edit Write MultiEdit NotebookEdit Bash`,
     launched in a `cd`'d subshell → no Edit/Write/Bash surface even if resumed cwd = live tree.
   - **codex**: `--cd <iso> --sandbox read-only --ask-for-approval never` before `exec [resume]`.
3. `lib/faculty.sh` — unchanged (seam already forwards `"$@"`, so cwd propagates).
4. `docs/FACULTY-ADAPTER-CONTRACT.md` — documents the two-layer isolation contract.
5. `tests/ask-isolation.sh` — NEW regression test (stubs, no network): proves the read-only
   flags/allowlists are present for both providers, the isolated cwd is passed, a resumed
   responder's cwd-relative write lands in the throw-away worktree (not the writer checkout),
   and fail-closed static + non-git-degrade behavior.

## Next actions
- Await Roy's call on push (not authorized yet).
- Optional live smoke: real `fleet ask` between two agents once a fleet is up (stubbed here).

## Do-not-assume / risks
- The claude read-only guarantee assumes real `claude` honors `--allowedTools`/`--disallowedTools`
  (stub can't enforce; §A proves the FLAGS are passed, provider contract enforces them).
  The cwd-isolation layer (§B) is provider-independent and is the belt to that suspenders.
- Denying `Bash` means the fork can't run `git log` for the F3 "verify against committed canon"
  primer hint — it can still `Read` RESUME.md / committed files. Acceptable trade for no-write.
- `codex --ask-for-approval never` is a global flag placed before `exec`; combo validated by the
  existing interactive builder that already pairs `--sandbox`/`--ask-for-approval`.
