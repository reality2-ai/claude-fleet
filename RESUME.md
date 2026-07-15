# RESUME — claude-fleet repo expert (id-hardening lane)

## LANDED (2026-07-15, local commits only) — fd-bound no-follow + pidfd hardening (atomic-writer)
Final correction for the residual TOCTOU that f9f2947 disclosed. **Code commit
`562dcee3681c10aa72bdb56f592b35401c01d755`** `fix(comms,registry,faculty-bg): fd-bound
no-follow safe-IO for mailbox/state + pidfd reap`, on `fix/fleet-robustness-batch` (parent
`a4cab7d`); this RESUME update is a SEPARATE commit on top. **NOT pushed.** watchdog +
`_fleet_inject_trace` hunk excluded (unstaged). **Requires a fresh exact adversarial review —
do NOT self-declare clean.**

### Design (what closes the residual)
bash cannot express O_NOFOLLOW / pidfd, so a tiny helper **`lib/fleet-safeio.py`** (python3,
Linux+macOS) provides the fd-bound primitives; the shell routes through it and **fails closed**
when it is absent (python3 is now a documented prerequisite for mailbox/state hardening — the
overwrite/rename class stays safe via rename(), but no-follow read/append/lock/pidfd require it).
Helper subcommands + exit codes (0 ok, 2 usage, 3 refused-symlink/non-regular/foreign, 4 absent,
5 primitive-unavailable, 6 rotate identity-mismatch):
- `read/append/write` — O_NOFOLLOW open (+fstat regular). `write` = O_EXCL temp → fsync →
  rename() (never descends → a dir dest fails atomically; a symlink dest is replaced; foreign
  regular refused). **No shell `mv` fallback** (a `[[ -d ]]`+`mv` is itself TOCTOU).
- `enqueue <inbox> <lock>` — ONE locked transaction: flock(lock,O_NOFOLLOW) → append(inbox,
  O_NOFOLLOW) → release. Replaces the shell `exec 9>>lock` + `>>inbox`.
- `hold-lock <lock>` — flock(O_NOFOLLOW), print LOCKED, hold until stdin EOF. A bash **coproc**
  (`fleet_safe_lock`/`unlock`) owns it so the drain's whole read-modify-write runs under a
  no-follow lock without opening the lock in shell.
- `rotate <src> <dst>` — the drain's **identity-checked snapshot**: O_NOFOLLOW-open+fstat src,
  rename→dst, reopen dst and require SAME (dev,ino,regular,owner), then emit that verified
  inode's content. Immune to a same-owner regular-file swap in the open→rename window (rc 6).
- `rename <src> <dst>` — plain atomic rename, used ONLY to RESTORE a snapshot on abort.
- `signal <sig> <id>` — pidfd_open + cmdline re-validation + pidfd_send_signal reap; closes the
  discovery→signal pid-reuse window. **No discover-then-kill fallback** — pidfd or under-reap.

### Drain invariant (data-loss preservation — enforced)
`$snap` is the SOLE copy of the mail from a successful rotate until confirmed safe at `$f`. It is
removed ONLY after a confirmed-safe commit or a successful restore; on ANY restore/commit/parse
failure it is KEPT on disk (`.snap.*`) and logged loudly (`_fleet_drain_restore`). A failed
read/parse is NEVER treated as an empty queue (fail closed + preserve). A symlinked inbox is NOT
unlinked by name (racer could swap it) — left in place, fail closed.

### Files (all dirty, uncommitted)
`lib/fleet-safeio.py` (new), `lib/common.sh` (safeio wrappers + coproc lock, atomic_write→helper),
`lib/comms.sh` (enqueue transaction, drain rotate/coproc/preserve), `lib/registry.sh`
(state_get/state_jq/journal → no-follow), `lib/faculty-bg.sh` (pidfd-only reap),
`tests/window-alloc.sh` (new section H, 18 checks), `tests/faculty.sh` (reap assertion updated),
`.gitignore` (`__pycache__/`,`*.pyc`). **Preserve & EXCLUDE from the commit**:
`bin/fleet-watchdog.sh` (unrelated) and the `_fleet_inject_trace` hunk in `lib/comms.sh`
(unrelated — needs `git add -p` to stage only the mailbox hunks).

### Verified so far (this session)
- `bash -n` clean; `py_compile` clean; `lib/__pycache__` removed + gitignored.
- Helper unit tests: read/append/write no-follow + symlink refusal; write self-heals a symlink,
  refuses dir/fifo/foreign; enqueue transaction + mutual exclusion (blocks while lock held);
  rotate identity-check catches an open→rename swap (rc 6); pidfd signal exact-identity reap.
- Drain: normal delivery, idempotent, malformed-JSON PRESERVED + fail-closed, restore-into-dir
  KEEPS snapshot, restore-with-safeio-down KEEPS snapshot, symlinked inbox not unlinked.
- `tests/window-alloc.sh` **93/93**, stable across 3 runs (section H = 18 new checks).

