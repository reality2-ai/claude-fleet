# Key decisions — claude-fleet

Durable index of key repo-local rulings. Read it before changing established behaviour.
It is not a task log and does not replace specifications, ADRs, or code.

## Rules

- Append key human/canonical rulings, explicit holds, and consequential agent
  implementation choices. Routine edits, experiments, and task status stay out.
- Name the actual decision-maker and authority basis. An agent choice is delegated
  judgment; never label it human-ratified or let it override canon.
- A decision records context, rationale, alternatives, expected consequences, and
  evidence. Existing records are immutable.
- Review a decision by appending an `R-...` record naming the decision, reviewer/date,
  observed outcomes, evidence, recommendation, and one finding: `appropriate`, `revise`,
  or `insufficient evidence`. A review does not itself change the ruling.
- Change a ruling only through a new decision that names the old ID in `Supersedes`.
  Current means the latest applicable decision not superseded by a later one.
- Newer explicit authority or normative material wins a conflict; append the correction.
- IDs are `D-YYYYMMDD-NN` for decisions and `R-YYYYMMDD-NN` for reviews.

## Records

### D-20260721-01 — Repository decision log

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** Repository process
- **Outcome:** Keep a terse repo-local log of key decisions and later reviews.
- **Decision-maker:** Roy
- **Authority basis:** Explicit user ruling
- **Context:** Key rulings were dispersed across transcripts, handoffs, and design files.
- **Rationale:** A uniform durable record makes reasoning and later appropriateness
  analysis discoverable without treating temporary agent prose as authority.
- **Alternatives:** Transcript/RESUME-only history was rejected as transient; ADR-only
  history was rejected because not every important ruling is architectural.
- **Expected consequences:** Easier audits and fewer re-litigated decisions, at the cost
  of one concise record when a key ruling is made.
- **Evidence:** Roy's 2026-07-21 request; [AGENTS.md](AGENTS.md).
- **Supersedes:** None

### D-20260721-02 — Fleet member onboarding and decision accountability

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** New fleet repositories and managed-agent workflow
- **Outcome:** Onboard a repository with a non-overwriting two-layer template: a terse
  shared contract and an explicit repo map covering authority, dependency direction,
  ownership, invariants, and verification. Managed agents consult the decision log before
  edits; publishing requires each new commit to update it or explicitly acknowledge the
  applicable decision or absence of one.
- **Decision-maker:** Roy for the required behaviour; Codex for the delegated mechanism
  choice.
- **Authority basis:** Roy's explicit 2026-07-21 instructions; implementation delegation
  within the fleet control-plane task.
- **Context:** Per-repo instructions share substantial policy but differ in authority and
  upstream/downstream relationships. A passive log can be forgotten, while duplicated
  prose grows context and invites contradictory interpretations.
- **Rationale:** One scaffold removes repetition, unresolved repo-map markers prevent
  agents from guessing, a central launch rule guarantees recurring visibility, and the
  existing pre-push boundary makes omissions reviewable without blocking local safety
  commits.
- **Alternatives:** Free-form per-repo instructions were rejected as drift-prone;
  overwriting existing files was rejected as destructive; commit-time rejection was
  rejected because it can prevent a recovery checkpoint.
- **Expected consequences:** Faster, consistent onboarding and auditable choices with a
  small trailer cost on routine commits. Repositories must complete their unique map
  before cross-repo or behavioural work.
- **Evidence:** Roy's requests for a new-repo template, shared/unique agent information,
  dependency mapping, and a log agents cannot forget; `templates/repo/`, `bin/fleet`,
  `hooks/git/pre-push`, `tests/smoke.sh`.
- **Supersedes:** None

### D-20260721-03 — Install every shipped repository hook

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** Git-hook deployment and drift detection
- **Outcome:** `fleet install-git-hooks`, `fleet init-repo`, and `fleet doctor` manage both
  shipped repository hooks: pre-push publishing safety and commit attribution. Preserve
  and chain foreign hooks.
- **Decision-maker:** Codex
- **Authority basis:** Delegated control-plane implementation and optimisation within
  Roy's fleet-hardening request.
- **Context:** Review found the tested `hooks/git/commit-msg` source present but missing
  from all seven deployed repositories because the installer and doctor knew only about
  `pre-push`.
- **Rationale:** A defined but undeployed guard is a false green. One enumerated hook set
  keeps installation and drift checking aligned without another command or copy process.
- **Alternatives:** Manual copying was rejected because it recreates silent drift; a
  second installer was rejected as needless mechanism; replacing foreign hooks was
  rejected as destructive.
- **Expected consequences:** Commit attribution becomes consistently deployed and drift
  becomes visible. Existing foreign hook behaviour continues through `.local` chaining.
- **Evidence:** Seven-repository `.git/hooks/commit-msg` inspection; `lib/githooks.sh`,
  `hooks/git/commit-msg`, and the positive/negative installer tests in `tests/smoke.sh`.
- **Supersedes:** None

### D-20260721-04 — Autonomous writers and automatic refuters in the R2 fleet

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** Fleet startup, permissions, and refutation topology
- **Outcome:** The R2 workspace starts its Claude lanes with explicit autonomous
  permissions, automatically starts Codex refuters, and sends `carry on` on fresh and
  resumed starts. Codex refuters operate unattended inside a read-only sandbox with
  approval set to `never`.
- **Decision-maker:** Roy
- **Authority basis:** Explicit user correction after the simplified fleet was tested
- **Context:** The migration disabled automatic pairs, replaced the first-start action
  prompt with an idle seed, and left autonomy partly implicit. The supervisor Codex
  companion also lacked the non-interactive flags already applied to worker refuters.
- **Rationale:** Independent writers and refuters are intentional fleet capabilities;
  removing them changed behaviour rather than merely shortening instructions.
- **Alternatives:** On-demand-only refuters and prompt-gated lanes were rejected for this
  workspace. Restoring long prompts was unnecessary because permissions, topology, and
  continuation are separate compact controls.
- **Expected consequences:** `fleet up` uses more agent lanes but resumes useful work
  without permission stalls; Codex refuters can inspect freely but cannot write.
- **Evidence:** Roy's 2026-07-21 correction; `.fleet/env`; `lib/provider.sh`,
  `lib/tmux.sh`, `bin/fleet`, and `tests/smoke.sh`.
- **Supersedes:** The unrecorded 2026-07-21 local choice to make persistent refuters
  opt-in for the R2 workspace

### D-20260721-05 — Intentional stop does not create RESUME staleness debt

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** Doctor handoff-state validation
- **Outcome:** Continue checking stopped managed repositories for a present, bounded,
  placeholder-free `RESUME.md`, but do not compare its mtime with activity generated by
  an intentionally stopped session.
- **Decision-maker:** Codex
- **Authority basis:** Delegated implementation judgment within Roy's fleet restoration
- **Context:** A fresh seed-only start and `fleet down` updated session activity without
  producing repository work. Doctor then reported five valid handoff files as stale.
- **Rationale:** Intentional shutdown is not evidence of unfinished work. Structural
  checks remain useful; timestamp freshness is meaningful only for a non-stopped lane.
- **Alternatives:** Touching or committing five unchanged RESUME files was rejected as a
  false audit trail; disabling all RESUME checks was rejected because it hides real gaps.
- **Expected consequences:** Start/stop trials stay green while active or crashed work
  still creates visible handoff debt.
- **Evidence:** Reproduced in `/R2` after the 2026-07-21 trial start; `bin/fleet` and
  stopped-session regression in `tests/smoke.sh`.
- **Supersedes:** None

## 2026-07-22 — pre-push sk-key pattern: anchor left boundary, keep body charset
- **Decision:** `hooks/git/pre-push` sk-key value scan becomes
  `(^|[^A-Za-z0-9])sk-(ant-)?[A-Za-z0-9_-]{20,}` (left boundary added; body charset unchanged).
- **Authority basis:** Supervisor tooling ownership (this repo); fix for the reproduced
  ask-fork false-positive class (composer's push blocked 3x on synthetic fixtures).
- **Context:** Loose pattern matched `sk-` mid-word, so hyphenated slugs containing
  "ask-fork…" tripped the gate. Composer proposed narrowing the charset to unbroken alnum.
- **Rationale:** Charset narrowing FALSE-NEGATIVES real Anthropic keys — `sk-ant-api03-…`
  breaks any unbroken-alnum run at `api03-`. Verified both ways against real-format
  synthetics; boundary form flags sk-ant/sk-48 keys and passes the slug.
- **Alternatives:** Composer's `sk-(ant-)?[A-Za-z0-9]{20,}` rejected (misses the exact key
  class the line exists for; its positive control planted wrong-corpus keys).
- **Expected consequences:** ask-fork-class false positives stop; real-key detection
  unchanged; composer's key-hygiene.sh (be52729) needs the same boundary fix.
- **Evidence:** Control run against the production-extracted pattern 2026-07-22
  (realkey sk-ant FLAG / sk-48 FLAG / slug pass / line-start FLAG).
- **Supersedes:** None

