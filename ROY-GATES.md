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

## g15 — may a join request be relayed? (real, canon + security)
Specs found this by running an audit on its own fix, and it's the one place today where
the *obviously correct next step* is the dangerous one.

Two specs now disagree about the same frame. R2-WIRE says a join request must be accepted
even though it carries no origin (that's the ruling in g14). R2-ROUTE says, unconditionally,
that any frame with no origin must be dropped and never relayed. So one document says
accept, the other says drop.

The frame itself asks to travel: the shipping join sets a hop limit of **5**, not 1.

**Why this needs you rather than a lane.** Today, joins don't get relayed — but only
because R2-ROUTE drops them *for the wrong reason* (missing origin, not "joins shouldn't
travel"). The natural next fix is to make R2-ROUTE honour the new exemption. Do that, and
joins become relayable across five hops, and a proximity assumption nobody ever wrote down
disappears silently. R2-PROVISION justifies trust-on-presentation *by* physical proximity
and selects short-range transports to enforce it; relaying a join through untrusted
intermediaries weakens exactly that. The guarantee is currently an accident.

**Specs' recommendation:** say the no-relay rule out loud — a join is one hop, hop limit
should be 1, and a relay must not forward that frame type. That makes the two specs
consistent and puts the guarantee on an intended rule instead of a coincidence. If you'd
rather joins *were* relayable, then R2-ROUTE needs the carve-out and the proximity
argument needs restating honestly.

**It is three places, not one — including live code.** Since I wrote this, the lanes
found the same unconditional drop in the routing spec, in the wire spec, and in core's
actual dataplane, where the ingest path drops any frame without an origin and a comment
three lines below asserts the very rule that just stopped being true. All three are
frozen. At every one of them, the obvious conformance fix is the harmful one: honour the
new exemption at any single site and joins silently gain access to the mesh path.

A practical consequence worth knowing: a related dedup fix specs already landed is
**dead code until you rule** — the new key only applies to frames that currently never
get that far. Landing it first would look like progress and change nothing.

I've told the fleet: **nobody "fixes" any of the three until you rule.** It's the natural
inference and it's the harmful one.

## g14 — RULED under delegation, not waiting on you (canon) — overrule if you disagree
I first put this to you as a decision: two things you blessed three weeks apart contradict
each other. §9.5 (you ratified 2026-06-23) says a frame with no carried origin must always
be dropped. §12.5 (you GO'd 2026-07-13) specifies the sovereign join as header byte `0x20`,
which decodes to a GROUP_MGMT frame with no origin — the thing §9.5 forbids.

**Specs ruled it and landed it** (R2-WIRE §9.5.1, now at v0.67): the drop rule binds
EVENT, REPLY, HEARTBEAT and CAPABILITY, and GROUP_MGMT is the one exempt type. I accepted
its authority to do so and I think it was right, so this is now a note rather than a gate.

**The argument that decided it — corrected after you refuted the first version.** You asked
whether a new hive doesn't already have an identity, and that question killed the original
reasoning, which claimed a joiner had nothing to stamp *by construction*. It does: the
invitation carries the group public key (which doubles as the group's identifier — not
any secret material), and the derivation is a pure function, so the joiner can compute
the value perfectly well. What it cannot do is make that value mean anything —
nobody else can verify it without the joiner's private master secret, so the stamp would
carry no attributional weight at all. It would also put a stable per-device-per-group
pseudonym in the clear, allowing correlation across sessions and retroactive
de-anonymisation once membership is learned elsewhere. Note that this is *linkability*, not
disclosure: the value is a one-way derivation and does not reveal which group is being
joined — an earlier version of this note overstated that too. And the anti-duplicate
reasoning behind §9.5 doesn't reach joins at all: they're signed with a sequence and
timestamp, and travel point-to-point rather than flooding.

Your one-sentence question forced both of those corrections into the spec (v0.66) within
minutes. This paragraph was the last place the refuted version was still standing.

**If you read the delegation more narrowly than we did, say so and it reverts in one commit**
(ledger D-20260725-08 in claude-fleet, specs' own entry D-20260725-06).

One thing worth your attention regardless: this surfaced because specs told android to drop
route-less frames of *every* type, android complied over an automated reviewer that had
correctly said "hold, there's an unaddressed clause here", and only then did specs find
§12.5. Specs owned that publicly and issued the correction I've adopted fleet-wide — a lane
owning a ruling doesn't make its newest message beat better evidence; a peer citing a clause
your answer doesn't address is a falsifier, and the right move is to hold and ask.

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
