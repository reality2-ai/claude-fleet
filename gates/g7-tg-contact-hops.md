# Gate 7 — TG contact: one-hop pulse only, or multi-hop via relay?

**Status:** ✅ CLOSED 2026-07-23 — #d019 (relax to two-hop; specs ordered to modify canon)

## RULING (Roy, 2026-07-23)

*"I think the one-hop rule might have to be relaxed to two-hop to allow for
transports that act as a go-between, such as internet relay."* Then, after specs'
reconciliation had landed one-hop-stands (D-20260723-11): *"For gate 7, you will
need to tell specs to modify canon."*

Executed as: TG-contact pulse TTL=2 — one go-between allowed. Specs' IP-transit
reading survives as the hop-1 case (id-6 bearer transit is not an R2 hop); the
canon change additionally admits one R2 go-between (e.g. a repeater relaying the
pulse). Constraints carried into the design order: TTL accounting at the
go-between (no chain masquerade), complex-hive bridges count zero (#d009),
relayed-pulse rate/suppression to bound the O(N) and privacy cost — one island
boundary is the point of 2-not-N.
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

## Roy's input (2026-07-23)

*"I think the one-hop rule might have to be relaxed to two-hop to allow for
transports that act as a go-between, such as internet relay."*

That's a fourth shape — **D: TTL=2 pulse**. The pulse may cross exactly one
go-between (an internet relay, a bearer-bridge repeater), never more. It covers
the ladder's last rung with one mechanism, keeps traffic bounded (no mesh
flooding — a single relay leg, not propagation), and limits the privacy cost to
one island boundary rather than arbitrary reach. Two notes for the design:
- **Complex-hive bridges don't count as hops** (#d009 — the internal link is
  invisible), so phone-relaying-for-its-own-XIAO stays "direct"; two-hop budget
  spends only on inter-hive go-betweens.
- The go-between itself is transport-shaped (the relay leg acts like a bearer),
  which is why this reads as a transport concern rather than mesh routing.

## Supervisor lean (updated)

**D** — Roy's two-hop relaxation, folded into specs' reconciliation design: pulse
TTL=2 with the go-between defined as a transport-level object, complex-hive
bridges excluded from the count. The prior lean **A** stands as fallback if specs
finds TTL=2 leaks (e.g. relay chains masquerading as one go-between). Layering stays
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
