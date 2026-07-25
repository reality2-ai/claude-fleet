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

## g14 — two of your own rulings contradict: can a join frame carry no route? (real, canon)
Specs found a genuine collision between two things you blessed three weeks apart, and
it can't be fixed as a defect because either answer adds new normative ground.

- **§9.5 (you ratified 2026-06-23):** a frame with R = 0 — no carried origin — is
  non-conformant and MUST be dropped. "There is no valid route-less frame."
- **§12.5 (you GO'd 2026-07-13):** the shipping sovereign join sends header byte
  `0x20`. Decode it: version 00, type 100 (GROUP_MGMT), flags 000 — that *is* R = 0.

So canon specifies a route-less join frame and separately forbids all route-less
frames. Core's `group_mgmt.rs` implements the join as specified.

**Specs' recommendation for your batch:** §12.5 is right and §9.5 overreached. A joiner
has no hive_id to stamp — that's the thing it's joining to obtain; target and tgid are
deliberately zeroed for §16.6 privacy; and §9.5's dedup rationale doesn't bite here
because GROUP_MGMT isn't deduplicated by (msg_id, origin) at all — it's Ed25519-signed
with sequence and timestamp per §10.2. Proposed shape: scope ROUTE-ORIGIN-1 to
deliverable/deduped types, and name the bootstrap exemption explicitly in §9.5.

Ledgered as D-20260725-05 @ 67cda01e, **not landed** — waiting on you. Ruling either
way is one line; the cost of leaving it is that one of the two sections keeps teaching
something false, and the next implementer re-derives the bug android just fixed.

Related and *not* blocked on this: android's fix (route-less EVENT/REPLY now dropped)
is safe under either answer, so it merges regardless. One correction to what I told you
earlier about that fix: I described it as closing a path where a forged origin displayed
under a verified badge. That was wrong — android and its refuter both re-checked and the
HMAC gate above the decoder already refuses route-less frames, so nothing user-visible
was ever reachable. It is a structural/API defect (unverified entry points synthesised a
zero origin), worth fixing as defence-in-depth. Ledgered as D-20260725-07. The canon
collision below is entirely independent of that and stands as written.

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
