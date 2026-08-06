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

## D-20260807-140 — THE TOKEN METER READ ZERO ON EVERY CODEX LANE, AND ZERO IS ALSO ITS WORD FOR "UNKNOWN"

- **Decision-maker:** Roy (directive: review the fleet for token-usage optimisation and
  for proper conjecture/refutation), claude-fleet lane (mechanism)
- **Authority basis:** Roy's direct instruction, 2026-08-07

`fleet_ctx_tokens` (`lib/registry.sh`) read only Claude's field names —
`cache_read_input_tokens` + `cache_creation_input_tokens`. Codex rollouts record
`last_token_usage.input_tokens` and `total_token_usage.*`. Neither Claude name appears in
a codex transcript, so the function returned **0 for every codex lane in the fleet**, and
0 is also its legitimate answer for "cannot read". **A blind meter does not report that it
is blind; it reports a small number, and every consumer believed it.**

**Measured on a real rollout** (`~/.codex/sessions/2026/07/21/rollout-…019f81fb…`):

```
"last_token_usage":{"input_tokens":79676,...}
"total_token_usage":{"input_tokens":32501144,...,"total_tokens":32601334}
```

The lane had re-processed 79,676 tokens on its last turn and 32.6M cumulatively. The
instrument said 0.

**Three layers failed together, and each hid the next:**

1. `fleet tokens` reported 0 for every codex lane — half the fleet, invisible.
2. The `on-stop` compaction size trigger never fired for those lanes. They never compacted.
3. The documented backstop that would have caught it — `FLEET_COMPACT_EVERY=40` in the
   comment three lines above — was **`:-0` in the code**. Disabled. And
   `tests/faculty.sh` asserted only that the *string* `FLEET_COMPACT_EVERY` appeared in
   the file, so it stayed **green the whole time**.

**This is D-112's class recurring in the token instrument** — *"the instrument matched its
own scaffolding"*. The sweep that followed D-112 did not reach the meters.

**Fix:** a codex arm scoped to the LAST `last_token_usage` object (grepping the bare
`input_tokens` key would match `total_token_usage`'s cumulative 32.6M and trip every
threshold on turn one); backstop default corrected to 40; the backstop now fires **only
when the meter reads unknown**, never as a second unconditional schedule — a compaction
destroys the cached prefix, so a turn-timer that fires at 5% of the ceiling is a pure
loss; and a `ctx-unknown` log line so a blind meter is findable instead of being silently
absorbed by the backstop.

**Evidence — controls fired before the fix and passed after** (`tests/faculty.sh` 4c/4c-bis,
real transcript fixtures per provider):

```
FAIL on-stop turn backstop defaults to disabled
FAIL turn backstop not gated on unreadable ctx
FAIL codex ctx = last_token_usage.input_tokens (got '0' want '79676')
ok   claude ctx = cache_read + cache_creation          <- unchanged, no regression
ok   negative control: a transcript with no usage reads 0
```

The negative control is load-bearing: without it, two green readings prove only that the
function returns *some* number.

**Decision-Log: this entry.**

## D-20260807-141 — 70% WAS NOT HOLDING, AND THE VALUE WAS NEVER THE PROBLEM — REACHABILITY WAS

- **Decision-maker:** Roy (directive), claude-fleet lane (mechanism)
- **Authority basis:** Roy's direct instruction, 2026-08-07

**Measured on the r2-hive lane's own transcript, 29,364 turns:**

```
context floor (fixed preamble)      23,082 tok
mean context re-processed / turn   406,780 tok
median                             397,234 tok
p90                                692,191 tok
max                                999,801 tok      <- reached the 1M ceiling
TOTAL input re-processed        11.94 BILLION tok   <- one lane
compactions                             46          (one per 638 turns)
```

**9.0% of turns ran above the 70% trigger and 1.0% above 90%.** The trigger was set to 70%
throughout. **It was not holding — and not because 70 is the wrong number.** The routine
trigger requires MANAGED **and idle with an empty inbox**. A worker kept busy by a steady
stream of peer mail never meets that condition, and grows until the provider auto-compacts
at ~95%: the most expensive compaction available, at maximum context, unplanned, mid-task.

