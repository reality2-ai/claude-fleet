# Gate 2 — Persistent 0x25: keep a standing BLE link on the bench?

**Status:** OPEN · Roy direction received (heartbeat-over-BLE); core sizing landed 2026-07-23 — see below
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

## Supervisor lean (updated)

Proceed with heartbeat-over-BLE once the rbid blocker clears, per your direction —
with the re-soak as a mandatory pass gate before any standing-0x25 green. No pump
service. Unless you object, this proceeds without a further ruling.

## Ruling syntax

"gate 2: proceed" (lean — also the default if you say nothing) /
"gate 2: pump service instead" / "gate 2: neither, 0x24 steady is enough"
