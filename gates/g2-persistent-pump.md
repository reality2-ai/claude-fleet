# Gate 2 — Persistent 0x25: keep a standing BLE link on the bench?

**Status:** ✅ CLOSED 2026-07-23 — #d018 (transport-test doctrine: dev bearer-ping + beacon-level awareness; heartbeat is NOT the transport test)
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → "read gates/g2 and argue both sides with me"

## Background

The coex PASS (0x25 = BLE + LoRa + ESP-NOW simultaneously) needed the host CoC pump to
light the BLE bit: bit0 stamps when a CoC frame is *received*, and with both boards
sitting as acceptors, nobody ever dialed anybody — the host had to. The pump is a
bench instrument, not R2 traffic. So today's honest claim is "0x25 held for 41.6 s
while a host pump drove BLE", and when the pump is off, the XIAO reads 0x24.

## The question

Do you want the bench to show a *standing* 0x25 — BLE continuously lit — or is the
proven-on-demand state enough?

- **Standing 0x25 via pump:** a systemd-style pump service on tuxedo-os. Cheap,
  but it institutionalizes an instrument as if it were traffic — the green would be
  partly synthetic, which is against the table's own honesty rule.
- **Standing 0x25 via board-to-board:** once the D4 initiator work (in flight right
  now) proves a board can dial its co-member and hold CoC, real R2 BLE traffic lights
  bit0 with no host involved. The green is then genuine.
- **Neither:** accept 0x24 steady + 0x25 on demand as the recorded result.

## Supervisor lean

**Wait for blerole.** If the bit0-BOTH retest passes, board-to-board BLE makes the
pump obsolete and this gate dissolves without a ruling — the right kind of resolution
(the system proves it, nobody decides it). Only if blerole stalls does the pump-service
question return, and then the lean is "neither" — don't fake a green.

## Roy's direction (2026-07-23)

"Could that be solved by bringing forward the 'heartbeat between TG members' code?"
— i.e. the standing BLE traffic should be the real TG heartbeat/shout-out, not a
bench pump. All bench hives share the dev TG, so the TG-contact primitive
(R2-HEARTBEAT v0.21 §6.1) applies to all of them.

## Core's sizing (read-only findings, 2026-07-23)

- Today the heartbeat emitter never touches the BLE CoC: it rides ESP-NOW (or UDP
  in sim builds). BLE carries control frames only. So heartbeat-over-BLE is new
  wiring, not a config flip.
- What exists already: frame format, heartbeat generation, CoC send path. What's
  missing: (a) a bridge from the heartbeat cadence into the CoC send, (b) link
  lifetime management — the CoC stands per-dial and drops on disconnect, so a
  standing liveness source needs the initiator to keep or re-establish it.
- The payoff is sound: bit0 stamps on CoC receive, so a periodic heartbeat admitted
  over the CoC refreshes bit0 every period — self-sustaining, pump retired for good.
- Size: MEDIUM.
- Honest-green caveat: the passed 41.6 s coex soak did NOT cover sustained periodic
  BLE transmit (BLE and ESP-NOW share the 2.4 GHz radio). A re-soak is required
  before claiming a standing 0x25 — risk judged medium, plausibly fine, unproven.
- Dependency: needs the board-to-board CoC to stand, which is behind the current
  rbid-resolve blocker (now suspected to be a stale flashed XIAO image, not a code
  defect — XIAO's flashed sha being checked).

## RULING (2026-07-23, evolved over three exchanges) — #d018

Roy, on the heartbeat lean: *"heartbeat is hive to hive but doesn't really answer
the 'how do we test a transport' question."* Then: *"at the transport level, it
does make sense at the moment for us to have something that pings between matching
transports for dev. and one can imagine there is something perhaps at the
transport layer anyway a sort of 'awareness test' that perhaps is more at the
beacon level."*

Resolved doctrine:

1. **Heartbeat is not the transport test.** It answers "is my co-member alive"
   (L5, TG-scoped); "does bearer X function" is below-L5, TG-agnostic. And routing
   (R2-ROUTE §5.2) legitimately steers heartbeat off BLE once ESP-NOW is up —
   pinning it to a bearer for test purposes would be a probe wearing heartbeat's
   clothes. Heartbeat proceeds on its own merits (v0.21 TG-contact), riding
   whatever bearer routing picks.
2. **DEV bearer-ping — adopted.** An active ping between matching transports,
   DEV-duty, for bench conformance. This is what legitimately lights the coex
   bits. Core's M sizing (cadence-into-CoC bridge + link lifetime) transfers to
   this wiring; the coex re-soak remains mandatory before any standing-0x25 green
   (sustained BLE TX is new load whatever the payload).
3. **Beacon-level awareness — to specs.** Production-shape conjecture: beacons
   already ride every bearer by canon, so sighting a co-member's beacon on bearer
   X is free passive per-bearer RX evidence — a liveness readout with zero added
   traffic. Specs to design placement and semantics; feeds the calm proof-surface.
4. **Pump: dead.** No synthetic green, ever. HB-over-CoC as the bit0 source is
   withdrawn.
