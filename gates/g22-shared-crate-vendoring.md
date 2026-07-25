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
class. A policy argued from "three" would have left **six copies outside its own blast
radius**.

Both lanes caught it and corrected themselves before you ruled. I recorded it as wholly my
error; **specs declined the absolution** and asked for it to read as shared, on the grounds
that it ran the search and owns its scope — it could have asked whether three was the
population. That is the more useful version, so it stands as shared.

Shared crates are **vendored per repository with no shared source**:

| crate | copies | distinct contents |
|---|---|---|
| `r2-trust` | **nine** | **six** — corrected again; see the whole-crate note below |
| `r2-dataplane` | **five** | **four** — only core's carries the g15 fix (join-carry: core 11, all four others 0) |

**The pairing is itself evidence, and it is good news — and it survived the whole-crate
recount, which I checked rather than assumed.** Nine copies resolve to **three exact pairs and
three singletons**. That looks like a handful of sync events, not nine independent forks, which
probably makes the vendoring model tractable rather than hopeless. (I verified the pairs
whole-crate, with a known-different pair as a control to prove the comparison could see a
difference.)

Neither anthill nor r2-composer path-deps core's copy; both point at their own local
`crates/r2-trust`. Core's is not upstream of anything.

**This contradicts the stated R2 map principle: core is sole-canonical, downstream never
forks.** In practice downstream has forked, quietly, and the forks are already divergent.

**Not every copy is a defect.** Core has since classified the class, independently
re-enumerating rather than trusting the handed set, and reporting that it had under-sized the
gate the same way I did.

**I had written that its figures *matched* specs', and offered the agreement as corroboration.
Striking that, not just correcting it.** The two lanes agreed because they ran the **same
partial check** — both hashed `src/lib.rs` alone. Core could not have disagreed. The
concordance carried **zero information** and this brief was presenting it to you as
confirmation. Specs caught it, and caught it as an instance of the very rule this gate
produced: *an agreement test carries information only if disagreement was possible.* The
number was wrong **and the reason it looked trustworthy was wrong**, which is the worse half.

## It is not nine-way chaos — but the classes are **per crate, not per repo**

Core's first classification was repo-keyed. Specs caught that this is false at the crate
level, core re-verified and agreed, and **the corrected shape is a (repo × crate) matrix**:

| class | state |
|---|---|
| **In sync** | **one copy only** — a forensic snapshot that matches canon whole-crate, by design. Under the old `lib.rs`-only check this group looked larger |
| **Deliberate vendor / deliberate pin** | one explicit vendor commit, zero unique lines, four behind. Two more are an **explicit security re-vendor pin** — the bench firmware is *intentionally* pinned, and its commit gap **is the pin**, not drift |
| **Stale, none on the bench** | two May initial-commits; one March copy that has grown its own join-code content |

**The trap, and it is a sharp one.** One repo re-vendored *both* crates on the same day. Its
trust copy equals canon — but **only because canon's trust crate has not moved since**. Its
dataplane copy, the crate that *did* move (it gained the g15 fix), is the pre-g15 pin. So:

> **A content match on a crate that never changed is not evidence of sync.** It is evidence
> of nothing having happened. A repo-keyed obligation would mark that repo *needs nothing*
> while its crates sit at distinct variants.

This is why the obligation you rule must key on **(repo, crate, pinned-core-sha)**. Repo-level
is not a coarser version of the right answer; it is the wrong answer.

**And one level further down: the comparison was one file, not the crate.** Both lanes had
been hashing `src/lib.rs` alone. Specs re-ran it whole-crate and found a repo whose `lib.rs`
is byte-identical to canon while **two other files in the same crate differ** — so the trust
count is **six** distinct contents, not five, and that repo leaves the in-sync group. Only one
copy survives a whole-crate match.

Same shape as the finding above, one level down: **a match on one file is not evidence about
the crate**, exactly as a match on an unchanged crate is not evidence about the repo. In both
cases the check's *scope* was narrower than the *claim* it was used to support.

### I verified the severity myself, and it is much lower than first reported

Specs flagged this as security-core drift — the differing files hold the key-derivation and
HMAC code, including the two functions the whole g15 join argument was reasoned against. That
would be serious, so I checked it directly rather than relaying it.

**The production code is byte-identical.** Both diffs fall entirely inside the test modules:

- one file: canon **gained 78 lines of provenance tests** the day *after* that repo vendored;
  the copy is not wrong, it is one day older. (I first wrote 84 — that was the diff hunk's
  length, not the count of added lines. Specs re-derived 78 independently while checking my
  refutation, and 78 is right.)
- the other file: **a single comment line** inside a test.
- The two g15-critical functions are byte-identical and at **the same line number** in both.

Method: compared the pre-`#[cfg(test)]` region of each file, with the test region as a
negative control to prove the comparison could see a difference at all. It could.

**So: no board is running key-derivation or HMAC code that differs from canon.** Specs' method
finding stands and is valuable; its severity claim does not, and I am not escalating a second
gate on it.

**Specs then verified my refutation itself and withdrew its own claim** — declining to accept a
favourable answer on trust, on the grounds that taking relief unverified is the same error in
the pleasant direction. It reproduced the region hashes independently. It also reported that
**its first negative control was vacuous**: it sampled a line range that could not contain the
difference, got "identical", and would have "confirmed" my refutation with a comparison
incapable of disagreeing. It caught that mid-check and re-ran at the right range. A control
that cannot fail is not a control.

**The security-relevant copy — the one on the bench — is in the deliberate-pin class and is
safe today.** Every non-core dataplane copy predates g15, so none of them can carry a join.
Nothing to hot-fix.

Core then took the check a third level down — past whole-crate hashing to **the function bodies
themselves** — and confirmed it independently: on *both* bench boards, every derivation and HMAC
function is byte-identical to canon. So the g15 derivation is intact on metal.

### The one residual that is real, and it is not crypto

Core found a genuine gap while clearing the false one, and I verified it myself: **the active
bench pin is missing a whole source file** — the capability-grant module. Canon has it; the
bench copy does not, and the symbol appears in zero of its files. Same for the group-management,
join and certificate code, which are older there.

That is a **feature and interop gap, not a key-derivation gap** — a consequence of the
deliberate pin, resolved at the next re-vendor. Worth knowing because it means the bench cannot
exercise capability grants at all, which is a different statement from "the bench is behind".

## Two things that make it worse than ordinary drift

**The version signal is dead.** **Every** copy declares `version = "0.1.0"` while being six
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
  detector that works — **per-(repo, crate) content hash**, since the version string is dead on
  every copy; **(b)** a standing **re-vendor obligation** keyed on **(repo, crate,
  pinned-core-sha)** that carries the g15 dataplane fix and the identity half to the bench pin at
  the next flash; **(c)** explicit *consumer* / *sync-on-demand* labels on the three stale copies,
  so their lag is **known state rather than something rediscovered**.
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
in `r2-trust`, and landing it in one of **six divergent variants** is exactly the risk. It also
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
