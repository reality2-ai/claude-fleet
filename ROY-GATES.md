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
**7 open.** Ordered by what is blocked, not by number. Each links to a brief with the
argument, the options and the ruling syntax.

### Blocking a lane right now

**[g13 — radar board-fit](gates/g13-radar-board-fit.md)** · tiny, physical
~29 breadboard columns needed against ~28 available. Marginal enough that only eyeballing the
real parts settles it. Circuits is idle until you look.
→ `gate 13: fits` / `rework`

### Security and tooling, open right now

**[g19 — may I patch the flash-authorisation gate?](gates/g19-auth-gate-bypass.md)** · a bypass that has fired
A bare `VAR=value` prefix hides a flasher from the gate — no check, no audit entry. **My defect:**
my own grant wording told lanes to use that form. It fired once, on an *offline derive*, not a
device operation. The number of bypasses is **unknown, not zero**, because nothing detects an
unlogged operation. Also: grants are never consumed, so every "one attempt only" I wrote was
prose the gate does not enforce.
→ `gate 19: you patch it` / `leg 1 only` / `I'll do it` / `defer`

**[g17 — may I patch the fleet message transport?](gates/g17-fleet-transport.md)** · one glyph, three failures
A fixed-string prompt match breaks acknowledgement (hence the duplicate messages — the transport
retrying, not lanes repeating), overloads the state and metrics, and **disables the anti-garble
guard**. Content does arrive; integrity is untested. I held off patching because you were away
and a bad edit costs the ability to report that I broke it.
→ `gate 17: you patch it` / `I'll patch it` / `defer`

### The main work

**[g20 — open a new flash grant for the origin hunt?](gates/g20-origin-hunt-grant.md)** · the next step on D5
The capture campaign closed: 240+ faults, **every one** self-recovered, family ruled at scale.
Origin is open with a lever — 13 of 18 wild jumps start in a timer-arm call site, 2 in our own
SPI/LoRa driver. One falsifier needs no hardware and should run first.
→ `gate 20: open the grant` / `falsifier first` / `hold`

**[g18 — D4 and X1 cannot report a fault at all](gates/g18-sibling-artifact-rebuild.md)** · forensics gap
~40 staged artifacts have **no capture instrument** and a handler that re-faults. The fix exists
only in the D5 line. Not a brick; but a fault on those boards is silent and unattributable.
→ `gate 18: rebuild now` / `rebuild before the next multi-board run` / `defer`

### Small, not urgent

**[g16 — a branch described as containment never was](gates/g16-branch-containment.md)**
No incident, no exposure, repo private, nothing to undo. A second branch holds sensitive parents
apart only by not having been merged — a state, not a guarantee, and one merge publishes it
silently.
→ `gate 16: delete` / `rewrite` / `accept`

**[g8 — AP client isolation blocks the phone↔tuxedo UDP path](gates/g8-ap-client-isolation.md)**
Cause established, not suspected. Any one of three fixes clears it; composer re-runs in two
minutes. The capability cell stays honest either way.
→ `gate 8: ethernet` / `disable isolation` / `other ssid` / `leave it`

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
| 12 | openocd USB perms (Alfred) | JTAG read executed clean 07-25; the "lock held" reading from that dump was later REFUTED and is retracted | #d026 | — |
| 14 | R=0 join frame — §9.5 vs §12.5 canon collision | CONVERTED to a note: specs RULED and landed it (R2-WIRE v0.65 §9.5.1 ROUTE-ORIGIN-1 binds EVENT/REPLY/HEARTBEAT, GROUP_MGMT exempt); supervisor accepted — I had been too conservative, it decides which of two blessed clauses governs, not new ground | D-20260725-08 | — |
| 15 | Join relay — may a sovereign JOIN traverse the mesh? | **RELAY PERMITTED; NO HOP BUDGET** (Roy 2026-07-26): intended case is **ZERO hops — direct connection**, physical presence; relay allowed when needed under the same single-hop rule (worked example: a UDP hive) = **at most one** intermediary. Lanes' NO was against mesh FLOODING and survives intact. Origin-less drop needs a join exception; hop semantics 0 direct / ≤1 relayed; 5 is boilerplate. **Dedup key NOT settled — g21** | — | [g15](gates/g15-join-relay.md) |
