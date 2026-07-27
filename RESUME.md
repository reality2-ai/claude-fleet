# RESUME — claude-fleet (supervisor)

**Rewritten whole, late 2026-07-27.** Not patched. The previous version was written earlier the same
evening and was already wrong in four places — which is the finding this whole session produced, so
leaving it patched would have been the joke telling itself. Every figure below re-derived at write
time.

## What actually happened tonight

**Almost none of the overnight directive advanced. What happened instead was an instrument audit that
found nine ways a green result meant nothing, and two live processes nobody knew were running.**

That was the right trade and I would make it again: **if the instruments are fake, every result
underneath them is unwarranted.** But it is a substitution, not progress on the plan, and it should
read as one.

## Board state — re-derived

- **D4** — identified **non-destructively** (passive console, no reset, three-way identity agreement).
  Runs `coex.iter9.0723`. **No lane holds a flash record for that image.** Three readings, none
  chosen: an unrecorded flash, a wrong record, or a pre-custody carry.
- **D5** — port **free**. Last recorded image is a coex diagnostic build; **off-bus state was never
  live-verified**, so that is a record, not a measurement.
- **X1 / the radar Xiao** — image A, untouched, unprovisioned. **D4 is provisioned and X1 is not** —
  a real asymmetry, now recorded.
- **RAK** — frozen (#d003). A rebuild of the #d001-passing reference happened under my order:
  **staged, never flashed.**

**Rig map:** three rows efuse-confirmed, seven marked **unverified assertions**, one flagged and
untouched because it differs from a confirmed row by a single byte — same-batch neighbour or
transcription error, **opposite remedies, only a physical board settles it.**

## Resolved tonight, with the reasoning that matters

- **#d001 STANDS, confirmed by rebuild-and-compare.** Determinism proven *first* (same sha built
  twice, byte-identical), then the override-bearing commit reproduced the flashed image exactly and
  the pre-fix commit reproduced the *stale* image — a corroborating negative, not a bare non-match.
  **Citable for that image digest and nothing else.**
- **The mesh failure is a re-vendor lineage regression.** Mechanism named: a **tree re-export**, which
  orphans hand-edits to the platform tree — exactly where the lost fix lived. Audit bounded to the
  firmware surface after rejecting a 43k-line false denominator: **one behavioural drop (restored),
  one superseded narrowing, rest cosmetic.**
- **The canon board-class bar reaches nothing on the bench.** Attested at pinned refs, twice, for two
  different images. The second attestation refuted the hostile reading **from call-site absence** —
  structural, not documentary. **Recorded as pinned, not permanent.**

## Open — and the first one is the only live anomaly

1. **The bench mesh is UNDIAGNOSED again.** Its root cause (a spreading-factor split) rested entirely
   on a metric read as *data rate* that actually means *frames dropped* — and the inference ran
   **backwards**, since zero drops is what the fast setting predicts. **Not refuted: unsupported.**
2. **D4 runs an image nobody records flashing.** Unresolved by design; no reading chosen.
3. **Five capabilities as ensembles / OTA round-trip** — where they were this morning.

## For Roy

**Physical:** D5 into manual download mode (port now free) · **bind which Xiao is the radar board** and
name the other — the persona mint is held on it, and will not be written to any board regardless.

**Gates:** **g24** (a supervisor *recommendation awaiting review* — **not a closure**; two lanes read
it as closed today and that was my wording) · **g21** (structural placement only) · **g8**.

**Canon:** he named **three** bulk OTA carriers; canon enumerates two. If the third joins, the
profile's five properties are AP-phrased and must be re-expressed as properties of the **bearer**.
Unauthored, deliberately.

**Standing:** ring-vs-roster · maintainer-machine key custody · **whether the android repo gets CI at
all** — it has none, so it is the one lane that cannot make the CI-verified claim.

## Bars that have not moved

No identity write until the persona region is declared and lookup resolves by name · **table first,
firmware second** · no NVS dump · **efuse per board, never the value** · #d005 build gate ·
**grants now archived to `grant-history/` before overwrite** — the unversioned grant file destroyed
provenance **twice today** before that was fixed.

## The pattern, because it is the whole session

**Nine distinct ways a green meant nothing**, all printing success: the scan errored and the wrapper
called it a pass · nothing printed, so an empty range looked like a full one · the control was aimed
at a file the gate never opens · at an argument the script ignores · at the wrong input channel · at
the wrong working directory · at a command that never ran · a cached number reported without running
anything · and a guard that **under-implemented the rule it was written from**.

**Eight mis-aimed first controls, across every lane including me.** The remedy is identical every
time: **assert the reason, not the exit code — and where exits are graded, assert which code.**

**And the unifying name, supplied by a lane:** *shape is not provenance* — **an artifact that looks
like the output of a process nobody verified ran.** A lease-shaped address. A roster label. A declared
feature. A short hex string. A green scan. A field name abbreviating something else.

## My own errors, kept because the pattern is the finding

I escalated a peer's correctly-scoped finding into a false canon non-conformance and dispatched it to
three lanes · applied an attestation of one image to a board running another, **hours after ruling
that exact distinction at someone else** · read a lease-shaped address as evidence of a lease ·
excused a repo from a CI check **because it had none** — exemption by absence, the form I had ruled
against that morning · wrote *"OPEN: nothing known"* into a file a lane then found a defect in · and
**left a document teaching the dangerous shape after hardening the tool**, thirteen days before it
caused the same leak again.

**Every one was caught by a lane going and looking.** Three lanes refused an over-broad self-blame
from me, and two corrected rulings of mine on evidence. **That is the machine working.**
