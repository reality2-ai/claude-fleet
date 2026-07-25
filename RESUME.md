# RESUME — claude-fleet (supervisor)

**Updated 2026-07-26.** Takeover snapshot. Every figure below was re-derived from the
repo at write time, not carried forward from the previous version — the file it replaced
was three days stale and still presented a closed campaign as the current objective.

## Objective right now

**Nothing is executing. Every lane is blocked on a Roy ruling, and that is correct.**
The work of the day was a gate arc plus a long method exchange, not code. Do not start
work to fill the gap — the blocks are deliberate.

## Repo state — ground truth

- Branch `gate-heredoc-2026-07-20`. **13 commits unpushed.** Tree clean.
- **The unpushed state is deliberate**: pushing is the exact action gate 23 is about.
  Do not push until Roy rules g23.
- Remote `master` deliberately lags this branch (merge is a later Roy-gated step).
- Ledger tail: `D-20260726-S12`. Twelve supervisor entries today.

## Open gates — all waiting on Roy

Full briefs in `gates/`, index in `ROY-GATES.md`. Five open: **g23, g22, g21, g13, g8**.

- **g23 — this repo is public.** `reality2-ai/claude-fleet` is public (verified from the
  API). No keys, MACs or personas — that guard held. Exposed: four private repo names,
  one private branch name, ~93 commit-id-shaped tokens in the ledger. Private names
  scrubbed **forward**; published history untouched because removing it needs a
  force-push, which is forbidden without an explicit lift.
- **g22 — shared crates are vendored per-repo.** Blocks the g15 identity half. Roy's g15
  dataplane fix landed in core's crate; the firmware builds from its own vendored copy,
  so the ruling does not reach metal. Nine trust copies / six contents; three classes
  (in-sync, deliberate-pin, stale). **Bench is safe** — an unfixed copy cannot carry a
  join at all, which is the intended zero-hop state. Obligation must key on
  **(repo, crate, pinned-canon-sha)**. Supervisor lean: fix the mechanism that exists.
- **g21 — dedup key.** Canon already ruled it normatively. One narrow question survives.
- **g13 — radar board-fit.** Physical; Roy eyeballs it after soldering.
- **g8 — AP client isolation.** Small, not urgent.

## Live grant

`.fleet/flash-authorization` holds a **read-only debugger grant** (`target=D5-037bf5b9`,
`artifact=jtag-read-callback-baseline`). Authorises ONE session: breakpoint, read memory,
detach. **No flash, no write, no erase.** Operator is composer. **Roy must be on-hand** —
a dropped session likely leaves the board dark and recovery is a physical reset.

**g18 artifacts are built, attested and eligible — and the flash is WITHHELD by me** until
that debugger session closes. One grant at a time. Hive has been told not to ask again.

## Standing bars in force

- **No bench hot-fix of the vendored dataplane.** An unfixed copy cannot carry a join,
  which is the safe intermediate state. The fix lands at the next re-vendor.
- **Identity half of g15 held** until g22 rules. A half-carriage is worse than none.
- Reset rules unchanged: `espflash reset` FORBIDDEN on S3; raw tty RTS/EN is not a reset
  on this chip; permitted resets are `espflash monitor` CTRL+R or Roy's physical button.
- One serial opener (composer). Core scores from the score log only.

## Known-state, not incidents

- The active bench pin **lacks the capability-grant module entirely**; group-management,
  join, certificate, provisioning and revocation code is older there. **Feature/interop
  lag from a deliberate pin, due at the next re-vendor — not an incident.**
- Crypto verified byte-identical to canon on **both** bench boards, checked directly.

## Method earned today — five rules, all paid for

1. **Ask what a command prints when it is BROKEN.** If that equals what it prints when the
   finding is absent, the check is worthless before it runs. Four false greens today share
   that root; three lanes, none caught by its own author.
2. **Scope mismatch in either direction.** Broader-than-claim over-alarms as much as
   narrower under-detects. Name the unit the claim is about, then measure that one —
   file / crate / line-number / function-body, and three of those four answer confidently
   wrong.
3. **A retraction is done when it reaches every artifact carrying the claim**, not when it
   is issued. It does not reach the artifact you read from, and it does not reach the other
   paragraphs of the artifact you edited. **Proximity is not protection.**
4. **Unwarranted until re-derived.** A claim whose source method was discredited is not
   automatically wrong, but it carries no warrant until recomputed.
5. **A verification list is itself a claim.** Per-item control, not aggregate;
   confirm-exists before diffing; **absent ≠ uncalled**; build the list from the tree, not
   from an API template.

## Next action for whoever takes over

**Wait.** Check `fleet brief` and the inbox, relay any Roy ruling to the owning lane, and
otherwise hold. Do not push, do not flash, do not start the identity half, do not
re-litigate g22 — it is verified as far as it can go without a ruling.
