# Gate 22 — shared crates are vendored per-repo, and it already broke a ruling

**Status:** 🔴 OPEN — **blocks the g15 identity half**; contradicts a stated R2 principle
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g22 and the Cargo manifests it names"*

## The live consequence, first

**Your g15 ruling has been implemented in a crate the firmware does not build from.**

Core landed the dataplane half of join carriage in the core lane's `crates/r2-dataplane`. The
firmware builds against **its own vendored copy** —
the firmware worktree's `platforms/<board>/Cargo.toml:19 → path = "../../crates/r2-dataplane"`.

Verified: the new signal appears **10 times** in core's copy and **0 times** in the firmware's.
So the change is real, tested, ledgered — **and does not reach metal.** Nobody did anything
wrong; the dependency graph simply does not connect them.

## The general shape — **corrected: it is nine copies, not three**

The first version of this brief said three. That number came from **me**: I handed specs a
named set of three trees and it verified exactly those three, rather than enumerating the
class. Specs caught it and corrected itself before you ruled. A policy argued from "three"
would have left **six copies outside its own blast radius**.

Shared crates are **vendored per repository with no shared source**:

| crate | copies | distinct contents |
|---|---|---|
| `r2-trust` | **nine** | **five** — one shared by three repos, one by two, three singletons |
| `r2-dataplane` | **five** | only core's carries the g15 fix (join-carry: core 11, all four others 0) |

**The pairing is itself evidence, and it is good news.** Three pairs agree *exactly*. That
looks like a handful of sync events, not nine independent forks — which probably makes the
vendoring model tractable rather than hopeless.

Neither anthill nor r2-composer path-deps core's copy; both point at their own local
`crates/r2-trust`. Core's is not upstream of anything.

**This contradicts the stated R2 map principle: core is sole-canonical, downstream never
forks.** In practice downstream has forked, quietly, and the forks are already divergent.

**Not every copy is a defect.** One firmware tree is a *forensic snapshot* by name and matches
core exactly; another reads like a pinned experiment. Some variants are surely intentional.
Which are by-design vs stale vs forked is core's classification, not specs' and not yours —
specs deliberately supplied the denominator only.

## Two things that make it worse than ordinary drift

**The version signal is dead.** **Every** copy declares `version = "0.1.0"` while being five
different implementations. Specs' standing cross-repo drift check is a **version-gap
comparison** — chosen precisely because it is race-proof where byte-identity is not — and it
is **blind here**. Content hash is the only detector that works. A drift detector that cannot
distinguish these trees is not a detector for them.

**And "stale" is the wrong word, which is why I did not use it.** Stale implies one is behind.
Mutually-different hashes with identical declared versions is **forked-or-drifted with no
signal to tell you which**.

## The decision

- **Path-dep the canonical crates.** Downstream points at the core lane's `crates/*`. Matches the
  stated principle, kills the class permanently. Costs: cross-repo path dependencies, and
  every downstream inherits core's churn.
- **Define an explicit sync procedure.** Keep the copies, add a mechanical check that a copy
  matches canon at a declared version — which means versions must actually move, since the
  current signal conveys nothing.
- **Accept the forks deliberately** — declare each an independent implementation with its own
  owner, and stop calling core canonical for those crates. Honest, but it is a different
  architecture from the one the map states.

## The bench is safe, and this is on the record before anyone reaches for it

An unfixed vendored dataplane **cannot carry a join at all** — it drops origin-less frames
unconditionally. That is precisely the safe intermediate state: **zero-hop joins work, and
zero-hop is the intended case you ruled.** Nothing on the bench is broken by this.

The real risk is the opposite one: a well-meaning lane "fixing" the bench firmware under
pressure and creating the **half-carriage** path every lane agrees is worse than none. The
obligation is at the next vendored sync. **Not a bench hot-fix.** Specs asked for this to be
stated ahead of time rather than argued later, and it is right to.

## What is blocked meanwhile

Core will **not** start the g15 identity half until this rules — correctly. That work lands
in `r2-trust`, and landing it in one of **five divergent variants** is exactly the risk. It also
declined to treat this as maintenance, which is the right instinct: **integration is a
decision, not housekeeping.**

Note this is **not** fixed by merging branches. The copies live in different *repositories*;
a branch merge carries nothing between them.

## Supervisor lean

**Path-dep the canonical crates for `r2-dataplane` first, then `r2-trust`.** The dataplane
case is not hypothetical — it is already swallowing a ruling you made this morning. Trust can
follow deliberately, since drifting a *trust* crate is the one with real consequences.

## Ruling syntax

"gate 22: path-dep canonical" / "gate 22: sync procedure" / "gate 22: accept the forks" / "gate 22: dataplane now, trust later"
