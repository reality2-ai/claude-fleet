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

**Not every copy is a defect.** Core has since classified the class — independently
re-enumerating rather than trusting the handed set, and reporting that it had under-sized the
gate the same way I did. Its figures match specs': nine trust copies in five variants, five
dataplane copies in four.

## It is not nine-way chaos — it is three classes

| class | copies | state |
|---|---|---|
| **In sync, no action** | 3 | the core source, a forensic snapshot that matches *by design*, and one board's worktree |
| **Deliberate vendor / deliberate pin** | 3 | one explicit vendor commit, zero unique lines, four behind. Two more are an **explicit security re-vendor pin** — the bench firmware is *intentionally* pinned, and its 57-commit gap **is the pin**, not drift |
| **Stale, none on the bench** | 3 | two are May initial-commits; one is a March copy that has grown its own join-code content |

**The security-relevant copy — the one on the bench — is in the deliberate-pin class and is
safe today.** Nothing to hot-fix. That is core's judgement after a full sweep, not an
assumption.

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

The classification changes what is actually on the table. **A sync mechanism already exists** —
the vendor and re-vendor commits are real, deliberate and dated. Three things are missing from
it, and core recommends supplying those rather than re-architecting:

- **Fix the mechanism you already have** *(core's recommendation)*. Three parts: **(a)** a drift
  detector that works — per-crate version bumps, or a content-hash manifest, since the version
  string is dead; **(b)** a standing **re-vendor obligation** that carries the g15 dataplane fix
  and the identity half to the bench pin at the next flash; **(c)** explicit *consumer* /
  *sync-on-demand* labels on the three stale copies, so their lag is **known state rather than
  something rediscovered**.
- **Path-dep the canonical crates.** Downstream points at the core lane's `crates/*`. Matches
  the stated principle and kills the class permanently — but it **dissolves the deliberate
  security pin**, which was chosen for a reason. Every downstream also inherits core's churn.
- **Accept the forks deliberately** — declare each an independent implementation with its own
  owner, and stop calling core canonical for those crates. Honest, but a different architecture
  from the one the map states.

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

## Supervisor lean — **revised, and I am saying why**

**Fix the mechanism.** I previously leaned path-dep-the-canonical-crates, dataplane first. That
lean was formed when the picture was "nine divergent copies with a dead version signal". Under
the classification it is wrong: **path-dep would dissolve a deliberate security pin** that was
chosen on purpose, and it would be me overriding a decision I had not known existed.

What is actually broken is narrower — no drift detector, and no standing obligation to carry a
landed fix to the pin at the next re-vendor. Both are supplyable without changing the
architecture. The one thing I would add to core's three: **the re-vendor obligation should be
written where the flash gate can see it**, or it is prose again.

## Ruling syntax

"gate 22: fix the mechanism" / "gate 22: path-dep canonical" / "gate 22: accept the forks"
