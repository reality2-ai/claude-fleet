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
**6 open.** Ordered by what is blocked, not by number. Each links to a brief with the
argument, the options and the ruling syntax.

### Blocking a lane right now

**[g27 — provision X1: authorise a raw persona write at `0x12000`?](gates/g27-x1-persona-raw-write.md)** · **the one thing between here and a completed OTA round-trip**
**Both questions you gated this on are now answered from code and from the device.** (1) This build reads
the persona from **raw absolute `0x12000`** via `esp_storage::FlashStorage` — **table-agnostic, not
NVS**. (2) That offset is in a region **no partition claims**: the device's own bootloader lists
`nvs 0x9000` · `otadata 0xf000` · `phy_init 0x11000+0x1000` · `ota_0 0x20000`, leaving `0x12000–0x1FFFF`
unclaimed. App is at `0x20000`, so **the D4 collision geometry does not apply here.**

**The margin is exactly one sector and that is the whole risk.** `phy_init` ends at `0x12000`; the
persona starts at `0x12000`. **Zero gap.** A 4 KB *sector* erase is safe; a 64 KB *block* erase at that
address would take out `phy_init` **and** `nvs`. So the write must be sector-granularity, verified after.

**Honest status: brick-safe today, defended by nothing.** Two partition tables are in play across the
catalogue and the platform runner, so the gap's existence depends on which flow last flashed the board.
→ `gate 27: provision` (recommended, with sector-only write + post-verify) / `gate 27: hold`

**[g26 — can a device that missed a cutover still be updated over the air?](gates/g26-update-header-version-reachback.md)** · **one line, the tail of your g25 ruling**
**Your g25 answer separated three version axes and settled two.** Wire message-passing: backwards
compatibility **mandatory**, slow-moving, old devices **expected**. Plugins and sentants: **their own
versions**, independent of firmware. Both landed and dispatched.

**The third axis is the OTA package header, and it inherits a consequence you may not have intended.**
Canon specifies **strict single-version cutover** — a receiver accepts *only* the current header
version, checked **before** the signature. So a device still on v2 **cannot be updated over the air by a
v3 pusher, ever.** Combined with *"we expect to find devices that have older versions"*, any device that
misses a cutover is **permanently un-updatable except by physical recovery** — and on a sealed field
unit, that can mean not recoverable at all.

**Recommendation: the pusher emits the receiver's accepted version.** Cheap here in a way it is **not**
on the wire: the pusher is an active participant that **knows its target** and can be updated freely, so
old-version support costs one encoder on the **reachable** side. Nothing changes on the constrained
device. → `gate 26: pusher speaks the receiver's version` / `physical recovery is acceptable`

**Not a decision, but it explains why this surfaced late:** canon already **required** a conformance test
for exactly this case — a v2 parser meeting a v3 header is the **first named item** in a
must-prove-before-freeze list, still open. It was never built, so **its first execution was a blocked
update path on metal instead of a red test.** The drift was not the defect; the **missing
drift-detection test** was.


**[g24 — which WiFi does the OTA proof join?](gates/g24-ota-bench-ap-credentials.md)** · **RULED overnight, pending your review**
**Answer: synthetic AP.** Alfred has a spare, idle, route-free, AP-capable 2.4 GHz radio, so we use
an SSID and passphrase **we choose** — synthetic by construction, no secret, no custody, and g23
leaves this path entirely. **This reversed my own earlier ruling of real-creds-via-env**, which I
had made believing a synthetic AP needed a human awake. The premise was refuted, so the ruling
changed. Alfred's sole uplink radio is explicitly not to be touched. Overturn in one line if you
disagree; the original argument is kept intact in the brief.

**Superseded original framing, kept for the sequence:**
Both OTA images are **built, attested and eligible** — mark-valid is health-gated, rollback is
intact, two-leg eligibility passes on both with positive *and* negative controls. The only thing
between them and a flash build is **which network's credentials get baked in**. The lab SSID/PSK
are the captured infrastructure from g23. **Recommendation: a synthetic bench AP** — identical code
path, identical proof, zero captured infra in any build, and it takes g23 off the critical path.
Real creds via env are permitted under canon (never as a literal in a tracked file, per
R2-SECRETS §3.1) but buy no proof benefit. Note: a lane called these creds "held under your
ruling" — **they are not; you have ruled nothing here** and use is not publication. Corrected.
`gate 24: synthetic` or `gate 24: real creds`.

**Also yours, not a gate, nothing waiting on them:** two hardware-history facts settle how an old
firmware module gets *recorded* (not what any new code does) — **was a MAX485 ever physically
soldered to a radar rig**, and if never, **was one planned or on hand?** First kills "stale", second
separates a misread from code authored against an intention that never became hardware.


