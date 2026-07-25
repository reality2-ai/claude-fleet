# Decisions waiting on Roy

One current list. Supervisor adds a gate when it opens, removes it when you rule;
history lives in DECISIONS.md. Empty file = nothing waiting on you.

**To interrogate a gate with AI help:** `cd ~/Development/R2/claude-fleet && claude`
then: *"read gates/g3 and argue both sides with me"* — a fresh Claude with the brief,
the ledger, and the repo. Or open the brief's GitHub link from any browser and paste
it into claude.ai.

**To rule:** tmux window 0 (supervisor), type e.g. `gate 3: regenerate`. Ruling
syntax is at the bottom of every brief.

---

## g15 — may a join request be relayed? (real, canon + security) — THREE LANES AGREE: NO
I asked core, android and specs the same question separately, told none of them to
coordinate, and told core and android not to read specs' reasoning first. **All three said
no — from three different grounds.** Two of them also found the same second problem
independently. Detail below, but the headline is that this converged rather than deferred.

**Two specs currently contradict each other about the same frame.** The wire spec says a
join must be accepted even though it carries no origin; the routing spec says any frame
with no origin must be dropped and never forwarded. The same unconditional drop also sits
in core's live dataplane. All three are frozen.

### The strongest argument, and it needs no proximity claim
**Origin-less plus relayable equals unmeterable.** The only rate-limiting primitive canon
has is a per-origin broadcast quota — it keys on origin. A join frame has no origin. So a
non-member could emit an unauthenticated frame that traverses five hops and *cannot be
quota-limited by any relay*, because the one metering tool available needs exactly the
field the exemption removes. This is canon-derived and survived every counter-argument the
lanes could mount.

Android reached the same place from the other side: **a relay cannot authorise a join even
in principle.** No verifiable origin, no outer authentication, and the signing key is
carried *inside* the frame — so anyone can mint a validly-signed join. A relay has nothing
it can check that separates a real joiner from an attacker, and by definition the sender
isn't a member yet. Forwarding means every node relays attacker-mintable, unattributable
frames with a hop budget.

### The best case FOR relaying, and why it collapsed
The frame sets a hop limit of **5**, not 1 — which looks like the designers provisioning
joins to travel. That was the one datum troubling both specs and core, and neither would
dismiss it. **Android dissolved it from its own code:** the value is documented there as
*nominal*, pinned only to match a shipped test vector, because the transport it was written
for is single-hop anyway. Meanwhile the field that genuinely controls propagation is set to
its minimum — the frame's own routing parameters say *don't spray*.

### What you should know before ruling
**Specs weakened its own case, unprompted.** It had told me proximity justifies
trust-on-presentation. On re-reading, that clause covers only auto-pairing — the mode with
no cryptographic ceremony — and elsewhere canon *explicitly* admits joins with no physical
adjacency at all. Its position didn't change; its grounds and confidence did. Its words:
do not present this as specs being confident on proximity.

**So this is a new call, not you ratifying your own prior rulings.** Specs volunteered that
distinction, which is exactly what I'd asked it to separate. What's canon-derived: the
textual conflict, the hop limit value, the cryptographic trust chain, and that canon admits
non-proximate joins. What's judgement: whether relaying is a meaningful threat increase,
and whether a guarantee we currently get by accident is worth preserving deliberately.

**Two lanes independently flagged a coupling — please rule both together.** The dedup key
for these frames is currently a single global identifier, which is safe *only* because
joins aren't flooded. Rule them relayable without fixing that, and it becomes trivially
collidable the moment the first join travels. Whichever way you go, the key and the relay
question have to move in the same ruling.

**The honest alternative nobody is pushing:** two lanes noted a modest spec change — a
defined return path for a relayed join, plus a properly namespaced dedup key — could make
"yes" safe. So this may be less *is it allowed* than *what would have to change first*.

Recommendation from all three: **no relay — a join is one hop.** Say it explicitly rather
than leaving it to a drop that happens for an unrelated reason.

