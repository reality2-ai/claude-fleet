# Gate 22 — shared crates are vendored per-repo, and it already broke a ruling

**Status:** 🔴 OPEN — **blocks the g15 identity half**; contradicts a stated R2 principle
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g22 and the Cargo manifests it names"*

## The live consequence, first

**Your g15 ruling has been implemented in a crate the firmware does not build from.**

Core landed the dataplane half of join carriage in `r2-core/crates/r2-dataplane`. The
firmware builds against **its own vendored copy** —
`dfr1195-fw-wt/platforms/dfr1195/Cargo.toml:19 → path = "../../crates/r2-dataplane"`.

Verified: the new signal appears **10 times** in core's copy and **0 times** in the firmware's.
So the change is real, tested, ledgered — **and does not reach metal.** Nobody did anything
wrong; the dependency graph simply does not connect them.

## The general shape

Shared crates are **vendored per repository with no shared source**:

| crate | copies | state |
|---|---|---|
| `r2-trust` | **three** — r2-core, anthill, r2-composer | three different `lib.rs` hashes, three different file counts, **all three declare `version = "0.1.0"`** |
| `r2-dataplane` | two — r2-core, firmware worktree | different hashes; firmware copy lacks the g15 fix |

Neither anthill nor r2-composer path-deps core's copy; both point at their own local
`crates/r2-trust`. Core's is not upstream of anything.

**This contradicts the stated R2 map principle: core is sole-canonical, downstream never
forks.** In practice downstream has forked, quietly, and the forks are already divergent.

## Two things that make it worse than ordinary drift

**The version signal is dead.** All three trust copies declare `0.1.0` while being three
different implementations. Specs' standing cross-repo drift check is a **version-gap
comparison** — chosen precisely because it is race-proof where byte-identity is not — and it
is **blind here**. A drift detector that cannot distinguish these trees is not a detector for
them.

**And "stale" is the wrong word, which is why I did not use it.** Stale implies one is behind.
Three mutually-different hashes with identical declared versions is **forked-or-drifted with
no signal to tell you which**.

## The decision

- **Path-dep the canonical crates.** Downstream points at `r2-core/crates/*`. Matches the
  stated principle, kills the class permanently. Costs: cross-repo path dependencies, and
  every downstream inherits core's churn.
- **Define an explicit sync procedure.** Keep the copies, add a mechanical check that a copy
  matches canon at a declared version — which means versions must actually move, since the
  current signal conveys nothing.
- **Accept the forks deliberately** — declare each an independent implementation with its own
  owner, and stop calling core canonical for those crates. Honest, but it is a different
  architecture from the one the map states.

## What is blocked meanwhile

Core will **not** start the g15 identity half until this rules — correctly. That work lands
in `r2-trust`, and landing it in one of three divergent copies is exactly the risk. It also
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