**[g23 — a captured home network is published in a public repo](gates/g23-public-fleet-repo-leak.md)** · **read this one first**
**The gate changed shape today and this is now its centre.** The bench-flash lane answered the
invented-or-captured question against itself: **two groups are CAPTURED from its real rig** — a
named home wireless network, four hosts at specific addresses, a mesh-VPN presence, real board
names — logged as operational measurements, not examples. **It is in that lane's own public repo,
tracked, and zero commits ahead of its remote, so it is live now.** Verified independently.
Nothing scrubbed: a scrub destroys the evidence of what was captured. **A third group is unowned** —
two lanes have ruled themselves out; if it is yours only you can say. Needed: go-ahead to enumerate
privately, a scrub decision, and an answer on the third group.

The rest of the gate, still open and less urgent:
**No keys, no MACs, no personas — now checked on all five, not just this one.** What is exposed is
structure: **~20 private-repo-name mentions and ~360 commit-id-shaped tokens**, including in the
repo that serves the org's public website. One thing needs your eye: a **trust-group identifier**
appears in two of the ledgers, **and I asked you the wrong question about it** — canon already
governs it, the test is real-provenance not chosen-versus-derived, *chosen is on the real side*,
and it is **not** in the synthetic allowlist so it is treated as real until certified. **Going
private does not remediate it** (canon says *any* repo). The real question is *which* trust group
it is — its owner can answer that, and that answer is the whole decision. **Caveat, found by the
lane that owns the certification tool and reported against its own interest:** the scanner reads
only the first 8 hex digits of a UUID-form identifier, so allowlisting one **certifies a fragment**
and a green cannot tell two groups apart. Instrument held, not fixed, so it does not pre-empt you. **And the bigger half is not
prose at all:** **seven of ten public repos declare a git dependency on a private repo URL with a
pinned commit id**, ~48 files, stated in plain words as private. **That cannot be scrubbed** — the
URL is load-bearing — so it needs its own answer: accept, vendor, or make the dep repo public.
Lane-owned throughout, so **your ruling must be dispatched, not executed by me**.
→ `gate 23: stop publishing bookkeeping` / `make them private` / `scrub forward only` / `rewrite history`

**[g21 — the dedup key](gates/g21-join-dedup-key.md)** · **much smaller than I first wrote**
You said check canon first, and canon had already ruled it: `GROUP_MGMT` dedups on `msg_id` alone,
NORMATIVE since v0.68, with fabricating an origin explicitly forbidden. There is no key to choose and
the type-aware rider is already canon. **My earlier brief would have had you overrule landed canon.**
One narrow question survives: §8.2 says the narrow key is sound *because these frames are not flooded*
— and your g15 ruling moved that premise from zero hops to at-most-one-carried.
→ `gate 21: rationale holds, close it` / `re-examine the soundness premise`

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
| 22 | Shared crates vendored per-repo | **sync procedure — use versioning** (Roy 2026-07-26): keep the copies, no path-dep, no declared forks. Versions must MOVE so the gap carries signal. Obligation keys on (repo, crate, pinned-canon-sha); content hash stays as the verifier that a bump was not forgotten. Bench safe throughout — an unfixed copy cannot carry a join. g15 identity half UNBLOCKED; reaches metal at next re-vendor, not by hot-fix | D-20260726-S29 | [g22](gates/g22-shared-crate-vendoring.md) |
| 13 | Radar board-fit — ~29 columns needed vs ~28 available | **RESOLVED into a two-board split** (Roy 2026-07-26): it does not fit one board. Power board and logic board BOTH built and bench-verified — power steady at both rails, logic powers clean. Supervisor's index had it listed open after the ruling; corrected by circuits | — | [g13](gates/g13-radar-board-fit.md) |
| 15 | Join relay — may a sovereign JOIN traverse the mesh? | **RELAY PERMITTED; NO HOP BUDGET** (Roy 2026-07-26): intended case is **ZERO hops — direct connection**, physical presence; relay allowed when needed under the same single-hop rule (worked example: a UDP hive) = **at most one** intermediary. Lanes' NO was against mesh FLOODING and survives intact. Origin-less drop needs a join exception; hop semantics 0 direct / ≤1 relayed; 5 is boilerplate. **Dedup key NOT settled — g21** | — | [g15](gates/g15-join-relay.md) |
| 25 | Update version negotiation trigger | **RULED 2026-07-27** — *always deploy latest unless a specific reason (eg hardware incompatibility); older-version devices are expected on the network; backwards compatibility in message passing is mandatory and slow-moving; plugins and sentants carry their own versions independent of firmware.* Separated three version axes the gate had collapsed into one; axes 1 and 3 settled, axis 2 (update header) spun out as **g26** | D-20260727-45 | [g25](gates/g25-update-version-negotiation-trigger.md) |
