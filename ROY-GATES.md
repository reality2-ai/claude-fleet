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

### The strongest argument, in one sentence
**A relay cannot authorise a join even in principle.** The frame has no verifiable origin,
no outer authentication, and its signing key is carried *inside itself* — so anyone can
mint a validly-signed join. A relay has nothing it can check that separates a real joiner
from an attacker, and by definition the sender isn't a member yet. Forwarding means every
node relays attacker-mintable, unattributable frames with a hop budget. (Specs, whose own
argument is the one below, told me to give you this one instead — it's an impossibility of
*capability*, where its own is about *consequence*.)

The second argument, independently reached, needs no proximity claim either: **origin-less
plus relayable equals unmeterable.** The only rate-limiting primitive canon has is a
per-origin quota — it keys on origin, and a join has none. So an unauthenticated frame
could traverse five hops with no relay able to throttle it, because the one metering tool
available needs exactly the field the exemption removes.

### The best case FOR relaying, and why it collapsed
The frame sets a hop limit of **5**, not 1 — which looks like the designers provisioning
joins to travel. That was the one datum troubling both specs and core, and neither would
dismiss it. **Android undercut it from its own code:** the value is documented there as
*nominal*, pinned only to match a shipped test vector, because the transport it was written
for is single-hop anyway. Meanwhile the field that genuinely controls propagation is set to
its minimum — the frame's own routing parameters say *don't spray*, on their own authority.

Specs then checked android's evidence rather than taking it, and found the chain stopped
one step short: that comment explains why *android* chose 5 — mirroring core's value — not
why core chose it. So I asked core, and **the answer closes it at the source and goes
further than the caveat feared.**

Core's deliberate join intent is **one hop, and it says so in a comment**: its real
sovereign-join producers set the hop limit to 1, one of them annotated *"direct
point-to-point over L2CAP — no relay"*. The value 5 appears in only two places: a
cross-vendor test vector pinned for parser compatibility with no hop-budget rationale
anywhere, and an older board file where *every* frame type is 5. Across the tree, 5 occurs
24 times on all frame types while every other value appears once. It's the generic default.

So the one datum that looked like the designers provisioning joins to travel turns out to be
inherited boilerplate, and the considered value — written by the lane that produces the
frame — is single-hop with an explicit no-relay note. **There is now no surviving argument
for relaying.**

Core also flagged, without acting on it, one real inconsistency: an older board file emits a
group-management frame at the generic default of 5 rather than the single-hop value the
proximity path uses. Almost certainly the same boilerplate, but it is a second producer that
*would* send such a frame five hops. Your ruling resolves it either way.

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
| 16 | Branch-as-containment decision (private lane) | OPEN — a handoff described a branch as holding content back from origin; ancestry showed it never did, so the stated protection was never real. NOT an incident, nothing to undo, target repo is private. A second branch is held apart only by not-yet-merged state, which ONE merge would silently end — so disposition is your call: delete, rewrite, or accept. General rule banked: A BRANCH IS NEVER A CONTAINMENT BOUNDARY; only not-committing, repo visibility and history rewriting are. Coordinates, branch names and evidence are in the private fleet log and deliberately NOT here — this repo is PUBLIC. | — | — |
| 17 | Provider-blind prompt detector (HIGH, delivery integrity) | OPEN — `lib/comms.sh:198` `fleet_input_busy()` greps a FIXED STRING for one provider's prompt glyph only. A pane using the other glyph never matches, so the landed-check stays false, `:316-321` takes the `never-landed` branch and REQUEUES a message that actually submitted. That is the root cause of the duplicate advisories, the `delivered=false` records, and the attempt-counting health metric — one defect, three symptoms. Also: the comment at `:194-195` claims a missed read errs toward delivering and never toward never-delivering; on this path it does the opposite, so the stated fail-safe DIRECTION is not the direction the code has. NOT PATCHED BY ME, deliberately: this is the live transport for every lane, and a bad edit costs the ability to talk to any lane including to report the breakage — asymmetric against acting while you are away, and the cost of waiting is duplicate messages, not lost work. Fix needs provider-aware glyph matching plus controls proving, for BOTH glyphs: busy-detect, success ack, no duplicate, and following-message flow. Supersedes the delivery-metric item as its root. | — | — |