### Verification at commit (2026-07-15, all green)
- Full suite: smoke 93/93, faculty 99/99, robustness 39/39, config 5/5, liveness 12/12,
  ask-isolation 59/59 (harness needs ambient TOOL_ROOT), window-alloc 93/93 (section H = 18 new).
- Deterministic 60-way concurrent enqueue+drain race: PASS 3/3 — 60 delivered exactly once, no
  loss/tear/double, no leftover temps, mutual exclusion holds under the coproc lock.
- New H checks RED against exact base f9f2947 (isolated worktree, base libs + new test): 12 RED
  in section H, F/G 0 fails (no regression).

### NOT done (next owner / fresh reviewer)
- A fresh EXACT opposite-provider adversarial review has NOT run yet — REQUIRED before any push.
- No push/hooks/deploy/history rewrite performed (per instruction).
### Do-not-assume
- python3 is now REQUIRED for mailbox/state hardening; document in README Prerequisites before commit.
- `_fleet_bg_controller_pids` is now test/diagnostic-only (live reap uses the pidfd helper).
- Leftover `.snap.*` files after a failure are DELIBERATE (mail preservation), not litter.


## Follow-up LANDED (2026-07-15) — `f9f2947` fixes both review findings, local commit only
supervisor-codex GO'd the repairs (initial reviewer died on a safety-policy block; a fresh
exact reviewer will attack the follow-up). **Committed `f9f2947`
`fix(faculty-bg,registry): exact-identity controller reap + symlink-safe path IO`** on top
of `6d19957`. NOT pushed (origin +11). watchdog + `_fleet_inject_trace` still excluded.

### Fix 1 — exact-identity controller reap (finding 1)
`fleet_bg_unmount` no longer builds an id-interpolated `pkill` regex. `_fleet_bg_controller_pids`
(lib/faculty-bg.sh) prefilters with fixed-string `pgrep 'bg-controller'`, then compares the last
`/proc/PID/cmdline` token to the id BYTE-FOR-BYTE. No regex touches the id, so dotted ids can't
collide. Linux-only (/proc); on other hosts it reaps nothing and the tmux window kill is the
teardown. tests/faculty.sh unmount assertion updated (exact identity, no pkill).

### Fix 2 — symlink safety, split by HARM (finding 2)
Bash has no O_NOFOLLOW, so:
- **Truncate/overwrite removed STRUCTURALLY (no TOCTOU)**: `fleet_atomic_write` (lib/common.sh)
  = mktemp + `rename()` over the dest; rename replaces a squatted link, target never written.
  Used by the argv writer (lib/tmux.sh), `fleet_state_ensure`, and session-start's `.session`
  write. The mailbox lock uses APPEND open `9>>` (cannot truncate); flock unchanged →
  **concurrent mailbox correctness preserved** (stress: 60 racing enqueues → 60 valid distinct
  lines, none lost/torn).
- **Reads + appends = BEST-EFFORT check-then-open** (`fleet_path_regular_or_absent`): state
  read (state_get/state_jq), inbox append, journal append. These refuse a PRE-PLANTED symlink
  but are **NOT atomic O_NOFOLLOW**.

### ⚠ RESIDUAL TOCTOU (do-not-assume; disclosed to supervisor)
The read/append refusals above have a residual race: a concurrent same-directory writer can
replant a symlink BETWEEN the `[[ -L ]]` check and the open. Threat model is BOUNDED to a
pre-planted link (a member who can plant, not one racing a tight replant loop). A true fix
needs an atomic no-follow open (O_NOFOLLOW fd), which bash cannot express — would require a
tiny helper binary or moving these writers behind `fleet_atomic_write`-style rename where the
op allows (appends to a shared accumulating inbox do not). This residual is INTENTIONAL and
recorded; a fresh reviewer may escalate it. The truncate/overwrite paths have NO such residual.

### Falsifier proof (both findings, this session)
New tests/window-alloc.sh sections F + G run against a `6d19957` worktree → **8 checks FAIL**
(F0 pkill-regex-present; G1 lock truncation; G2 inbox append-through; G3 journal append-through;
G4 argv write-through + still-symlink; G5 state_get read-through; G6 state_jq read-through).
Fixed tree → **76/76**. Genuine falsifiers, not placebos.

---
## HOLD on 6d19957 (2026-07-15) — [RESOLVED by f9f2947 above]
supervisor-codex's exact review put `6d19957` on HOLD. Both findings reproduced read-only
against ground truth; the scoped follow-up `f9f2947` fixes both. Kept `bin/fleet-watchdog.sh`
+ `_fleet_inject_trace` excluded, no push.

**Finding 1 — dotted-id `pkill` regex collision (in id-hardening scope; refutes my own claim).**
The allowlist admits `.`, but `fleet_bg_unmount` (lib/faculty-bg.sh:168) interpolates the id into
`pkill -f "bg-controller\.sh ${id}\$"`. `.` is a regex metachar. Repro: a decoy whose cmdline is
`bg-controller.sh aXb`; the pattern for VALID id `a.b` MATCHED it → `fleet_bg_unmount a.b` would
`pkill` the wrong controller. This falsifies the E9 comment "no regex metacharacters survive it".
Fix: match by EXACT argv identity (iterate `pgrep 'bg-controller\.sh'` pids, compare
`/proc/PID/cmdline` last token == id) rather than an id-interpolated regex; delete the false claim.

