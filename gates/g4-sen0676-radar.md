# Gate 4 — SEN0676 radar attach: when does D5 get its real sensor?

**Status:** ✅ RULED 2026-07-23 — #d017 (see Ruling below)
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → "read gates/g4 and the water-level field-node design with me"

## Background

The field-node design (Mariko water-level monitoring) pairs a DFR1195 with the DFR
SEN0676 mmWave radar as the water-level sensor. The radar is on the bench, unattached.
D5 is being brought current right now as the second *simulated* sensor (cosine wave,
own persona) — the radar would replace or sit beside that simulated source and make D5
the first hive reporting a *physical* measurement through the mesh.

Note the radar is the one 5 V exception in the otherwise-3V3 system — attach includes
a small wiring decision, which the circuits lane owns.

## The decision

When to attach: it's a bench-slot + focus question, not a capability question.

- **Soon (after D5 is current + blerole closed):** same board, natural next increment;
  turns the "Sensor (radar)" table cells from ◑ to a real metal claim; first physical
  data through the substrate — a strong calm-tech demo (real signal on the phone).
- **Later (after the substrate lock you called):** keeps the bench on one-variable
  below-TG conjectures; the radar is an *above*-trust payload (ensemble), so it
  doesn't advance the current lock — it widens surface while the lock is still open.

## Supervisor lean

**After D5 current + blerole closed, but before the wider scale-out** — it rides the
same board that's already being reflashed, and one real sensor stream alongside the
simulated cosine gives the substrate a truth-bearing payload to carry without opening
a new front. The counter-argument (stay pure on below-TG until locked) is respectable;
this is genuinely your sequencing call.

## Ruling syntax

"gate 4: after blerole" / "gate 4: after substrate lock" / "gate 4: now"


---

## RULING (Roy, 2026-07-23 — #d017)

**Radar set aside; D5 is a bench test tool from now on.** Roy: *"put aside the radar
for now, [D]5 is a bench test tool from now on. We will deal with the radar later,
and probably use a Xiao with that anyway."* Consequences: SEN0676 attach deferred
indefinitely; D5's standing role = bench test tool (cosine sim sensor); the eventual
radar field node leans XIAO-based, not DFR1195 (field-node design updated).
