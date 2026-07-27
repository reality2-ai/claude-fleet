# RESUME — claude-fleet (supervisor)

**Rewritten whole 2026-07-27 evening.** Not patched — the previous snapshot was ~20 hours old and
described the OTA blocker as *"the identity write, gated on two partition questions."* **Both
questions are answered and the blocker has moved somewhere else entirely.** Every figure below is
re-derived at write time rather than carried forward.

## Where the work actually stands

**The OTA round-trip is still not done, and the blocker is no longer what it was this morning.**

It was: *provision X1, then push image B.* It is now: **the persona must live in a declared region
before anything is provisioned** — because Roy ruled the raw-offset write non-conformant, which
made *provision-or-hold* the wrong question. Provisioning at the raw offset would mean
**provisioning twice**, and the second write lands on a board that already holds a valid identity
— the exact case our own rules say **stop and escalate** on.

**What that turned into:** a lockstep change across **six raw fixed-offset firmware reads**, a
partition table that **freezes at deployment** (a table cannot go over the air — confirmed from the
tooling, not assumed), and a shipping gate: **every bench-reachable board gets the final table plus
named-lookup firmware before it deploys.**

**Ratified geometry:** 14 sectors, `0x12000`–`0x20000`, **four in-place anchors, one moving part**,
**byte-identical across both carriers.** Persona stays at `0x12000` because **relocating a
provisioned persona is a membership break, not a flash operation.**

**And a live defect found on the way, worse than the one we were fixing:** the persona **write path
is not atomic** — in-place write plus read-back verify, so a power loss mid-write is a **torn
persona**, on every board today, independent of the migration. **An unclaimed region is a hazard; a
torn persona is a loss.** The fix already exists unused in the tree.

## Board state

- **X1** — image A in `ota_0`, **untouched**, NVS preserved, unprovisioned. Not in any live grant.
- **Two DFR1195s** — newly on the bench. **Table-read grant written and dispatched**: read-only,
  offset `0x8000`, **length exactly `0x1000`**.
- **RAK** — frozen (#d003). Roy reaffirmed: *"an exception, not the rule."*

**The read exists because `flash-board.sh` changed mid-session.** A board flashed before that fix
has its persona in an unclaimed gap; one flashed after does not. **Neither the repo nor the commit
history can say which a given board carries.**

## Standing bars that have not moved

- **No identity write** until the region is declared and `read_persona` resolves by name.
- **Hard-fault on absent region, no raw fallback** — and the fix for the field is to **refuse the
  image before applying it**, not to soften the fault.
- **Table first, firmware second.** Reverse it and the boot bricks.
- **No NVS dump.** The table read's length is the safety property: `0x8000 + 0x1000 = 0x9000`,
  which is exactly where NVS begins. **One sector of overrun reads key material.**
- **Two identical DFRs**: efuse MAC per board, never the value. *Reading one board twice is
  indistinguishable from reading two boards once.*

## Open for Roy

**g24** (synthetic AP — ruled, pending review) · **g21** (dedup key — canon already ruled it; one
premise survives) · **g8** (client isolation — three fixes, two minutes) · **name the complex-Hive
Xiao**, which is in no lane's records.

**Three architectural, none blocking:** ring-signature vs no-global-roster · maintainer-machine key
concentration · whether field units should be remotely readable at all.

**Closed today:** g23, g26, g27.

## What did NOT advance, said plainly

**The overnight directive — five capabilities as ensembles, and the OTA round-trip — is roughly
where it was this morning.** Nine of ten scores still fail the grammar validator. The gate is
**core's five-item schema change**, which sits behind the torn-persona fix.

**That ordering is a choice I made**: a defect that can lose a provisioned identity, ahead of the
thing that was asked for. Worth re-examining rather than inheriting.

## The pattern of the day, because it will recur

**Eight gates that could not see their subject, across six lanes, every one of them green:** a
schema catch-all absorbing what it should reject · a symbol matcher with no false-present guard · a
build-feature block never parsed · a test asserting its own copy · a hygiene scanner whose paths
excluded the ledger · a boolean that destroyed a distinction upstream · **a hardfail gate nothing
invoked at push time** · and a header gate that **proved a row existed and never proved it was in
the changelog.**

**Only one of those was fixed by a mechanism rather than another check**, and that is the one worth
copying.

**The question to ask of any gate: what weaker question could this be answering while still
returning green?**

## My own errors, kept because the pattern is the finding

I asserted a canon divergence that did not exist and broadcast it to three lanes · attributed a
scanner defect to the wrong lane and could not pin it when challenged · called a finding fleet-wide
when it was carrier-split and then time-split · **used *membership* as the criterion for *internal*
three times after being corrected explicitly** · relayed a commit hash as a verification target
without opening it · and **audited this repo for addresses and credentials while never checking the
host-name class that turned out to be in the ledger, the gate index, and a filename.**

**Every one was caught because a lane went and looked instead of taking the relay.** Two lanes also
**refused an over-broad self-blame from me**, which is the harder direction and left the real defect
visible.