**Fix:** `FLEET_COMPACT_HARD_PCT=85`, the only compaction that runs while mail is waiting.
It runs **BEFORE the inbox drain and skips the drain when it fires.** That ordering is the
whole safety argument: draining injects text into the pane, and `/compact` keystroked onto
a half-submitted message corrupts it. Mail stays queued — an already-supported state with
its own defer path — and lands next turn against a fresh context.

**A cost model was built and then REJECTED as a basis for changing the 70.** With F=23,082
and g≈1,061 tok/turn, `cost/turn = 0.1·(T+F)/2 + (T+1.25F)·g/(T−F)` falls monotonically
toward the floor (700k→400k = 0.60x, →200k = 0.34x). **The model omits the re-derivation
cost** — a compaction destroys working context and the agent then re-reads files, re-derives
state, re-asks peers. That term is unmeasured, so the interior optimum is an artefact of
what was left out. **The number stays at 70 until someone measures the other side.** What
the model does establish: 70 was never derived either.

**Decision-Log: this entry.**

## D-20260807-142 — TOOL OUTPUT NOW SPILLS INSTEAD OF TRUNCATING, BECAUSE HEAD+TAIL ALONE HID A DECISIVE LINE IN 10.6% OF REAL CASES

- **Decision-maker:** Roy (directive: be inspired by Headroom, then run the head+tail
  attack), claude-fleet lane (mechanism)
- **Authority basis:** Roy's direct instruction, 2026-08-07

Prompted by Headroom (Tejas Chopra, Netflix; Apache-2.0; claimed 60–95%, demo 88%).
**The headline does not transfer and was not adopted.** Headroom wins where *"tool output
dominates the context window"*. Measured on the r2-hive lane's LIVE context window (every
record since its last compaction, so no inference about what is in context):

```
tool_use 32.8% | text 31.5% + 6.9% | thinking 18.2% | tool_result 10.7%
```

88% off 10.7% is ~9% of the window. **The mechanism transfers; the magnitude does not.**

A rival conjecture — *"the fixed preamble dominates"* — was **refuted by measurement**: the
floor is 23,082 tokens, not the ~217k predicted. The gap that suggested it was
compaction-summary text inside the window being measured against.

**What was built:** `hooks/output-budget.sh`, a PostToolUse hook using `updatedToolOutput`
(a native Claude Code contract — no proxy, no model, no dependency). **Spill, not
truncate:** the full output is written to `.fleet/spill/`, head and tail stay verbatim
inline, and the elision states exactly how many bytes and lines moved and where to read
them. Information is deferred, never lost. Fails open on every error — a hook that eats a
tool result is worse than a hook that saves nothing.

**THEN THE ATTACK, AND IT LANDED.** 161 real over-budget results from a live transcript
replayed through the elision: **17 of 161 (10.6%) had a decisive line — an error, a
failure, a verdict — existing ONLY in the elided middle**, with nothing in either end to
hint at it. Two classes accounted for all of them, and both are line-oriented output where
every line is its own record and there is no verdict at the bottom:

```
fleet inbox   7/27    each peer message is its own finding
grep results  8/68    the match you wanted is at whatever line it is at
```

**A token win bought with a lost finding is the defect class this repo keeps killing**, and
`tools/comms-fitness.py` would reject it: capability is a gate, not a term.

**Repair:** carry the flagged middle lines inline (up to `FLEET_OUTPUT_HL_MAX=12`, 200
cols), announcing the remainder when the cap bites — no silent caps. Re-measured on the
same 161: **10.6% → 0.0% hidden, at a cost of 3 percentage points of saving (53% → 50%).**

`tests/output-budget.sh` asserts both halves — smaller AND lossless — including that the
spill is **byte-identical** to the original, plus three controls that must fire: no rewrite
outside a `.fleet` workspace, pass-through-whole when the spill cannot be written, and the
attack itself (`FLEET_OUTPUT_HL_MAX=0` reproduces the pre-repair algorithm and turns the
attack assertions red).

**Not wired for codex:** `updatedToolOutput` is a Claude Code hook contract with no
verified codex equivalent. Asserted as a test, so the omission is deliberate rather than
forgotten.

**Also:** `tests/faculty.sh` and `tests/output-budget.sh` are now in CI. 103 assertions —
including the per-provider meter above — ran only when someone remembered to. **A suite
nobody runs is documentation, not a gate.**

**Decision-Log: this entry.**
