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
**5 open.** Ordered by what is blocked, not by number. Each links to a brief with the
argument, the options and the ruling syntax.

### Blocking a lane right now

**[g23 — this repo is public and our own ledger is in it](gates/g23-public-fleet-repo-leak.md)** · **hygiene, not a breach**
`reality2-ai/claude-fleet` is public (verified from the API) and the branch we commit to is pushed
to it. **No keys, no MACs, no personas** — that guard held. What is exposed is structure: four
private repo names, one private branch name, and **93 commit-id-shaped tokens** in the ledger.
**I was adding to it** — yesterday's gate brief named a private repo; scrubbed forward now.
History needs your ruling: rewriting it means force-push, which I am forbidden.
→ `gate 23: make it private` / `scrub forward only` / `rewrite history` / `stop publishing the ledger`

**[g22 — shared crates are vendored per-repo](gates/g22-shared-crate-vendoring.md)** · **a ruling is already lost to it**
Your g15 dataplane fix landed in core's crate; the firmware builds from **its own vendored copy** and
the new signal appears 10 times in core's and **0 times in the firmware's**. So the change is real,
tested, ledgered — and does not reach metal. **Twice re-sized since I first wrote it:** three copies →
nine, then **six whole-crate variants** once the comparison stopped hashing one file — and **three classes**. Not chaos: 3 in sync,
3 deliberate (incl. an **explicit security pin** on the bench), 3 stale and none of them on the bench.
**The bench is safe** — an unfixed copy cannot carry a join at all, which is the intended zero-hop
state. Real gap is narrow: no working drift detector, no standing re-vendor obligation — and it
must key on **(repo, crate, sha)**, because *a content match on a crate that never moved is not
evidence of sync*. **My lean flipped** — path-dep would dissolve that deliberate pin.
Blocks the g15 identity half.
→ `gate 22: fix the mechanism` / `path-dep canonical` / `accept the forks`


**[g21 — the dedup key](gates/g21-join-dedup-key.md)** · **much smaller than I first wrote**
You said check canon first, and canon had already ruled it: `GROUP_MGMT` dedups on `msg_id` alone,
NORMATIVE since v0.68, with fabricating an origin explicitly forbidden. There is no key to choose and
the type-aware rider is already canon. **My earlier brief would have had you overrule landed canon.**
One narrow question survives: §8.2 says the narrow key is sound *because these frames are not flooded*
— and your g15 ruling moved that premise from zero hops to at-most-one-carried.
→ `gate 21: rationale holds, close it` / `re-examine the soundness premise`

**[g13 — radar board-fit](gates/g13-radar-board-fit.md)** · tiny, physical
~29 breadboard columns needed against ~28 available. Marginal enough that only eyeballing the
real parts settles it. Circuits is idle until you look.
→ `gate 13: fits` / `rework`

### Small, not urgent

**[g8 — AP client isolation blocks the phone↔tuxedo UDP path](gates/g8-ap-client-isolation.md)**
Cause established, not suspected. Any one of three fixes clears it; composer re-runs in two
minutes. The capability cell stays honest either way.
→ `gate 8: ethernet` / `disable isolation` / `other ssid` / `leave it`

## Not waiting on you
- **D4/X1 flash of the g18 rebuild** — built, attested, eligible. Held by supervisor until the
  D5 debugger session closes; one grant at a time. No ruling needed from you.
- **g19 legs 2 and 3** (audit-log location, one-shot grant consumption) and **g17 state/metric
  separation** — ruled by you, work in progress, not gates.
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
| 12 | openocd USB perms (Alfred) | JTAG read executed clean 07-25; the "lock held" reading from that dump was later REFUTED and is retracted | #d026 | — |
| 14 | R=0 join frame — §9.5 vs §12.5 canon collision | CONVERTED to a note: specs RULED and landed it (R2-WIRE v0.65 §9.5.1 ROUTE-ORIGIN-1 binds EVENT/REPLY/HEARTBEAT, GROUP_MGMT exempt); supervisor accepted — I had been too conservative, it decides which of two blessed clauses governs, not new ground | D-20260725-08 | — |
| 18 | D4/X1 have no fault-capture instrument | **rebuild now** (Roy 2026-07-26) — EXECUTED: both variants built and attested, two-leg eligibility PASS on both, positive+negative controls run. **No flash taken**; flash held by supervisor until the D5 debugger session closes (one grant at a time). Note the rebuild does **not** carry the g15 join fix — different branch, and g18 was forensics, not join | — | [g18](gates/g18-sibling-artifact-rebuild.md) |
| 15 | Join relay — may a sovereign JOIN traverse the mesh? | **RELAY PERMITTED; NO HOP BUDGET** (Roy 2026-07-26): intended case is **ZERO hops — direct connection**, physical presence; relay allowed when needed under the same single-hop rule (worked example: a UDP hive) = **at most one** intermediary. Lanes' NO was against mesh FLOODING and survives intact. Origin-less drop needs a join exception; hop semantics 0 direct / ≤1 relayed; 5 is boilerplate. **Dedup key NOT settled — g21** | — | [g15](gates/g15-join-relay.md) |
