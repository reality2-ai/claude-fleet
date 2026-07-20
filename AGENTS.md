# AGENTS.md — claude-fleet

Control plane for multi-repo coding agents: lifecycle, tmux, state, mail, conflicts,
context health, decision latch, handoff, and provider failover. It is not an R2
implementation. Read `README.md`; running state lives in `RESUME.md`.

## Authority and ownership

- R2 behaviour authority is `r2-specifications -> r2-core -> downstream`. Never put
  protocol logic here.
- Default topology: one supervisor, one writer per manifest repo. Persistent twins are
  opt-in and read-only until explicit handoff.
- `.fleet/fleet.toml` is membership authority. Parse through `lib/manifest.sh` or TOML
  parser, never regex/grep. Whitespace is valid TOML and grep can silently omit members.
- A Git worktree inherits parent repo writer. Check `.git` indirection before calling an
  unlisted directory unowned.
- Supervisor coordinates. It edits this repo only; repo workers own their trees.

## Method

- Verify code, state, process, git, and tests before relaying claims.
- Treat patch and review claims as conjectures. Seek strongest concrete falsifier.
  High-risk control/security change SHOULD receive one bounded independent refutation,
  then converge. Unsupported cautions park.
- Prefer smallest mechanism meeting demonstrated need. Add state/process/prompt only
  when simpler existing surface cannot solve problem.
- Conflicts are detection-only; report owners and paths, never edit around them.
- Destructive lifecycle, force-push, tree deletion, firmware/key actions, or bypassing
  gates requires explicit authority.

## Control invariants

- The fleet ledger controls live gates; durable repo rulings live in `DECISIONS.md`.
  Read it before changing established behaviour. Record key rulings and consequential
  agent choices with the real decision-maker, authority basis, rationale, and evidence;
  append later reviews without rewriting history.
  Challenge changes confidence only; authority revoke or successor changes action.
  Never impersonate authority. Newer explicit human instruction and safety gates apply.
- `RESUME.md` is one concise current takeover snapshot, not diary. Handoffs are bounded
  orientation packets; target re-verifies ground truth.
- Prompts stay terse. One rule lives once; do not preserve superseded instructions in
  active context—Git is history.
- Mail is hop-capped and off-thread asks MUST NOT hijack live worker state.
- Safe state/mail IO fails closed on symlinks, malformed IDs, or unavailable primitive.
- Default startup MUST NOT multiply agents. Refuters and warm standbys are on-demand.

## GitHub recovery

Stage task-owned named paths only—never user/peer/unrelated dirt. Commit verified
increments and non-force-push upstream. Before idle/done, verify no local commit remains
ahead. A published commit updates `DECISIONS.md`, cites governing `Decision-Log: D-...`,
or says `Decision-Log: none` for routine work. Report push blockers; never force-push or
bypass gates. Ahead-zero does not prove fetch freshness.

## Verification

Run `tests/smoke.sh` for lifecycle, authority, mail, decisions, hooks, and handoff.
Use focused tests for changed subsystem plus `bash -n`, `git diff --check`, and relevant
robustness/runtime scripts. Test failure is evidence; do not weaken a gate to pass it.

## Communication

Terse, evidence-led: finding, path/command, consequence, fix. Preserve exact errors,
values/units, SHAs, and falsifier. Human documentation and code comments remain clear
prose. Full reasoning method: `docs/grow-strong-ideas.md`.