## g8 — WiFi AP client isolation blocks the phone↔tuxedo UDP path (small, physical/network)
The phone UDP metal test is DONE except the last hop: phone sends the probe correctly,
tuxedo's echo server works, but the datagram never arrives — your WiFi AP has
client isolation on (wireless client ↔ wireless client blocked; ICMP 100% loss both
ways). Fix is any ONE of: disable AP client isolation · put tuxedo on ethernet ·
use a non-isolating SSID. Then composer re-runs (2 min). Not urgent — cell stays
annotated transport-only either way.

GitHub: https://github.com/reality2-ai/claude-fleet/tree/gate-heredoc-2026-07-20/gates

## g13 — radar board-fit check at the bench (tiny, physical)
Circuits published the radar XIAO-node spec (docs/radar-xiao-node.md) and flags one
physical check only you can do: the FRAM 8-pin footprint needs ~29 breadboard columns
vs the HP9570's ~28 — marginal fit. Eyeball it next time you're at the bench; if it
doesn't fit, circuits reworks the layout. Nothing else blocks the radar code leg.


## Not waiting on you
- Blerole D4 reflash (iter 2, L3 fix) + D5 sensor flash — pre-granted, in flight.
- Multi-hive / multi-TG scale-out — gated on the below-TG substrate lock (the table
  is the gate-keeper, not a ruling).
- Waveform-as-sentant implementation — core owns it under your layer ruling.

## Closed — record of decisions past

| # | Gate | Ruling | Ref | Brief |
|---|------|--------|-----|-------|
| 1 | Key-10 liveness window | both axes compose: transport floor × observed cadence; lifecycle + mobility folds | #d015 | [g1](gates/g1-key10-liveness-window.md) |
| 2 | Persistent 0x25 | dev bearer-ping + beacon-level awareness; heartbeat ≠ transport test; pump dead | #d018 | [g2](gates/g2-persistent-pump.md) |
| 3 | composer manifest.json | regenerate — EXECUTED ab62a0e (was chip-split staleness, not corruption) | #d016 | [g3](gates/g3-composer-manifest.md) |
| 4 | SEN0676 radar | set aside; D5 = bench test tool; radar later on a XIAO | #d017 | [g4](gates/g4-sen0676-radar.md) |
| 7 | TG contact hops | relax to two-hop (one go-between; TTL=2); canon landed HEARTBEAT v0.24 §7 | #d019 | [g7](gates/g7-tg-contact-hops.md) |
| 6 | Baked member roster | adopt as dev seed of runtime member-set; canon D-13/-14; merge + wiring dispatched | #d020 | [g6](gates/g6-baked-roster.md) |
| 5 | Alfred rig fork | defer until phone-pair merge proven on metal; stays two hives + relay; reopens automatically | #d021 | [g5](gates/g5-alfred-rig-fork.md) |
| 9 | D5 USB replug | replugged 07-24 06:2x; "sleeping tuxedo" = wrong-host artifact (dead node `tuxedo` vs live `tuxedo-os`); suspend/powersave asks withdrawn | #d026 | — |
| 10 | v8 OTA radio quiesce | blessed as shaped 07-24 (relay-island dark + collectors-astray accepted); v8 build GO | #d026 | — |
| 11 | D5 replug / bench USB | closed 07-24 22:5x — tuxedo uplink cable bad (data lines); boards moved to Alfred, all 3 stable; v8.3 cycle firing | #d026 | — |
| 12 | openocd USB perms (Alfred) | Roy ran corrected sudo 07-25 13:07 (original plugdev/uaccess rules can't work on Manjaro-over-ssh); JTAG read of D5's wedged-RX state executed clean same hour — read cpu1 parked in the fault handler's own spin with RX queues empty; the 'lock held' reading from that dump was later REFUTED (the symbol is a handle pointer) and is retracted | #d026 | — |