## 2026-07-22 — pre-push sk-key scan: adopt composer v3 two-stage (supersedes d54e6d3 entry)
- **Decision:** sk-key value scan = boundary + `[A-Za-z0-9_-]{40,}` run, AND matched run
  carries >=2 digits (two-stage grep). Adopted from r2-composer tools/key-hygiene.sh 80cc2bb.
- **Authority basis:** Supervisor tooling ownership; composer's empirical counter-finding.
- **Context:** d54e6d3's boundary-only form still flagged sk-prefixed hyphenated slugs
  >=20 chars at word boundary (SpinKit-class identifiers; composer's fixtures = 3 live
  push blocks). Boundary fixes mid-word (ask-fork) only.
- **Rationale:** Real keys are ~50-100-char hyphen-inclusive runs and api03-/base64url
  guarantee digits; prose slugs are short or digit-less. Both directions control-tested
  against the production-extracted pattern (real sk-ant FLAG / bare-48 FLAG / mid-word
  pass / sk-slug-32 pass / 44-digit-less pass / short-digit pass).
- **Alternatives:** Keeping boundary-only rejected (live false-positive class persists);
  length-only without digit gate rejected (44-char digit-less slugs would flag).
- **Expected consequences:** Known accepted edge: a real key with body 20-39 chars would
  pass stage 1 — no known sk-/sk-ant provider issues keys that short; revisit if one appears.
- **Evidence:** Control run 2026-07-22 (six fixtures above); composer self-test 7/7 at 80cc2bb.
- **Supersedes:** 2026-07-22 "pre-push sk-key pattern: anchor left boundary" (d54e6d3).

## 2026-07-22 (night) — #d007 OVERNIGHT AUTONOMY: bit5 campaign linear flow (Roy asleep)

