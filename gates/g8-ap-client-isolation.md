# Gate 8 — WiFi AP client isolation blocks the phone↔<build-host> UDP path

**Status:** 🔵 OPEN — small, physical/network, not urgent
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g8 and tell me whether the transport-only annotation is honest"*

## Background

The phone UDP metal test is complete except its last hop. The phone sends the probe
correctly and <build-host>'s echo server works — but the datagram never arrives. Cause is
established, not suspected: **your WiFi AP has client isolation on**, so wireless client
↔ wireless client traffic is blocked. ICMP shows 100% loss both ways, which is the
signature rather than an inference.

Nothing is broken in our code. This is a property of the network the bench sits on.

## The decision

Which fix, or none. Any **one** of these clears it:

- **Disable AP client isolation** — one router setting; affects your whole home network,
  so it is your call and not a bench detail.
- **Put <build-host> on ethernet** — no wireless-to-wireless hop, no router change. Probably
  the least invasive if there is a cable path.
- **Use a non-isolating SSID** — if the AP offers a guest/main split where one permits
  client-to-client.

Then composer re-runs the probe: **about two minutes**.

## What it costs to leave it

Not much, which is why this is not urgent. The capability cell stays annotated
**transport-only** either way — the claim we publish is already honest about what was
and wasn't demonstrated. Ruling it simply upgrades an annotated cell to a measured one.

The reason to do it eventually: it is the only step between "the phone path works in
principle" and "the phone path was observed working end to end on this bench".

## Supervisor lean

**Ethernet if a cable reaches, otherwise leave it.** Turning off client isolation
network-wide to close one bench annotation is a poor trade — it is a standing security
posture on your home network being spent on a two-minute test. If <build-host> can take a
cable, that costs nothing and settles it permanently.

## Ruling syntax

"gate 8: ethernet" / "gate 8: disable isolation" / "gate 8: other ssid" / "gate 8: leave it"
