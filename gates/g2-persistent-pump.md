# Gate 2 — Persistent 0x25: keep a standing BLE link on the bench?

**Status:** OPEN · likely DISSOLVES when blerole lands
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

## Ruling syntax

"gate 2: wait" (default) / "gate 2: pump service" / "gate 2: neither, close it"