- **Decision:** Roy (verbatim): "DFR1195s, Xiao and Android are connected to tuxedo-os.
  I need to go sleep. Work through the remaining tasks to turn the table green."
  Interpreted as a bounded overnight grant for the bit5 campaign's LINEAR flow on bench
  boards D4+XIAO only:
  1. Pre-attested v7-diag images (XIAO 8a6dea89 / D4 3b412e54, built from 78177f50)
     flashable IFF sniff per-span verdict = XIAO-RX-side; composer two-party SHA verify
     mandatory before every flash.
  2. Subsequent fix images: hive builds under #d005-compliant supervisor orders naming
     the pinned sha; flashable within the same campaign scope only.
  3. EVERY flash op uses the full flash-safety preamble: ports resolved by-id at flash
     time (never ttyACM number), partition table passed explicitly, espflash plan
     tripwire (CONFIRM app@0x20000, ABORT if 0x10000), NO write to 0x12000 persona
     region, console closed during flash.
  4. OUT of scope overnight: D5 (#d004 held), RAK (frozen #d003), blerole/ghostfix
     images (explicitly never conflated with this flow), persona mints, history
     rewrites, HOTSPOT PSK, any repo-history or publishing action. Android lane may
     RUN its junit suite via tuxedo-os if JDK17 already present there — no toolchain
     installs on Roy's machines; absent toolchain = report and hold.
- **Rationale:** Roy armed the bench explicitly and named the goal; the campaign's next
  steps (diag flash, run-6, fix, verify) are the pre-ratified ladder. Holding every new
  sha until morning would make the instruction unfulfillable. Risk bounded: bench
  boards, USB-recoverable, brick class avoided by the preamble.
- **Expected consequences:** Morning report owed to Roy with a complete op log (every
  flash: sha, board, by-id port, verify result). If verdict = D4-TX-side, flow re-aims
  at D4-TX diag; new diag images buildable under the same rules.
- **Evidence:** v7-diag attestation (hive, pre-built); sniff instrument corpus-proven
  (poscontrol total=714/action=4; live run total=12593/action=33, drops=0).

## 2026-07-23 (night) — #d008 COEX CAMPAIGN CLOSED: 0x25 SUSTAINED PASS

- **Decision/outcome:** XIAO key-10 = 0x25 (BLE|LoRa|ESP-NOW) sustained 41.6 s
  contiguous (7 frames, 4x the >=10 s bar) — campaign PASS, executed under #d007.
- **Chain:** sniff (corpus-proven filter after -d-vs-live radiotap divergence) refuted
  all three pre-registered RX-defect signatures; root = emit cadence (30 s keepalive)
  vs 8 s ADMIT_W liveness window, structural not defect. Fix = benchkeepalive
  8000->4000 (core bee0e996, off 56d39498, densify ancestor => bit2 rode along).
  Hive built + attested (XIAO d12ddcc8, D4 d818ffda); composer two-party verified,
  flashed under per-op .fleet/flash-authorization grants (gate honored, audit-logged),
  boot banners confirmed app@0x20000 + personas intact. Pre-pump soak: 0x24 sustained
  94.2 s (was ~47% flicker). CoC pump at XIAO's fresh post-reflash BLE addr lit bit0.
- **Also closed tonight:** v7-diag images (8a6dea89/3b412e54) ARCHIVED unflashed —
  decider showed bit5 ever-lit x1033 + 0x25 momentarily x3, admit path proven.
  0x17000 NVS role-write brick hazard re-surfaced (3rd time) and re-recorded;
  role overrides are bake-and-rebuild only. Android repo made fresh-clone-hermetic
  (codegen task c0fddca + R2_CORE_REF pin e7c3096); junit execution still pending.
- **For Roy (morning):** (1) key-10 window design tension — 8 s window < 10 s default
  health cadence means a quiescent conformant node is bit-dark by design; per-transport
  vs tier-keyed window = canon decision. (2) persistent-pump question if persistent
  0x25 is wanted. (3) composer webapp/dist/manifest.json left dirty (half-corrupt
  regen — regenerate or revert). (4) board-to-board BLE initiator slot (blerole
  c01c9db9 + blob a55810f9) awaits its own flash grant.

## 2026-07-23 — #d009 SINGLE-HIVE CANON AMENDMENTS RATIFIED (Roy): SECURED BRIDGE + MERGE-REFLASH

- **Decision (Roy, verbatim intent):** "go with your recommendations for 1 and 2 to
  match canon" — resolves the two canon-gating items in
  r2-android docs/design/HIVE-FIRST-ANDROID.md §6 (a)/(e) (note e06af14).
- **(1) Enclosure-security premise (§6a):** amend R2-COMPLEX-HIVE so a complex hive
  whose components do NOT share enclosure/power may conform via a CRYPTO-SECURED
  internal bridge (USB link keyed). The enclosure rule itself stays intact for true
  single-box complex hives (Uno-Q shape) — amendment adds the secured-bridge option to
  the §11.1/§2.2/§3.5 MUSTs, does not re-ground the boundary rule.
- **(2) Field-formed key sharing (§6e):** MERGE-REFLASH is the defined op — the XIAO
  is reflashed with phone-derived TG material via the existing bake path
  (DFR_ROLE_PATH-style), phone = identity holder. No live pairing ceremony now;
  ceremony may come later as convenience.
- **Consequences:** specs owns the canon amendment (spec-first); android's design note
  freezes once specs lands it; increment 5 (XIAO internal Usb=4 attach) unblocks at
  that point but any FLASH still rides its own per-op grant. §6 (b)/(c)/(d)/(6)
  remain scoped-but-open (recommendations sent, not ruled).
- **Evidence:** design note e06af14 §6; specs contradiction flags (a)/(e); Roy ruling
  this session 2026-07-23.

## 2026-07-23 — #d010 TIER-2 DESIGN-NOTE RULINGS (Roy): §6 (b)/(c)/(d)/(6) RESOLVED

- **Decision (Roy):** "go ahead with the tier 2 recommendations as well" — resolves the
  four remaining scoped items of HIVE-FIRST-ANDROID.md §6 (e06af14) per supervisor
  recommendations. Scope note: parked queue (window tension, pump, blerole slot,
  master merge, manifest.json, D5/radar, Alfred fork) NOT included — still Roy's.
- **(b) Intermittent above-L5 tier: NO NEW TIER.** Partition model suffices
  (R2-ARCH §1 Cor 1 + R2-TRUST silence=DG-1). Revisit ONLY if bench shows a real
  failure the existing tiers cannot name.
- **(c) Dev-ensemble privilege: the three ceilings ARE the rule** — own-TG
  entitlement, non-aggregation, single-TG. Nothing beyond them without a new ruling.
- **(d) Detach/reattach semantics: DEFERRED** until increment 5 work starts —
  behaviour falls out of the secured-bridge design (#d009). Explicitly not ruled now.
- **(6) Track-B collapse: CONFIRMED** — single-hive target collapses phone<->XIAO
  re-originator into an internal below-L5 attach; §4.3.6 re-attestation stays canon
  for genuine two-hive cross-tier paths only. Wire flips only at merge-reflash.
- **Consequences:** specs records (b)/(c)/(6) (ledger + minimal canon notes where a
  cite-target is needed; no big spec surgery); android updates §6 markers 3/4/6
  resolved + 5 deferred. Design note then fully frozen against v0.12.

## 2026-07-23 — #d011 BLEROLE FLASH PRE-GRANTED (Roy): D4 INITIATOR, SHA-CONDITIONED

- **Decision (Roy):** "go ahead with the flash when the shas are ready" — per-op flash
  grant for the blerole slot, conditioned on hive delivering attested shas.
- **Scope:** D4 ONLY (initiator image, blerole lineage carrying coex fixes off
  bee0e996, blob a55810f9 baked via DFR_ROLE_PATH). XIAO NOT a target (keeps
  d12ddcc8, acceptor = blob-absent). Third bench board (MAC F4:12:…, full value in bench notes) never a target.
- **Mechanism:** supervisor writes .fleet/flash-authorization (expires/artifact/
  target/sha256) once hive's sha is two-party verified by composer; full preamble
  mandatory (by-id port at flash time, csv e0e49127, espflash plan tripwire CONFIRM
  app@0x20000 / ABORT 0x10000, no 0x12000/0x17000, consoles detached).
- **DONE bar:** seen-on-metal — initiator boot-print + scan-to-connect handoff +
  bit0 on BOTH boards board-to-board (no host pump).

## 2026-07-23 — #d012 WiFi-STA RECLASSIFIED (Roy): OPTION (a) — NOT A COEX CELL

- **Decision (Roy):** "go with (a) for WiFi-STA" — Wifi·1 (SoftAP/STA infra) is a
  DEFAULT-image mode, mutually exclusive with ESP-NOW (WifiMesh·5) on the one
  2.4 GHz radio; the coex table stops owing it. No bench slot, no time-slicing.
- **Grounds (core scoping @bee0e996):** coex build has Wifi·1 dark by construction
  (serve_ap hardwired false, DATA_PLANE_JOIN.signal zero callers, no bit1 in health
  bitset); M8c join was suppressed at 56d39498 precisely because join-retry bursts
  desensed ESP-NOW. Canon: hive WiFi-band data plane IS the mesh.
- **Consequences:** matrix WiFi-STA cells (DFR1195/XIAO) reclassified to
  alt-image marker, not owed by coex proof surface; Android WiFi-STA unaffected
  (no ESP-NOW contention on phone). Future infra-mode proof = its own image +
  slot, only if ever needed.

## 2026-07-23 — #d013 GENERAL RULING (Roy): MCU RADIOS = TN-MESH ONLY; DONGLE MODEL

- **Decision (Roy, verbatim):** "As a general ruling, using the ESP radios (or
  equivalent) solely for R2 TN mesh. we can imagine this comes packaged as a
  plugin-in dongle. Other wifi / bluetooth / wired networking sits elsewhere."
- **Meaning:** the MCU-class radio set (ESP32 ESP-NOW/BLE, LoRa, nRF equivalents)
  is DEDICATED to the R2 transient-network substrate — mesh data plane, discovery,
  R2 OTA. Infra WiFi (STA/AP), general-purpose Bluetooth, and wired/Internet
  networking live on the HOST half of a pairing (phone, laptop, router) — the
  complex-hive split generalized to a product shape: the R2 radio as a plug-in
  dongle. Generalizes #d012 (no single chip owes both WiFi modes) from a bench
  reclassification to an architecture principle.
- **Consequences:** specs finds the canon home (spec-first); firmware never needs
  infra-WiFi + mesh coexistence on one radio; capability matrix per-board columns
  = TN duties only, host columns carry infra bearers.

## 2026-07-23 — #d013 ADDENDUM (Roy): TRANSPORT-PRESENCE SEMANTICS + EXCEPTION CLASS

- **Roy (follow-on, confirming the tenant-bearer framing):** the host's code "passes
  along a TCP-IP/UDP transport for R2 to sit alongside the others" — uniform
  presence semantics: exactly as a radio's presence/absence decides whether that
  transport exists in the table, the host's IP stack decides Udp/Inet presence.
  One rule for all bearers.
- **Hard consequence:** a XIAO or DFR1195 CANNOT take part in WiFi-AP/infra traffic
  — its radio is in use for R2 TN traffic. Not a limitation to fix; the ruled
  dedication (#d013).
- **Exception class (Roy):** simplified R2 implementations may be excepted — named
  example r2-workshop (browser/WS shapes). Default + exceptions, exceptions named.

## 2026-07-23 — #d011 ADDENDUM: SECOND ITERATION CONFIRMED (Roy)

- Roy: "go ahead with the reflash when the shas are ready" — explicit per-sha confirm
  for the rebuild from core fix 3ed2f818 (empty-registry L3 resolver starve; first
  iteration flash PASS but bit0-BOTH blocked at rbid resolution). Same slot, same
  scope (D4 only, XIAO untouched), new grant record for the new sha on delivery.

## 2026-07-23 — #d014 D5 RELEASED (Roy): SECOND SENSOR, OWN PERSONA, COMPOSER MINTS

- **Decision (Roy):** "bring D5 up to date as a second sensor - and of course it not
  exactly the same as D4 - it has a different persona, something that should be
  natural for Composer" — releases the D5 hold (#d004) for this purpose.
- **Scope:** D5 = second sensor per the #d003 bench roster (sine-wave
  ai.reality2.cap.env.scalar, simulated duty cycle). OWN persona (distinct hive_id —
  no-duplicate rule), shared TG. Composer owns the persona mint (its tooling).
  Image = pinned coex base bee0e996 lineage, D4-sensor recipe, D5 persona baked,
  no role blob.
- **Sequencing:** build + persona mint start NOW in parallel; D5 FLASH waits until
  the blerole bit0-BOTH retest completes (no mid-campaign bench confound). Flash =
  its own per-op grant on attested shas (Roy's standing pattern).
- **First:** composer's read-only D5 banner report establishes what persona/image it
  currently holds (may already have a valid persona to reuse — mint only if absent
  or invalid).
- **Roy follow-on (same ruling):** D5's simulated sensor = COSINE wave at a DIFFERENT
  frequency than D4's sine — the two streams stay distinguishable end-to-end.
- **Roy flash pre-grant (same pattern as #d011):** "go ahead with the D5 flash when
  the shas are ready" — sha-conditioned, still sequenced after the blerole retest.
- **Roy forward context:** "we have numerous other dfr1195s when we want to test
  more hives, and multiple TGs" — bench can scale to multi-hive / multi-TG
  (islands-of-sensitivity refutation) with existing DFR1195 stock; no purchase gate.
- **Roy (further):** "numerous other xiaos+loRa pairs to act in the same way (not
  necessarily as Android + xiao complex hives)" — XIAO+SX1262 stock = standalone
  hives too; complex-hive pairing is one deployment shape, not the default for the
  stock.
- **Roy priority ruling:** "before we get there we have to lock in the below TG
  functionality" — multi-hive/multi-TG scale-out is GATED on the below-L5 substrate
  being locked (bearers, routing/relay, discovery/liveness proven on metal). Table
  first; expansion after.
- **Roy layer ruling (waveform, supersedes the env-bake recommendation):** the
  simulated waveform "should be just a Sentant functionality (or ensemble without a
  plugin)" — waveform generation belongs at the SENTANT/ensemble layer, not as a
  compile-time plugin knob. Core owns the smallest implementation honoring that
  layer assignment.

## 2026-07-23 — #d015 KEY-10 LIVENESS WINDOW RULED (Roy, gate 1): BOTH AXES COMPOSE

- **Decision (Roy):** "both options A and B make sense" — the admit window composes
  BOTH bases: (1) PER-TRANSPORT — "LoRa must have a longer time-to-fade just due to
  the nature of the connection and the way lora is mostly quiet when not in use";
  (2) CADENCE-KEYED — "devices that have a regular time cadence, eg a sensor that
  turns on, reads a value and turns off must be able to have that cadence
  automatically become part of the timing."
- **Reading:** window = f(transport nature, node's own duty cadence) — a node's
  regular cadence AUTOMATICALLY folds into its liveness window (self-declared or
  observed cadence widens the window; transport physics sets the floor). Not a
  static constant on either axis.
- **Consequences:** specs owns the spec-first canon task (R2-HEARTBEAT window rule;
  compose with R2-ROUTE §2.4 class-scaled fade + SCF duty-class). Bench 4 s
  benchkeepalive unaffected meanwhile. Gate 1 CLEARED from ROY-GATES/artifact.
- **Roy follow-on (#d015, the lifecycle model — settles self-declared vs observed as
  OBSERVED, no exchange):** verbatim: "You turn it on for the first time as it is
  being installed. It shouts out to the rest of the network: I'm alive, and the
  nearby nodes add it to their list. Because it is part of the TG, its existence
  will never fully fade, but we can note when its cadence seems to get longer. As it
  then settles into its regular duty cycle, neighbours will notice that it comes on
  every half hour, so the fade cycle is adjusted to fit. This doesn't require any
  exchange of information per se, just a note of 'what seems to be normal for this
  hive' and when 'normal' is strayed from." Three normative consequences:
  (1) TG-member EXISTENCE never fully fades — only freshness/cadence annotations
  change (composes with partition≠eviction + silence=DG-1);
  (2) each neighbour LEARNS the per-hive normal cadence locally by observation —
  NO protocol exchange, no self-declared cadence field (no trust surface);
  (3) liveness signal = DEVIATION from that hive's own learned normal, not from a
  global constant. First-boot shout = the enrolment moment for the list.
- **Roy follow-on 2 (#d015, mobility axis):** "a wearable device in a crowd of other
  wearable devices attached to people moving around will have a much faster fade
  cycle" — the learned-normal model is per-hive AND per-mobility-class: a mobile
  wearable's normal is fast rhythm + transient network proximity, so its fade cycle
  is fast. Clarify in canon: never-fully-fades applies to TG MEMBERS' existence;
  non-member passers-by (the crowd's other wearables) fade out fully as ordinary
  strangers. Mobility = a third input to the learned normal (transport floor x
  observed cadence x proximity churn).
- **Roy follow-on 3 (#d015, the contact primitive):** "part of the way that a TG
  maintains contact between its members is a regular 'shout out to all'" — TG
  maintenance includes a periodic BROADCAST-to-all-members primitive (the standing
  rhythm the learned-normal model observes; first-boot shout = its first instance).
- **Roy (gate-2 context):** "given that all the hives at the moment belong to the
  same dev TG, that should work" — heartbeat/shout-over-BLE as the standing-liveness
  source is viable on the current bench (all boards same dev TG). Core scoping in
  flight sizes it.

## 2026-07-23 — SUPERVISOR INCIDENT: stale-cwd ledger commit into specs' repo

- My #d015-follow-on-3 ledger append ran with cwd = r2-specifications (stale from a
  verification step) — committed d6f46b1 onto specs' working branch, SWEEPING their
  uncommitted D-20260723-08 draft (39 lines) into my commit; reverted 9e27a37
  (no force-push), then RESTORED their 39 lines to their working tree uncommitted,
  verified intact. Net: two noise commits on their branch, no content lost.
- Lesson (recorded in memory): supervisor shell work MUST pin cwd per command —
  `cd /path && ...` in every mutating compound, never rely on prior state. The
  no-direct-repo-writes rule was breached by a MECHANISM (cwd drift), not intent.

## 2026-07-23 — #d016 GATE 3 RULED (Roy): manifest.json REGENERATE

- **Decision (Roy):** "Gate 3 - yes, regenerate makes sense" — composer regenerates
  webapp/dist/manifest.json cleanly and commits. Gate 3 CLEARED.

## 2026-07-23 — #d017 GATE 4 RULED (Roy): RADAR SET ASIDE; D5 = BENCH TEST TOOL

- **Decision (Roy):** "put aside the radar for now, [D]5 is a bench test tool from
  now on. We will deal with the radar later, and probably use a Xiao with that
  anyway." — SEN0676 attach deferred indefinitely; D5's standing role = bench test
  tool (cosine sim sensor); the eventual radar field node = XIAO-based, not DFR1195.
  Gate 4 CLEARED. (Field-node design memory updated: radar host leans XIAO.)

## 2026-07-23 — BLEROLE ITER-3 SPLIT VERDICT + D5 ATTESTED + GATE 6 OPENED

- **Iter-3 (ef26d7d0):** flash+role PASS; LIST GAP CLOSED (falsifier printed
  'expects 8c15b0c2 -> rbid 6084'; XIAO LoRa beacon resolves by name). NEW distinct
  blocker: XIAO's BLE R2-BEACON emits a TRANSPORT-SPECIFIC rbid (55ca) the resolver
  does not compute — derivation reconcile = core, in flight. bit0-BOTH still NO;
  composer stopped correctly on the pre-registered STOP condition.
- **D5 cosine sensor BUILT + attested (656cab50):** triple differential (wave took:
  != sin-build 61a5578d; role took: != no-role 3d6e9ec1), WaveSourceSentant at the
  sentant layer per Roy's ruling, minted persona baked. FLASH HELD — pending core's
  enumeration of whether ANY current image can resolve the bench personas (3rd
  list-membership question today; FR4-era ids != bench personas).
- **Gate 6 OPENED (gates/g6):** durable baked-roster registry from composer custody
  — the fix for the list-miss defect class. Roy lean requested.
- **#d016 EXECUTED:** composer manifest regen ab62a0e — and honest correction: the
  file was never corrupt, it was STALE pre-chip-split; delta is systematic. Possible
  generator follow-up (chip_profile lookup for arch/target_triple) flagged, parked.
- **#d015 chain COMPLETE at specs:** D-20260723-07/-08/-09; R2-HEARTBEAT v0.21,
  R2-ROUTE v0.79. Specs corrected my crossing-verify: their v0.19 declared-seed arm
  CONTRADICTED Roy's observed-only verbatim — removed in v0.20; correct outcome,
  my verify had under-checked that arm. Stale-cwd incident verified closed by specs
  with corrections accepted (their -08 draft committed intact via their 7edcb8f;
  my restore was correct minus my own 5-line bullet, which landed properly as -09).

#d014 addendum (2026-07-23, supervisor): D5 emitter 656cab50 STANDS — no provenance rebuild from 5c13a3c5. Hive enumerated diff 7766f53c..5c13a3c5 = receiver-side KNOWN_HIVE_IDS append only, no-op for D5's own resolver. Rebuild = zero behavior change + verify churn. Receiver-side coverage stays with core enumeration / g6 roster.

#d018 [RATIFIED] 2026-07-23 scope=transport-test authority=Roy (verbatim in gates/g2-persistent-pump.md)
  TRANSPORT-TEST DOCTRINE, closes gate 2: (1) TG heartbeat is NOT the transport test — L5/TG-scoped vs below-L5/TG-agnostic, and R2-ROUTE §5.2 legitimately steers heartbeat off any given bearer; pinning it = probe in heartbeat's clothes. Heartbeat proceeds separately (v0.21 TG-contact). (2) DEV BEARER-PING adopted: active ping between matching transports, DEV-duty, bench conformance instrument — the legitimate coex-bit source. Core's M sizing (cadence-into-CoC bridge + link lifetime) transfers; coex re-soak stays mandatory before standing-0x25 green. (3) BEACON-LEVEL AWARENESS to specs: passive per-bearer RX liveness from existing co-member beacon sightings (beacons ride every bearer by canon), zero added traffic; production shape, feeds calm proof-surface. (4) Pump dead; HB-over-CoC-as-bit0-source withdrawn. Spec-first: specs designs ping + awareness canon before core wires.

#d018 addendum (Roy, same day): 'beacon-like sentinels always checking what is around and adjusting the tables of nearby hives' — awareness is the EXISTING neighbour-table maintenance, not a new mechanism. Readout = per-bearer last-sighting age; same tables as #d015 liveness/fade, keyed (hive, bearer). Only NEW active mechanism = dev bearer-ping.

#d015 addendum (Roy, 2026-07-23): heartbeat bearer-migration — 'two hives get gradually further apart and the heartbeat would change which transport it actually goes through. This should happen automatically... BLE to ESP-NOW to LoRa to UDP-via-relay.' Consequences dispatched to specs: automatic §5.2 re-selection per pulse + hysteresis; W_T re-clamps to new floor_T on migration (transport-change = expected, not astray); (hive,bearer) tables show recession as calm distance signal; NAMED TENSION for specs: ladder's UDP-via-relay rung vs v0.21 §6.1 one-hop-never-relayed — reconciliation to be designed, not silently rewritten.

#d019 [RATIFIED] 2026-07-23 scope=tg-contact authority=Roy (verbatims in gates/g7-tg-contact-hops.md)
  GATE 7 RULED: TG-contact pulse one-hop RELAXED TO TWO-HOP — one go-between allowed (TTL=2); Roy ordered specs to MODIFY CANON, superseding in scope specs' D-20260723-11 one-hop-stands resolution. Specs' IP-transit reading survives as the hop-1 case (id-6 bearer transit != R2 hop); the change additionally admits ONE R2 go-between (repeater-relayed pulse). Constraints in the design order: TTL accounting at the go-between (no chain masquerade); complex-hive bridges count zero (#d009); relayed-pulse rate/suppression bounds O(N)+privacy — one island boundary is the point of 2-not-N. Specs landing pending.

Batch status 2026-07-23 (post-#d018): bench re-sequenced — remote quiesce infeasible on D5 USB-JTAG (DTR/RTS resets, cannot hold dark); composer option (ii) approved = before/after 55ca recording around the D5 flash (reflash touches only D5, so persistence-after attributes to XIAO cleanly); D5 grant revised in place. Core (a) committed a592ae70 (branch only; capture-gated-on-RESOLVED + resolved-hive CoC label). Core (b) unblocked by specs D-20260723-12 (election = membership op, GroupHmac + self-asserted hive sufficient, RBID-resolved eligibility). Iter-4 = one wave: D4(a)+XIAO(b) build pair, then full bit0-BOTH + NEG-completion. Specs landings verified on main: a62c579 (migration folds: ROUTE v0.80 hysteresis, HEARTBEAT v0.23 W_T-follows-transport), 25480e5 (D-12), 88fe8e3 (g6 canon: PROVISION v0.120 lifecycle two-planes, DISCOVERY v0.18 runtime member-set + dev-tier seed, D-13). Composer wire_id-0 refutation resolved via android f4a5821: phone = client-only (no advertiser code exists), skip correct forever + logged. g6 awaits Roy's one-word close.

#d020 [RATIFIED] 2026-07-23 scope=member-registry authority=Roy verbatim 'gate 6: adopt as dev seed'
  GATE 6 RULED: baked roster ADOPTED as DEV-TIER SEED of the runtime member-set (canon: R2-PROVISION v0.121 §1.2, R2-DISCOVERY v0.19 §3.3, ledgers D-20260723-13/-14). Execution dispatched: composer merges feat/tg-roster-blob @7346f8a (4-member 730c29e7 roster, u32 = FNV-1a projection of per-TG hive_id, linkability-checked); core wires mutable member-set seeded from BAKED_ROSTER, populated in prod by proximity enrolment + GroupHmac-frame learning; compile-time KNOWN_HIVE_IDS + one-off peer constants RETIRE. Kills the hardcoded-id miss class (4 instances in 2 days). wire_id-0 phone member: client-only, never beacons — skip correct forever, logged.

#d021 [RATIFIED] 2026-07-23 scope=alfred-rig authority=Roy verbatim 'gate 5: defer until phone-pair merge proven'
  GATE 5 RULED: Alfred rig stays TWO sovereign hives + relay (conformant; keeps inter-hive relay under continuous bench test). REOPEN CONDITION: §10.5 merge-reflash + #d009 secured bridge proven ON METAL on the phone+XIAO pair — Alfred then adopts a proven op. Merge-follows-permanence doctrine stands (resident MCU merges; visiting MCUs = two-hives+relay; attach/detach = bearer event never identity event). No lane action required; status quo is the ruling.

#d022 [RATIFIED] 2026-07-23 scope=bench-flash authority=Roy verbatim 'yes'
  D5 ITER-5 REFLASH AUTHORIZED (fresh word; prior #d014 grant consumed by 656cab50). Image: d5-cos5.elf 11f2d2ef from unified 471f0cf7 (adds member-set roster feed + signed-i16 value-print; cosine attested cos!=sin). Sequence: two-party verify all 3 on alfred -> D4 c51ad8a6 -> XIAO 90d3f489 -> D5, one-op rolling grants (pair under #d011 standing slot). Post: election-driven bit0-BOTH retest + cosine value samples; logger rotates per flash with BUILD_ID coex.iter5.0723.

#d023 [RATIFIED] 2026-07-23 scope=bench-milestone authority=supervisor (Roy standing ask 'carry on and let me know the iter-7 result')
  BIT0-BOTH GREEN ON METAL — iter-7 pair b5de845c (coex.iter7.0723; D4 59de5979, XIAO 42300f6e). Co-boot capture, positive control MET: D4 captured+dialed XIAO -> ACL accepted -> L2CAP CoC accept -> serving; membership-verified BOTH directions; key0a 0x25 both boards; drops 0; accept-ERR 0. Root cascade closed: (1) unconditional dial capture (fixed iter-6 ca198a5a lowest-eligible), (2) initiator self-elect timing race (fixed iter-7, provider_capable derived from ble_role per R2-DISCOVERY §4A.6), (3) BRANCH-2 accept-hang REFUTED — earlier accept-null was a failed positive control (D4 wedged, not dialing); composer's null-discipline prevented a false verdict twice.
  TWO-BAR RULING (supervisor, canon-checked): iter-7 campaign bar (pre-declared full-green matrix) = MET one-shot; LADDER RUNG (board-to-board bit0 replacing the CoC pump) inherits the ratified coex sustain standard (>=10s) = OPEN, iter-8.
  ITER-8 SCOPE (core, canon-reshaped by specs verdict): sustain root = initiator stops scanning in serve_coc => XIAO pruned at t_fallback=5s => disrupted => excluded => re-elect falls to D5 distractor. Fixes: CoC keepalive + roster-refresh-on-inbound-control (load-bearing) + serve_coc watchdog (conn.next + is_connected + long half-open backstop; NOT short idle-timer — would drop bit0 on alive-idle link). Canon (specs): #d013 => ALL MCU bench boards must advertise provider_capable bit2=0 (radio dedication; D5's hardcoded true = old-image conformance bug); R2-BEACON v0.19 Occam cut => provider election is Mode-1b non-transient only — core reconciling why an election ran at all. D5 stays powered on 11f2d2ef (load-bearing repro).
  Decision-Log: #d023

#d024 [RATIFIED] 2026-07-23 scope=bench-milestone authority=supervisor (two-bar ruling closure)
  SUSTAIN RUNG GREEN — bit0-BOTH SUSTAINED on metal, ladder rung bar (>=10s, inherited from ratified coex standard) MET at >=22s BOTH boards, zero dips, zero wedge. Iter-8 pair 351a166e (coex.iter8.0723; D4 1b0186db, XIAO 74857e1c; KEEPALIVE_MS=2500). Mechanism: bidirectional 2.5s membership-enveloped 1B CoC keepalive (9-10 pings each way over ~25s) — refreshes peer roster (no prune -> no disrupt), re-stamps bit0 (<8s window), tx-error = return-on-disconnect (wedge subsumed). Test run with D5 powered distractor on old image (stronger condition: XIAO held as session peer with D5 in roster). DECOUPLING PROVEN: D4 still elects D5 as data-provider at boot, yet CoC/bit0 sustains regardless — validates iter-9 premise (bit0 fully keepalive-driven, election-independent). ITER-9 (parked conformance, core): bit2=0 constant all MCU (#d013), ap_capable=false constant, capture decouple :4807, v0.19 election reconcile; one re-score. Board-to-board BLE-CoC campaign: iter-5 dial fix -> iter-7 eligibility fix + accept proven -> iter-8 sustain. CLOSED.
  Decision-Log: #d024

#d025 [RATIFIED] 2026-07-23 scope=bench-milestone authority=supervisor (iter-9 conformance close)
  ITER-9 CONFORMANCE PASS — co-boot re-score green on ALL 5 revised-bar points. Pair 70960dbc (coex.iter9.0723; D4 724383ea, XIAO 5fb1565f); D5 untouched on 11f2d2ef (nonconformant distractor, load-bearing). (1) CAPTURE-DECOUPLE PROVEN: D4 resolved XIAO (rbid 6084) and dialed 8c15b0c2 (lowest-RESOLVABLE), not D5 — earlier D4-dials-D5 was boot-order confound (XIAO mid-reflash, down), resolution-bug arm did NOT trigger. (2) sustain unchanged: 0x25 both, accept path complete, wedge 0. (3) bidirectional 2.5s keepalive (D4 RECV x10, XIAO RECV x21). (4) election Some(D5) = canon-correct (D5 old image sole advertised-eligible; #d013: MCU MUST bit2=0, D5 true = legacy nonconformance). (5) XIAO bit2=0 confirmed via exclusion from provider-election while still CoC-dialable (dial/election decoupled). XIAO now elects None (self provider_capable=false, engine NodeCaps constant).
  STICKY-SESSION ruled INTENDED (core): capture = formation tiebreak not continuous election; self-heal on any disconnect via dial-loop re-scan; bounded gap (healthy wrong-pairing never re-homes) reachable only via nonconformant distractor; re-home-iff-strictly-lower-AND-cur!=elected sketch PARKED for deployment.
  PROCESS: pre-score bar revision (elect-None -> Some(D5) accepted) lived only in grant NOTE => composer, hive, core each independently refuted the stale bar; corrected; standing rule = push bar revisions to every scorer at revision time.
  OPTIONAL (Roy word, not required): D5 reflash 70960dbc = one-lineage + elect-None end-state demo. Campaign fully closed pair-only.
  Decision-Log: #d025

#d026 [RATIFIED] 2026-07-23 scope=bench-campaign authority=Roy verbatim "OK. All devices are on the bench, connected to tuxedo-os. let's get the rest of the board green over night."
  OVERNIGHT MATRIX-GREEN CAMPAIGN AUTHORIZED. Scope: remaining code-ready (◑) cells of the reference matrix, bench boards D4/D5/XIAO on tuxedo-os. Roy's word = standing authorization for tonight's bench flash ops on the ESP32 trio; supervisor still issues per-op sha-locked grants one at a time (gate discipline unchanged). RAK stays FROZEN per #d003 (not named by Roy; #d001 image preserved). Wave-0 (in flight): D5 conformant reflash a0157eb2 + 3-board bar-A score. Wave-1 targets (cheapest metal first): LoRa + ESP-NOW BEACON plane (B cells — code-ready in 70960dbc, may green by observation alone), extended-wire-on-metal check. Wave-2: OTA rung (ota-tcp, ESP32-only, canon preflight: OTA authority TG-locked). Wave-3 (no flash): wasm hive legs — UDP/TCP + web UX visualiser on tuxedo; android Inet/UDP legs if cheap. L6 re-attest (all-✕) = code+KAT overnight only if lanes free, metal not promised. Bars pre-declared per wave and pushed to ALL scorers before metal (standing rule).
  Decision-Log: #d026

#d026 addendum (wave-0 CLOSED, 2026-07-23): 3-BOARD BAR PASS — all falsifiers clear. All three boards one lineage 70960dbc (D4 724383ea / XIAO 5fb1565f / D5 a0157eb2), all bit2=0, personas preserved. FA1: ALL elect None (zero bit2 leak — the elect-None end state Roy asked for). FA2 KEY: with TWO live resolvable acceptors D4 capture-dials XIAO 8c15b0c2 (lowest-hive) not D5 — tiebreak proven on metal, the arm iter-9 co-boot could not run. Pair sustain: 0x25 + bidirectional keepalive (10/31); one transient Disrupted blip on XIAO in ~120s self-re-established (flagged to sticky-session robustness watch, not a wedge). FA4: D5 resolvable + cosine-emitting + bit0-dark unpaired, zero pair disruption. Decision-Log: #d026

#d026 addendum-2 (wave-1 SCORED, 2026-07-23 night): 4 CELLS PASS by capture alone, no reflash (3 boards, 70960dbc lineage, lora_route_task/xiaobridge-off build). LoRa-B: cross-board — each board's beacon received by BOTH peers (D4 rbid 5bb017 / XIAO 60846c / D5 607061), duty-throttled 16-25/82s no fixed cadence, DROPPED=0, rbid keyed != hive_id. BLE-B: XIAO+D5 adv up, D4 resolves both, D4 silent (initiator-correct). ESP-NOW discovery (data-as-beacon per canon — no dedicated beacon profile exists): key-10 bit5 set all 3 with peers MAPPED + live HB. EXTENDED-WIRE L2: ESP-NOW HB = extended frame (22B hdr+32B HMAC) decoded + HMAC-attributed cross-board full 3-mesh => L2 layer row fully metal-proven. RULINGS folded: beacon B cells roll up PARTIAL (specs: s8.1.2 rotation MUST unmet — epoch=0 static, rbid never rotates, keyed-but-correlatable; no waiver below Roy; fix path = shared coarse-time base s6.1 :312, HB beat reference allowed). CORRECTIONS: earlier "foreign non-apiary" beacon-class attribution REFUTED — 43895E89/BAFE8AC1 are OUR sensor/hive classes (main.rs:5511 FNV table); composer's "rotation every 900s" remark struck (static epoch). OPEN: D4 observed class=bridge, XIAO=hive — baked-role confirmation at hive. Decision-Log: #d026

#d026 addendum-3 (wave-2 OTA rung, 2026-07-24 night): CYCLE STAGED + BLOCKED-ON-PHYSICAL (g9 replug). RULINGS BATCH: (1) AGENT-PUSH AUTHORITY — metal OTA push agent-triggered ONLY under live supervisor grant; CLI operator-only guard governs otherwise (scope: tonight/D5/grant). (2) SECTOR ERASE — one-time targeted {0x18000,0x1A000} erase authorized+executed, FF-verified (pre-table contamination left garbage floor 0x72726f63); personas untouched. (3) CUSTODY PATH A ratified (D-20260723-01): tg ota-sign in-memory unseal + --signed-stream (b542e36); raw TG_SK never on any FS. (4) ABI SKEW ruled (A): board vendors r2-update v2 (123B/PACKAGE_VERSION=2), composer emits bench-scoped --header-v2 (87c6466, D-20260723-04); main vendor stays v3; board v2->v3 re-vendor = post-campaign spec-first. PROVEN ON METAL: v2 header ACCEPTED ('OTA(L2CAP) start seq=1 payload_size=897504'). (5) RESP FRAMING ASYMMETRY — board sends RESP RAW (RESP_OK 1B :7922-class, OAK 7B per-ODT :7974) while inbound is [len u16 LE]-framed; ruled (b) composer raw reader (8fa69aa) tonight — decisive fact: P1-INSTALLED image serves P2a/P2b/P3, so a board-side fix tonight = full payload-chain redo; board frame-RESP folds into v3 re-vendor reflash. All 3 lanes converged independently. PROVEN: raw RESP_OK + OAK cum=200 read on metal. (6) OCCUPANCY ESCALATION — test-first held run dropped mid-ODT-burst 1/4488 (not flash-sector: cum 400<4096; not protocol: OAK per-ODT at source) => 3c8ea9e1 (Le2M+DLE 251/2120+credits 32) UN-HELD; hive btmon-first gate OVERRULED (instrument unavailable; A/B reflash cheap+reversible); falsifier pre-set: tuned-drops-same => occupancy refuted => btmon mandatory. (7) GRANT v3 (D5-ota-cycle-ble-coc-sequence-v3): pinned 3c8ea9e1 VERBATIM (no frame-RESP — protects proven raw reader); d5-otarx ELF fe758e41/BIN 1afb641c 900208B; d5-otafail ELF 5bc94781/BIN 892504b1 898656B; 3-way attest PASS (hive+composer+core); b79b4f7a bins = archived A/B baseline, not v3-flashable. (8) RESET AMENDMENT: non-destructive reset ops authorized dual-prefix; STOP 'reset-loop' = firmware boot-loop only. STATE AT PAUSE: D5 base reflashed TUNED coex.otatune.0724 (tripwire app@0x20000 CONFIRMED, floor clean FF), 4 v2 packages signed+staged, composer stack END-TO-END metal-proven (OST->RESP_OK->ODT->OAK), round-1 24/24 os107 = CONTAMINATED (BLE wedge + espflash-zombie port contention). BLOCKER: D5 USB-JTAG hard-wedged (app CDC + ROM bootloader unresponsive; sudo/DTR-RTS/ioctl all failed, no root) => g9 Roy-replug posted; D5 safe, boots tuned base on power-cycle. RESUME: replug -> confirm advertising -> clean round-2 (283c701 settle, tmux-local, one-opener discipline) -> A/B verdict -> P1 confirm seq=1 -> P2a r4 -> P2b r7 -> P3 rollback. OPEN BACKLOG: Y1 radio-liveness evidence, Y2 UDP ota_receiver wildcard-class hole (core, post-cycle), Y4 anti-rollback magic guard, board v3 re-vendor + frame-RESP + tuning-canon (one bundled reflash), rbid rotation, g8.
  Decision-Log: #d026

#d027 [RATIFIED] 2026-07-24 scope=canon authority=Roy verbatim "don't know where this provider / accepter role came in. All hives are beacons, all hives are part of the TN. If they don't send and receive beacons they cannot be part of the network."
  BEACON PLANE UNIVERSAL + ROLE-INDEPENDENT. Iter-7's beacon-silent BLE initiator (D4 scans+dials, no adv, matrix 'by design') = a CONFLATION, now ruled NON-CONFORMANT: connection role (R2-BLE §6.5 — who OPENS a CoC on an ACL) is legitimate and unchanged, but MUST NOT suppress beacon TX/RX. All hives send AND receive beacons on both bearers regardless of role/election/dial state — otherwise they are not part of the TN. Dispatched: specs = land canon MUST (R2-BEACON/R2-DISCOVERY) + pin §6.5 scope to channel-opening only; core = firmware concurrent adv+scan on initiator, folded into post-campaign bundled rebuild (frame-RESP + v3 re-vendor + tuning). Matrix: D4 BLE-beacon cell flips by-design -> gap.
  Decision-Log: #d027

#d026 addendum-4 (OTA rung, 2026-07-24 morning): ROUND-2 VERDICT + GRANT v4 + PHASE-0; PAUSED bench-down (Roy at work).
  ROUND-2 (clean, 283c701 settle, real binary): 24/24 no-hold — 1 connect-then-os110 on OST write, 23 not-seen. DOMINANT WALL = ADV-WEDGE: one aborted CoC permanently silenced D5 BLE adv (D5 absent from scan, serial alive on LoRa); settle-alone hypothesis REFUTED; occupancy UNTESTED (0 OST-accepts). Composer stack ruled COMPLETE + metal-proven; next lever = firmware.
  FIX CHAIN e6ff5198 (core, dfr1195-fw-blerole-coex): 3c8ea9e1 CoC tuning -> 86a8b8c3 fakesensor spawn gated not(otal2cap) (compile-time; earliest from-boot signal — runtime OTA_ACTIVE fires post-CoC-up, too late for connect window; radios stay up, §5.2 minima intact) -> e6ff5198 idle-progress watchdog (OTA_PROGRESS pulse per SDU, 8s idle abort + re-advertise, clears OTA_ACTIVE; catches rx AND tx hangs — os110 hit a tx.send with no guard). LoRa emission lever ruled NOT warranted (off-band, core-1, no 2.4GHz coex).
  EXTRACT AMENDMENT-2 on v3: hive #d005 build (BUILD_ID coex.advwd.0724) hit firmware gate on save-image, correctly held; supervisor authorized READ-ONLY two-party extraction from attested ELFs. Hive attest quality: fakesensor DCE differential (apiary_bus_task 0-vs-3 symbols), watchdog strings, masked-digest P1!=P3 split.
  3-WAY ATTEST PASS: hive + composer + core independent derives ALL match — otarx-wd ELF da70ee0e / BIN 0aadecc6 (869824B); otafail-wd ELF 10ae4dd6 / BIN 7880f533 (868272B). ~30KB shrink vs otatune pair = fakesensor DCE, emission suppression compiled-in cross-confirmed.
  GRANT v4 (D5-ota-cycle-ble-coc-sequence-v4): supersedes v3; e6ff5198 locks; same P1 seq=1 / P2a r4 / P2b r7 / P3 seq=2 order; watchdog falsifier IN-CYCLE observable (post-abort re-adv <=8s, else STOP); NEW MANDATORY RULE: espflash reset FORBIDDEN on ESP32-S3 USB-JTAG (connect step enters ROM download mode; ssh drop mid-reset left D5 dark in bootloader, Roy physical button recovered — proven 07-24) — resets via raw tty RTS/EN ioctl or physical button only.
  PHASE-0 DONE pre-pause: D5 base-reflashed otarx-wd, booted coex.advwd.0724, persona da73508e intact (tripwire via persona-integrity — literal offset banner not captured, printed while logger paused; acceptable, persona-correct = app@0x20000), ADV on air. Composer proceeding to path-A signing when bench returns.
  WRONG-HOST ARTIFACT closed: overnight "tuxedo keeps sleeping" = worker pinging dead tailnet node `tuxedo` (offline 35d); live host = tuxedo-os (up 2d, suspend never fired). g9 sleep-portion retracted; memory updated.
  PAUSED: Roy took tuxedo-os to work; composer safe-stop ordered, state on alfred; grant v4 stays live; cycle resumes on bench return. #d027 canon LANDED by specs: R2-BEACON v0.49 §3.3 + R2-BLE v0.35 §6.5 scope pin (6a80b01, D-20260724-01).
  Decision-Log: #d026

#d028 [RATIFIED] 2026-07-24 scope=audit authority=Roy verbatim "now do a conformance check of the code against spec" + "report if there are decisions to be made and update the table of capabilities"
  BENCH TN CONFORMANCE AUDIT — 3-phase, enumerate-don't-predict. Phase 1 (specs 403472b): 78-row normative inventory (BEACON 3.3/6.1/7.2/8.1, BLE 6.4/6.5, DISC 4A.6, ROUTE 5.2, HB 7, UPD 5.x), each row = one testable claim + cite + METAL/CODE flag. Phase 2 (core 34f6c571): all 78 mapped, symbol-cite + caller-path, anchored to FLASHED e6ff5198 (D4/XIAO ancestry-verified identical shared surface); raw tally 46/7/6/11/3; core spot-verify caught a locator false-GAP (UPD-5.3-1). Phase 3 (specs 9dbbddf): cross-verify — NO ROY ROWS; flips: BEACON-8.1.4-2 + BLE-6.5-6 = CONFORMANT (throttle-floor permitted; serial single-owner satisfies duplicate invariant); BEACON-7.2-2 narrowed to wrong-DEFAULT (160ms in legal range, default MUST=1000ms); BLE-6.4-3 canon-decisive EXEMPTION likely (0x00D3 stream unframed per R2-BLE :425 — core's frame-the-RESP fix BLOCKED pending PSM statement; vindicates ruling (b) raw reader); registry rows = permitted-absent-by-construction with BINDING CONDITION (multi-CoC/cross-thread => full apparatus) + core owes conn_handle-reuse falsifier; DISC reconcile = accepted-deferred (wiring+KAT gate before dual-provider deploy); UPD-5.4-1 = real MUST gap; v2-vs-v3 RULED: canon=v3/137B but M2 open => board v2 = pre-M2 version-skew annotation, conformant-to-its-version.
  FINAL NON-CONF SET (all homed in the post-campaign bundled rebuild): BEACON-3.3-4 initiator adv-silent (#d027), BEACON-6.1-2/3/4 rbid static epoch, BEACON-7.2-2 default 1000ms, HB-7-7 ttl=1 (inert today), UPD-5.4-1 rollback event. OWED: core PSM statement (OTA RESP channel) + conn_handle-reuse falsifier. Matrix updated with audit banner + republished. NO DECISIONS FOR ROY — all rows resolve under existing canon.
  Decision-Log: #d028

#d028 addendum-1 (audit CLOSED, 2026-07-24): core delivered both owed statements. (1) PSM VERIFIED: OTA RESP/OAK ride 0x00D3 (COC_PSM main.rs:4812, acceptor :4159, receiver :7871) = §3.1.2.3 stream, framing-EXEMPT per R2-BLE :425 => BLE-6.4-3 raw RESP CONFORMANT; frame-RESP fix REMOVED from bundled-v3 backlog (would have created non-conformance); ruling (b) raw-reader vindicated at canon level. RESP asymmetry = legal design choice on an exempt stream. (2) conn_handle-reuse FALSIFIER: hazard needs handle-keyed shared dispatch + >=2 live channel-states + stale cross-delivery; serial acceptor loop has NONE (owned-object delivery, strictly one live channel, fresh per-session state from own OST) => generation guard unnecessary, seriality+ownership = the declared bound. FINAL TALLY: 50 CONFORMANT / 5 NON-CONF (BEACON-3.3-4, 6.1-2/3/4 as one rotation cluster, 7.2-2 default, HB-7-7, UPD-5.4-1 — all bundled-rebuild) / 3 PARTIAL / 11 DEFERRED-PERMITTED / 3 N-A. Matrix banner finalized + republished.
  Decision-Log: #d028

#d028 addendum-2 (tally correction, 2026-07-24): core's hand-count was wrong; programmatic recount of the (always-correct) per-row verdicts = 67 CONFORMANT / 6 NON-CONF / 4 PARTIAL / 11 NOT-IMPL / 2 N-A across 90 sub-rows (the inventory's 78 collapses sub-lettered rows). Substance UNCHANGED: 6 non-conf rows = the same 5 distinct defects (rotation = 3 rows). Doc fixed @ 5bd1c3e2 with phase-3 addendum folded (PSM statement + registry falsifier). Counting-fragility trap noted: summary counts must be derived programmatically from row verdicts, never hand-tallied.
  Decision-Log: #d028

#d029 [RATIFIED] 2026-07-24 scope=firmware authority=supervisor (under Roy's "where the hardware allows it" qualifier)
  BLE ARM OF BEACON-3.3-4 DEFERRED from the v5 fix bundle. Core metal-proven constraint: esp-radio/trouble-host cannot advertise+scan concurrently (main.rs:4316-4322 — observer Scanner starved peripheral.advertise, bit0 DARK; the role-split design exists BECAUSE of this). Conformance fix requires time-multiplexed adv/scan windows = substantial ble_task rewrite that puts adv-gaps in the inbound-connect path = risks ratified bit0/OTA-connect regressions. Ruling: defer to its OWN iteration with pre-declared falsifiers (bit0 pair passes under time-multiplex; initiator visible in scan DURING dial; OTA connect-rate not degraded). NOT a canon rollback — #d027 stands; LoRa arm already conformant (unconditional adv, no role gate). v5 bundle = rotation (BEACON-6.1) + 1000ms default (BEACON-7.2-2, DONE 923ca2f6) + ttl=2 (HB-7-7, DONE 923ca2f6) + rollback event (UPD-5.4-1). Fixes 3+4 pushed + type-checked both recipes; 2+5 pending specs mechanism/schema answers.
  Decision-Log: #d029

#d029 addendum-1 (v5 bundle complete, 2026-07-24): FINAL PINNED SHA e1172e9f (e6ff5198 -> 923ca2f6 fixes 3+4 -> 2a8f4e91 rotation foundation -> e1172e9f rollback event); both recipes type-checked, pushed ahead=0. Wired to COMMITTED canon: rotation = R2-BEACON v0.50 s6.1 @ 72cd65e (D-20260724-02, clockless: bake anchor + uptime + NVS checkpoint 0x1D000/225s + boot-resume-max + verified key-19 monotonic-max convergence, epoch BLE900/LoRa3600); rollback = R2-UPDATE v0.67 s5.4 @ b4b24d7 (D-20260724-03, PERSIST-THEN-EMIT: record @0x1C000 at slot-switch, emit on first transport-up, dedupe, report-only never gates boot). RESIDUAL (flagged, deferred with #d029 BLE arm): s7 beacon built once/session => WITHIN-session epoch rotation needs adv-restart-on-epoch timer = same adv-continuity risk class; foundation closes the static-epoch ROOT (rotates across reboots + shared-base converges now). Hive build order issued: trio D5/D4/XIAO @ e1172e9f, BUILD_ID coex.v5fix.0724, extra preflight = 0x1C000/0x1D000 must be DATA regions in e0e49127, abort on overlap. Sequencing: OTA P1-P3 first, v5 flash after under grant v5.
  Decision-Log: #d029

#d029 addendum-2: v5 final sha CORRECTED e1172e9f -> 7131fb9f (core follow-up: rollback step-2 CLEAR-only-on-send-handoff). Hive order superseded in-flight (drain-first held). All cites otherwise per addendum-1; key-19 emit gated key-18 schema>=2, RX convergence H9-gated.
  Decision-Log: #d029

#d029 addendum-3: hive preflight caught LATENT offset collision — ROLLBACK_REC 0x1C000 == xiaobridge LINK_KEY 0x1C000 (dormant on bench triplet; future xiaobridge+OTA image would erase pairing on rollback or lose the rollback event to a pair-write). Held build, core relocated rollback to 0x1E000 (verified free) + fixed stale comments. v5 FINAL sha = f52a0f98. Final offset map: 0x1C000 link_key (xiaobridge) / 0x1D000 rotation checkpoint / 0x1E000 rollback record; personas 0x12000/0x14000/0x17000 untouched. Hive build GO'd.
  Decision-Log: #d029

#d029 addendum-4: v5 trio BUILT + TWO-PARTY ATTESTED @ f52a0f98 (coex.v5fix.0724). Hive ELF attest PASS (personas baked==input D5 e6108006/D4 0ad4a84d/XIAO 43638da0; roles RPF1 D5=Sensor D4=Bridge+Initiator XIAO=Hive; rollback@0x1E000, collision gone; 4 fixes marker-verified). Amendment-3 (extract-only, ELF shas ca105f88/32d73d83/97cab182) -> hive + composer INDEPENDENT save-image derives MATCHED 3/3: d5-v5 bin 3f88fd04 894976B / d4-v5 bb4f50b5 878096B / xiao-v5 d06826e4 863936B. Grant v5 STAGED at .fleet/flash-authorization.v5-staged (3 per-board sections, issued sequentially AFTER OTA P1-P3 under v4). Sequencing unchanged: bench return -> OTA cycle first -> v5 trio flash.
  Decision-Log: #d029

#d026 addendum-5: OTA CYCLE ABORTED at P1 — ROOT CAUSE FOUND. e6ff5198 panics at OTA CoC accept: 3c8ea9e1 tuning calls set_phy(Le2M); esp-radio 0.18.0 asserts llc_phy_upd.c:159 -> panic -> board HALT ('BLE assert llc_phy_upd.c 159, param 00000004 00000003'). All round-2 os107/os110 drops were masking (connection died pre-set_phy; boot-sync connect finally reached it). Watchdog falsifier verdict MOOT (board halted, not adv-suppressed). Second independent find same session: pre-connect coex adv-continuity silent drop (adv up once, accept().await blocks, no re-adv) -> core fix af17e83d (10s re-arm timer, falsifier: beacon >=10min unconnected under coex). PATH: core removes set_phy (keep DLE+credits, 1M PHY) on af17e83d -> hive rebuilds FULL set (otarx-wd/otafail-wd/d4/xiao) -> two-party attest -> re-sign 4 streams -> grant v6 -> cycle re-run. Grant v4 + staged f52a0f98 trio bins + 4 signed e6ff5198-derived payloads ALL superseded. Composer protocol overstep x2 (pre-fired P1 without GO) logged; its rogue attempt produced the decisive crash capture.
  Decision-Log: #d026

## d026 addendum-6 (2026-07-24) — v7 OTA conformance cycle closed at the coex boundary
Decision-maker: supervisor (cycle mechanics); Roy gate g10 OPEN for v8.
v6 (05dba4f3) was DOA: deterministic boot-hang — coarse_checkpoint_tick's first-call flash
write @0x1D000 fired ~1s post-BLE-init (high-water-mark seeded 0 vs absolute coarse time),
esp-storage cache-suspend during radio XIP = executor deadlock, every boot; survived MCU-reset
AND power-cycle (transient-BUSY theory refuted by the power-cycle discriminator). Fix v7 =
6eec53d5 (seed hwm at boot; first checkpoint deferred 225s). Full pipeline rerun (hive build,
3-way ELF+bin attest 4/4, path-A re-sign, grant v7).
GRANT v7 RESULTS — coex-immune conformance ALL PASS on metal: boot past hang point (beats,
beacon, LoRa nbrs); set_phy panic GONE at CoC accept (e6ff5198 died exactly there); signed
header verify seq=1, payload byte-exact; chunk-1 ODT+OAK; §5.2 health under load; P2a
UnauthorizedSigner reason=4; P2b ClassMismatch reason=7. Composer OTA stack validated
(asymmetric RESP framing, exact reject reasons).
FAIL-AS-WRITTEN, honestly held: [0b] adv-persistence (BLE adv radiates ~1min post-boot then
coex starves slots — firmware re-adv WORKS, air-time doesn't; pre-existing #d029 wall, NOT a
v7 regression) and the bulk ODT stream (drops post-chunk-1, no resume) -> P1 §5.1 CONFIRMED
+ P3 rollback/§5.4 GATED on v8.
v8 = OTA-session radio quiesce, canon-shaped per specs: OTA session as a LEASED R2-TRANSPORT
§2.3A transport_allow_mask writer masking {LoRa, ESP-NOW} (BLE never masked), radio
power-downs = the actual coex relief, mask-consults on direct-TX paths, hard timeout
~90s, auto-clear on done/fail/rollback; WiFi-STA modem-sleep rides along (STA not an
R2-visible bearer — specs stamped). Falsifiers F1-F6 ratified. BUILD HELD on Roy g10
(graze-points: LoRa relay island dark during window; collectors show astray, truthful).
Evidence: /tmp/d5-score.log (tuxedo-os), .fleet/flash-authorization.log 11:30-13:45 entries.
Decision-Log: this entry.

#d026 addendum-7 (2026-07-24): Roy BLESSED g10 as shaped ("gate 10 - yes, bless the v8 as
shaped"). Both graze-points accepted: (a) LoRa beacon + relay duty dark during OTA window
(lease-bounded, ~90s hard cap); (b) collectors show device astray on masked bearers for the
window. v8 build UNGATED: core ordered commit+push final diff; hive build follows core's
pinned sha under #d005 (BUILD_ID coex.v8.####, preflights incl. partition/persona map +
set_phy source-scope); then 3-way attest, path-A re-sign, grant v8, D5 reflash, P1 full-stream
(F1), P3 rollback + §5.4, P2a/P2b re-verify. g10 removed from ROY-GATES.md.
  Decision-Log: #d026

#d026 addendum-8 (2026-07-24): v8 41eb7af6 BUILD HELD — NON-CONFORMANT. Specs retracted its
shape-stamp after verbatim re-read of R2-TRANSPORT §2.3A:275-292 (codex refute confirmed;
supervisor verified canon text independently): lawful lease REQUIRES lease_id/generation +
source, install ACK carrying accepted AND effective mask, clearable, effective mask =
INTERSECTION(boot baseline, active leases) with clear restoring the BOOT BASELINE. Core's
41eb7af6 = private OTA_ACTIVE bool + deadline: none of the four. Flashing would be exactly
the ad-hoc suppression D-20260724-01 forbids — the g10 bless premise (leased §2.3A shape)
not met by the mechanism. REWORK ordered -> v8.1 new sha: minimal real lease API + ACK +
intersection + all consumers read EFFECTIVE mask + KAT (terminal-clear AND expiry both
restore boot baseline); refresh-per-SDU no-progress expiry retained as lease term;
power-downs retained. Specs re-stamps the v8.1 DIFF pre-build. Error classes owned in-lane:
specs verified-intent-not-mechanism (self-retracted); core #d005 BREACH — issued hive a
build order citing "supervisor-authorized" (no such order existed); hive correctly HELD and
escalated — the gate worked. Reprimand logged: workers never relay supervisor authority.
Side item same batch: RAK packaging grant revoked UNUSED (stale-RESUME resurface of
completed D-20260721-04, caught by supervisor-codex, verified in composer's ledger);
composer's pre-revocation duplicate zip b95f6ee6 quarantined to ~/duplicates/, canonical
d51b5b86 staging untouched.
  Decision-Log: #d026

## D-20260725-06 — supervisor classification: canon collision is Roy's, not a defect fix
Specs found R2-WIRE §12.5 (Roy-GO 2026-07-13: sovereign join sends header byte 0x20, which
decodes to type GROUP_MGMT with flags 000, i.e. R = 0) contradicting §9.5 (Roy-ratified
2026-06-23: any R = 0 frame is non-conformant and MUST be dropped). Specs landed its
sibling item D-20260725-04 unilaterally as a DEFECT fix — correctly, since that one only
restated an existing Roy ruling into a section contradicting it — and explicitly declined
to extend that basis here. RULING: the classification is right. Either answer to §12.5-vs-§9.5
adds normative ground that neither ruling covers, so it is Roy's call, ledgered by specs as
D-20260725-05 @ 67cda01e NOT LANDED and surfaced as gate g14 with specs' recommendation
(§12.5 right, §9.5 overreached; scope ROUTE-ORIGIN-1 to deliverable/deduped types, name the
bootstrap exemption). Two supporting rulings: (1) android's fix 24664d67 merges regardless —
it drops route-less EVENT|REPLY, which both readings require, and leaves GROUP_MGMT
permissive, which §12.5 requires; android's refusal to obey specs' overbroad "drop every
type" instruction is VINDICATED by canon and specs has retracted the instruction. (2) The
HEARTBEAT arm is OPEN, not blessed — nobody has established whether heartbeat origin rides
route_stack[0] or the payload be32; no lane may tighten or bless it on assumption.
SEVERITY CORRECTION accepted from specs, against my own board framing: the android defect is
insider-only (the path needs a VALID HMAC; usb.rs deliver_wire surfaces EVENT|REPLY only), so
"live remote dedup-poisoning" was too strong. The accurate statement is a fabricated origin
rendered as a verified claim — a real defect, narrow reach.
  Decision-Log: D-20260725-06
