# Gate 7 — TG contact: one-hop pulse only, or multi-hop via relay?

**Status:** OPEN · opened 2026-07-23 (Roy) · specs reconciliation design in flight
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → "read gates/g7 and R2-HEARTBEAT v0.21 §6.1 with me"

## Why this gate exists

Two pieces of your own direction are in tension. R2-HEARTBEAT v0.21 §6.1 defines
the TG-contact primitive as the existing pulse — **one-hop, never relayed**. Your
bearer-migration ladder (2026-07-23) has heartbeat automatically degrading
BLE → ESP-NOW → LoRa → **UDP-via-relay** as two hives separate — and the last rung
crosses a relay, which the pulse as canonized cannot do. Something has to give,
deliberately.

## What one-hop bought (why §6.1 says never-relayed)

- **Bounded traffic**: a pulse that relays is a pulse that multiplies — every TG
  member's liveness beacon crossing the mesh at heartbeat cadence is real load.
- **Privacy**: a one-hop pulse keeps "who is in this TG and alive" within radio
  range; a relayed pulse advertises membership liveness across islands.
- **Clean meaning**: pulse = "my neighbour is alive", direct evidence, no route
  trust involved.

## Options

- **A — Keep the pulse one-hop; far contact rides the routed layer.** Two
  primitives: the pulse stays neighbour-scoped liveness; when no direct bearer
  reaches a co-member, TG contact becomes an ordinary routed message (GroupHmac,
  normal transport selection, relay like any traffic) at a suitable cadence. The
  ladder's last rung is then "routed contact", not "relayed pulse".
- **B — Loosen never-relayed for the far rung.** One mechanism: the pulse itself
  relays when no direct bearer reaches the peer. Simpler on paper; but it spends
  the traffic and privacy properties §6.1 was written to keep, and needs
  suppression rules to avoid membership-liveness flooding.
- **C — One-hop pulse + passive far-awareness.** Pulse never relays; "far
  co-member still reachable" is derived from routing-table state (a route exists,
  recently used) with only occasional routed contact to confirm. Cheapest — no
  standing far traffic at all — but weakest liveness guarantee.

## Supervisor lean

**A**, with C's passive derivation as an optimization inside it. Layering stays
clean (pulse = direct evidence; routed contact = reachability), privacy holds
(membership liveness doesn't cross islands unbidden), and the ladder still reads
as you described — the *contact* migrates automatically, its mechanism switching
from pulse to routed message at the relay rung. **Would refute the lean:** if
specs' reconciliation shows routed far-contact re-implements most of the pulse
machinery anyway, B's single loosened mechanism may be honestly simpler.

Specs is designing this reconciliation now (dispatched with your verbatim);
their proposal will sharpen the choice — ruling can wait for it.

## Ruling syntax

"gate 7: one-hop + routed far-contact" (lean) / "gate 7: relay the pulse" /
"gate 7: passive far-awareness" / "gate 7: wait for specs proposal"
