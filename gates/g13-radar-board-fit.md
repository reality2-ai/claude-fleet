# Gate 13 — radar board-fit check at the bench

**Status:** 🔵 OPEN — tiny, physical; blocks nothing but the layout
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g13 and docs/radar-xiao-node.md"*

## Background

Circuits published the radar XIAO-node spec (`docs/radar-xiao-node.md`, rev C76) and
flagged one physical check that only you can perform.

## The decision

**Does it physically fit?** The FRAM 8-pin footprint needs roughly **29 breadboard
columns**; the HP9570 offers about **28** (73 mm). That is a marginal miss — near enough
that measuring on paper is not trustworthy and eyeballing the actual parts is.

- **Fits** → the layout stands as published, and the radar code leg proceeds when its
  turn comes.
- **Doesn't fit** → circuits reworks the layout. That is a contained change; it does not
  touch the interface or the spec's electrical decisions.

## What is not blocked

Everything else on the radar leg is done: Modbus RTU over TTL-UART, 5 V gated through
the boost converter's enable line, 3 V3 logic via level shifter, the register and framing
choices, and the XIAO as target per your earlier ruling. Two bench confirmations remain
owed (frame format and sensor-side logic voltage) but those need hardware and no device
operations are currently authorised.

Circuits is idle until this verdict or a core question on the interface.

## Supervisor lean

**None — this is a measurement, not a judgement.** Put the parts next to each other next
time you are at the bench. If it is genuinely borderline rather than clearly one or the
other, say so and circuits will rework anyway; a marginal fit that depends on how hard
you press is a fit that will fail later.

## Ruling syntax

"gate 13: fits" / "gate 13: rework"
