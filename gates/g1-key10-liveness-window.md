# Gate 1 — Key-10 liveness window: per-transport or tier-keyed?

**Status:** ✅ CLOSED 2026-07-23 — #d015 (see Ruling below)
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → "read gates/g1 and argue both sides with me"

## The problem in one paragraph

The health byte (key-10) marks a bearer "live" only if a frame was admitted within the
last ~8 seconds (the ADMIT_W window, uniform across transports). But the *default*
health-frame cadence in canon is ~10 seconds, and the default keepalive is 30 seconds.
So a node that is perfectly conformant but quiet — sending only its scheduled
heartbeats — will show its bearers dark most of the time. Not a bug anywhere: every
component follows its own spec. The specs just never promise that the window is wider
than the cadence. The coex campaign hit this exact mismatch on the bench (30 s emit vs
8 s window) and we fixed it *for the bench* by speeding the bench keepalive up.
The design question is what the *fleet-wide* rule should be.

## Why it matters

Key-10 is the proof-signal the whole table leans on — "is this bearer alive" is how we
turn radio behaviour into a green cell. If the window rule is wrong, healthy nodes look
dead (false alarm, violates calm-technology: attention drawn to nothing) or we widen
windows so far that dead bearers look alive for minutes (false green — worse).

## Options

**(a) Per-transport windows.** Each bearer gets a window suited to its cadence: LoRa
(slow, duty-cycled) gets minutes; ESP-NOW (chatty) keeps seconds. Matches physics.
Cost: N window constants to justify and maintain; the health byte's meaning becomes
per-bearer ("live" = different freshness per bit), which complicates reading it.

**(b) Tier-keyed windows.** The window follows the node's *duty tier* (the SCF
duty-class already ruled: power source × role), imported the way R2-ROUTE §2.4 already
scales fade by class — a battery sensor gets a long window everywhere, a powered relay
a short one. One rule, already-canonical machinery, consistent byte semantics per node.
Cost: a chatty bearer on a sleepy node looks no fresher than its slowest duty.

**(c) Do nothing.** Keep 8 s uniform; accept quiet-node-is-dark as the semantic
("live" means *actively heard right now*, not *believed present*). Cheapest; honest;
but then key-10 under-reports on every low-duty deployment and field dashboards
inherit the flicker the bench just spent a campaign diagnosing.

## Supervisor lean

**(b) tier-keyed**, handed to specs as a spec-first task. Grounds: the class machinery
exists (R2-ROUTE §2.4 fade ≫ keepalive), it keeps one legible rule, and the coex
campaign's lesson was precisely that cadence and window must be co-designed, not set
in different documents. **What would refute the lean:** if bench evidence shows
bearers on one node genuinely need different freshness (e.g. LoRa-only neighbours
fading while ESP-NOW is hot), per-transport (a) wins.

## Ruling syntax

"gate 1: tier-keyed" / "gate 1: per-transport" / "gate 1: leave it" — with any
sharpening you want; specs gets it as a spec-first task either way.


---

## RULING (Roy, 2026-07-23 — #d015, specs D-20260723-07/-08)

**Both axes compose.** Roy: *"both options A and B make sense. eg LoRa must have a
longer time-to-fade just due to the nature of the connection and the way lora is
mostly quiet when not in use. Similarly, devices that have a regular time cadence,
eg a sensor that turns on, reads a value and turns off must be able to have that
cadence automatically become part of the timing."*

Follow-ons folded into the same ruling: the sensor lifecycle model (first-boot shout
= enrolment; TG-member existence never fully fades; each neighbour learns "what seems
normal for this hive" locally, **observed, no exchange**; attention = deviation from
that hive's own normal), the mobility axis (wearable-in-crowd = fast fade;
non-members fade fully — privacy consequence), and the TG contact primitive (the
regular "shout out to all").

**Landed:** R2-HEARTBEAT v0.19 §6.4.1 `W_T = clamp(k_w × C_T, floor_T, ceil_T)`
(specs 861d7b0), with the observed-only supersede + mobility folds in the v0.20
follow-up. The #d008 tension case became a conformance MUST with a negative control.