**Finding 2 — symlink follow/truncate, INDEPENDENT of id validity (broader TOCTOU class).**
A pre-planted symlink at `inbox/<validid>.jsonl.lock` is followed by `exec 9>"$f.lock"` and the
out-of-tree target is TRUNCATED (reproduced: `outside/victim.lock` went to 0 bytes with valid id
`core`). Same class: journal `>>`, argv `:>`, inbox `>>`, and state reads all follow symlinks.
Fix: no-follow (`-L` refusal/unlink) + regular-file check + safer create/append across
state/journal/argv/inbox/lock. NB: requires an attacker with state-dir write to plant the symlink,
so it is a distinct capability from crafting an id — real, but a separate class from id→path.

**Falsifiers to add**: (F1) a controller-collision test — spawn a decoy `bg-controller.sh <idA>`,
assert `fleet_bg_unmount <idB>` where idB's regex could match idA does NOT reap the decoy; (F2) a
symlink-lock/journal/argv/inbox test — plant a symlink to an out-of-tree victim, call the writer,
assert the victim is untouched. Both must FAIL against 6d19957 and pass fixed.

## Current objective — member-id path-hardening LANDED (2026-07-15), local commit only [ON HOLD]
**Committed `6d19957` `fix(registry): fail closed on member-id -> path derivation everywhere`.**
Branch `fix/fleet-robustness-batch`, parent `0ab4a0e`. NOT pushed (origin +8 ahead).
6d19957 remains a NET IMPROVEMENT (closes the traversal/phantom class) but is INCOMPLETE per the
two findings above — do not push until the follow-up lands.

### What landed (scope)
A member id is interpolated into paths (`state/<id>.json`, `run/<id>.{session,exit,argv}`,
`inbox/<id>.jsonl`, `memory/<id>.md`), a tmux window name, and a `pkill -f` regex. Validation
used to live ONLY in `fleet_state_ensure`, which an existing file short-circuits and which the
launch path reached only AFTER creating/destroying artifacts. Central choke point now in
`lib/common.sh`: `fleet_valid_member_id` (ALLOWLIST `[A-Za-z0-9._-]+`), `fleet_member_path` /
`fleet_run_path` (print nothing + return 1 → callers fail CLOSED on status), `fleet_require_member_id`
(`die` at argv boundaries). All state/run/inbox/journal/memory builders route through it; every
call site handles the non-zero status so `set -euo pipefail` does not turn hardening into a
fail-FATAL regression (doctor must survive a live `--help` phantom).

### Verified state (all re-run 2026-07-15, this session)
- **Falsifier proof**: new `tests/window-alloc.sh` section E run against unfixed `0ab4a0e` in a
  throw-away detached worktree → **27 checks FAIL** (state_jq MUTATED an out-of-tree doc; state_path
  traversal; journal escape; state_get out-of-tree read; argv-file RUN_DIR escape; start_child
  DELETED an out-of-tree file; window created for invalid id; enqueue wrote inbox outside; the whole
  `.*`/`$(id)`/`a|b`/backtick charset-mutation class accepted by the old denylist). Fixed → **65/65**.
  NOT a placebo suite.
- **Staged-tree proof**: stashed the unstaged remainder with `--keep-index` and ran suites against the
  index alone — smoke **93**, window-alloc **65**, faculty **99**, robustness **39**, config **5**,
  liveness **12**, ask-isolation **59** (ambient `TOOL_ROOT`). Equal baseline. Restored cleanly.
- `bash -n` clean on all 12 modified files. Completeness scan: no raw id→path interpolation remains
  outside a comment; no `local x="$(helper)"` status-discarding call site.

### Deliberately EXCLUDED from the commit (still dirty in working tree — do not assume abandoned)
- `bin/fleet-watchdog.sh`: **wholly unrelated** — doctor edge-trigger normalization (strips volatile
  `Ns old` / `stale by Ns` / inject-failure counts before the change-compare). Separate concern.
- `lib/comms.sh` `_fleet_inject_trace` hunk (guards a stale `FLEET_INJECT_TRACE` dir): unrelated;
  left unstaged. Only the 3 MAILBOX hunks (`fleet_inbox_file`, `fleet_enqueue`, `fleet_drain_inbox`)
  were committed, because E8/E11 direct-primitive safety depends on them.

### Next actions
- Get an opposite-provider twin (codex) to challenge `6d19957`: strongest open attack is a
  concurrent-writer race on `fleet_enqueue`'s fail-closed path, and the allowlist against any
  legitimate non-ASCII id shape a real deployment might use.
- Decide the fate of the two excluded hunks (own commits or drop) before any push.
- Await explicit authorization before pushing.

---
## (Prior objective, retained) #66 window allocator
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
