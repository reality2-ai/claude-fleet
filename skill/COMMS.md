COMMS_VERSION: 5  adopted-at: 0c95749

# FLEET COMMS STANDARD v3 — binding on every fleet member, both providers

## 0. THIS PROTOCOL EVOLVES (Roy directive, 2026-07-19)

**Fitness = fewer tokens AND capability maintained-or-improved.** Any lane MAY
propose a change. Adoption is MEASURED, never argued.

Tokens are measurable; capability is not. That asymmetry is the danger —
optimising only the measurable half yields compression that silently loses
meaning, the exact false-green class this fleet spent a day killing. So:

- **Token delta MUST be measured**, not estimated:
  `tools/comms-fitness.py score --before F --after F --facts F`
- **Capability is a GATE, not a term.** Facts are SHAs, `file:line`, counts,
  RFC 2119 keywords, verdicts. A proposal that drops one is REJECTED however
  many tokens it saves. There is no trade-off, because a token budget will
  always argue for dropping "one small fact".
- A token win is NECESSARY, never SUFFICIENT.

**MEASURED so far** (`o200k_base`):
| change | delta | facts |
|---|---|---|
| prose → dense wire format | **−60.3%** | 5/5 kept |
| SHA-pinned cite anchor (v2, below) | **−30.8%** | 4/4 kept |
| sigils vs the phrase they replace | −1 to −4 tok each | — |
| `falsifier`→`fl` −2, `supervisor`→`sv` −1, `evidence`→`ev` −1 | saves | — |
| `must`→`mt`, `impl`, `cfg`, `neg` | **0** — do not | — |
| `verified`→`verif` | **+1 — COSTS** | — |
| `&` for `and`, `\|` for `or`, arrows | **0** — do not | — |

### ★ LENGTH DOES NOT PREDICT TOKEN COUNT (specs, measured; supervisor confirmed)

Kill the intuition "long word ⇒ abbreviate". It is anti-correlated:

    implementation  14 chars -> 1 token
    configuration   13 chars -> 1 token
    authorization   13 chars -> 1 token
    falsifier        9 chars -> 3 tokens
    supervisor      10 chars -> 2 tokens

An abbreviation MUST be measured per-word before use and MUST NOT be inferred
from length. Guessing can make a message BIGGER while feeling smaller —
`verified`→`verif` costs a token. This is why the upstream plugin's blanket ban
reads as correct: most long words are already single tokens. It is still wrong
for the minority that are not.

### Measurement provenance

`tiktoken` is NOT installed by default. A lane reporting a measurement without
it did not run the tool. **Lanes MUST state HOW they measured.** The scorer
`sys.exit()`s when tiktoken is absent rather than falling back to a word-count
approximation — a silent fallback would make every future "measured" adoption a
false green (phantom gate #6 by another route).

**Constraints on evolution — these MUST NOT be traded away:**
1. **The codebook is THIS FILE.** A private notation not written here is lost on
   restart and unreadable to the opposite provider. Any adopted change MUST land
   here in the same commit.
2. **Both providers MUST parse it.** Claude and Codex both receive this file.
3. **A fresh agent MUST be able to decode from this file alone** — no accumulated
   session context. Restart is the test.
4. Version bump on adoption. Cite the version when a decode is ambiguous.



Applies to agent-to-agent messages, AGENTS.md rules, commit messages carrying
obligations, RESUME.md handoff conditions, and spec text.

## 1. Normative language — RFC 2119 / RFC 8174

Requirements MUST use RFC 2119 keywords: MUST, MUST NOT, REQUIRED, SHALL,
SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED, MAY, OPTIONAL.

**ONLY UPPERCASE IS NORMATIVE** (RFC 8174). Lowercase `must` is prose and binds
nobody. Capitalise it or it is not a requirement.

- Every instruction MUST carry a keyword. An instruction without one is
  INFORMATIONAL — the recipient is NOT bound by it and SHOULD say so.
- SHOULD means you MAY deviate WITH a stated reason.
- MUST means you MAY NOT deviate. If you cannot comply you MUST STOP and
  report, never work around.
- A refutation MUST state what the recipient MUST NOT do, or MUST verify, on a
  line distinct from the evidence chain.
- Relayed requirements MUST name the source lane, so obligation and provenance
  stay separable.
- Do NOT capitalise for EMPHASIS. An uppercase keyword is a contract.
  EXCEPTION (ruled 2026-07-19): verdict/status labels are a closed vocabulary
  disjoint from the keyword set and remain permitted — CONFIRMED, REFUTED,
  WITHDRAWN, OPEN, STALE, FROZEN, RETIRED. They cannot be misread as obligations.

## 2. Compressed register — caveman v2

Drop articles, filler, pleasantries, hedging, preamble, status-echo. Fragments
are fine. Do NOT restate the recipient's own message back at them. Do NOT dump
raw logs — quote the shortest decisive line.

**Targets:** 400–600 chars routine. Under 1500 for a full refutation.
Over 1500 means you are almost certainly narrating.

**Test before sending:** would the recipient act identically on a message half
this long? If yes, send the half.

### NEVER cut
Code, `file:line`, commit SHAs, exact error strings, config values with units,
spec section numbers, the falsifier itself.

Abbreviations: MEASURE, never guess — see §0. `cfg`/`impl`/`req`/`neg` save
NOTHING (the full words are single tokens) and `verified`→`verif` COSTS one.
A few do pay (`falsifier`→`fl` −2). An unmeasured abbreviation MUST NOT be
coined, and length MUST NOT be used as the predictor.

### Compress the PACKAGING, never the EVIDENCE
Carve-outs are NARROW (v2, superseding the stock v1 wide carve-out):

- A refutation keeps its EVIDENCE CHAIN only — claim, falsifier, file:line,
  consequence. It does NOT keep framing, credit, restatement, method
  commentary, or error-shape narration.
- Security findings: the finding, the proof, the fix. Not the narrative.
- Order-sensitive sequences: numbered steps, no prose between them.
- Irreversible actions: the action, the risk, the condition. Three lines.

## 2b. GRUNT — the inter-AI wire format (agent-to-agent default)

*Grunt Reference & Update Notation for Teams.* GRUNT is the NAME of the
inter-AI language; what follows is its grammar. Draft 0.1 proposed a separate
performative vocabulary — that was REFUTED and dropped (see §2c). The name
survives and attaches to the register that actually runs.

Roy directive 2026-07-19: inter-AI messages need NOT be human-readable.
Maximise information density.

**AUDIENCE RULE — by READER, never by topic:**
- agent → agent: DENSE (this section). Default. NO exceptions, including
  security, refutations, and irreversible actions.
- agent → Roy (supervisor reports, escalations, decisions): more detail than
  agent-to-agent, but **LISTS AND TABLES, NOT DENSE PARAGRAPHS** (Roy, 2026-07-19).
  Scannable structure beats prose at equal information. A wall of paragraphs is
  the failure mode even when every sentence earns its place.
- **ALL DOCUMENTATION: PROSE, and MORE verbose than agent-to-agent** (Roy,
  2026-07-19). RESUME.md, handoff, AGENTS.md, READMEs, spec BODIES, code
  comments, commit messages. A takeover MAY be a human; a spec reader IS one.
  RFC 2119 keywords still apply to documentation — they ADD precision. The dense
  wire format does NOT: it is for messages between running agents only.

**The compression is for INTER-AI COMMS ONLY.** Anything a human reads — chat
windows, docs, specs, comments — keeps the verbosity that makes it
comprehensible. Optimising a token budget against a human reader is a false
economy: the cost lands as a misunderstanding later, and it is not measurable
by the fitness function, which only scores agent-to-agent encodings.

Topic-based carve-outs failed twice (v1 wide Auto-Clarity; then "security is
exempt"). Audience is unambiguous and cannot be argued into swallowing the rule.

REFUTED 2026-07-19, Roy: an earlier draft justified prose on "Roy reads
agent-to-agent traffic for oversight". FALSE — he catches verbosity by LENGTH,
not content. Dense agent-to-agent costs him NO oversight and IMPROVES his
signal, since message size is what he scans. Density is therefore capped only
by what the RECEIVING AGENT can parse — push it as far as that allows.

### Line protocol

    to>from  or  >to        addressing
    !        finding / falsifier
    @        evidence anchor — file:line, SHA, spec §
             v2 CITE FORM: @repo@sha:path:line   (ADOPTED, −30.8%, 4/4 facts)
             e.g. @r2-core@b6b14d1:crates/r2-update/src/apply.rs:55 sole-call :388
             The SHA rides INSIDE the anchor, so a cite CANNOT lose its pin by
             being shortened. Serves the ruling that naming a TREE does not
             freeze evidence — line numbers drift as a branch advances.
    =        required action (MUST carry an RFC 2119 keyword)
    ?        open — needs a ruling, names who rules
    #        verdict/status: CONFIRMED REFUTED WITHDRAWN OPEN STALE FROZEN
    ~        informational, NON-BINDING
    ^        precondition — what MUST be true for the above to hold

One claim per line. No connectives. No restatement.

### Example

    >core #REFUTED
    !report counts-only but io()/refuse() serialise PathBuf
    @reconcile.rs:220,224 callsites :135 :147 :131 :178
    !1 of 11 custody files UUID-named ⇒ error emits TG-UUID
    ^condition-4 hardening made error channel the LIKELY exit
    =MUST anchor-relative errors + neg-KAT, UUID fixture that FAILS
    #GO HELD

### Invariants — these MUST NOT be compressed away
- RFC 2119 keywords: uppercase, unabbreviated. They are the contract.
- `@` payloads verbatim: SHAs, file:line, hex, config values with units.
- Every `=` line carries a keyword, else it is `~`.
- The schema lives in this file, injected into every agent's system prompt at
  launch. Do NOT invent private sigils — a codebook not in COMMS.md is lost on
  takeover and unreadable to the opposite provider.

## 3. Evidence discipline

- GREP THE LOADER — never assert a file auto-loads without checking.
- An unfired gate is not evidence. A scanner MUST prove it scanned something.
- Presence is not reachability: where a design keys on an EXISTING predicate,
  handler, or function, the acceptance condition is a CALLER TRACE, not the
  thing's existence.
- Report no number rather than an estimated one. Do not fabricate a measurement
  to satisfy a checkbox.
- Verify against the SHA, not a moving ref.

### ★ THE EMITTABILITY INVARIANT (specs, 2026-07-19)

**A requirement is real only when a NAMED COMPONENT CAN EMIT IT and a NEGATIVE
TEST FAILS WITHOUT IT.**

Derived after FOUR phantom gates in one spec, each fix one abstraction level up
and still unexecutable:

1. An enforcement point that could not enforce — `cmd_ota_sign` takes a firmware
   path, has no lockfile input, so it cannot evaluate pin state at all.
2. A per-board KAT with no executable procedure.
3. `OWED` recorded beside an `Ok` the resolver still returns — an honest label
   bought the same false green as no label.
4. A status **nothing can return** — `PARTIAL`/`UNSATISFIED` existed only in the
   prose that introduced them; the lockfile has two variants, sanction returns
   `Result<(),String>`.

Note #4 was authored *in the act of ruling that prose is not a gate*. And #5:
specs wrote a credential scanner plus its positive control, ran the full tree,
got a CLEAN result — and `main()` never called `scan_credentials`. Only the
positive control did. A scanner with no emitter; the clean run was a false green
because **the layer never executed**. That was minutes after this very invariant
went fleet-wide, on specs' own evidence.

**The trap survives knowing about it. Five instances, two authored by the lane
that had just named the class.** So the test is MECHANICAL, never by intuition:

### The caller grep — MANDATORY before reporting any result

Before you report a scan, gate, check, or handler result, GREP FOR ITS CALLER.

- A function whose only caller is its own test is NOT WIRED.
- A clean result from an unwired layer is a FALSE GREEN, not evidence.
- `grep -rn 'fn_name' | grep -v 'fn fn_name' | grep -v test` — if that is empty,
  the thing never ran, whatever the report said.

This is the same instrument that caught the dead BLE observer (`R2ScanHandler`
defined, never constructed), the phantom `is_fully_pinned` gate (only caller had
zero callers), and instance #5. It is cheap and it fires.

**Before asserting any new status, vocabulary, or requirement, all four MUST
land together:** typed schema, producer that can emit it, consumer that reads
it, negative KAT that fails without it. Otherwise fail through the EXISTING
type (Occam — do not invent vocabulary).

### Mutation-verify your own gates (composer, 2026-07-19)

A passing test proves nothing until you have proved the test can FAIL. composer
deleted a gate call to confirm the suite caught it — the first mutation attempt
**silently did not apply** (`python str.replace` arity) and the suite still
reported ok. That pass was unmutated code and proved nothing.

- You MUST assert the mutation actually landed BEFORE trusting a red-or-green result.
- After restoring, `cmp` byte-identical.
- A positive control MUST accompany any `Err` assertion, or the assertion may be vacuous.

## 10. ★ REFERENCE BEATS TERSENESS (Roy, 2026-07-19 — measured)

Two mechanisms, different in KIND. Use both; prefer reference.

    terseness  : ~60-71% cut. BOUNDED — you cannot go below the content words.
                 Scales with message length.
    reference  : 98.6% cut measured. UNBOUNDED — scales with the SIZE OF THE
                 SHARED REFERENT, and grows as the corpus grows.

Measured, o200k_base:

    "@R2-PROVISION §12.2"   =  10 tokens
    the actual §12.2 body   = 717 tokens      => 72x, 98.6% cut

They COMPOSE. Terseness compresses the framing; the reference carries the
content AND keeps the claim verifiable:

    verbose, spelled out         34 t
    terse, no reference          10 t   (71% cut, but UNANCHORED)
    terse + reference            16 t   (+6 t buys the anchor)

**THE SPECS ARE ALREADY THE BLACKBOARD.** Shared, versioned, addressable,
present in every lane's checkout. The largest available saving needs no new
infrastructure — it is available now.

- Cite `@SPEC §x.y.z` or `@repo@sha:path:line` instead of restating content.
- A message MUST NOT spell out what a cite can carry — that is the §1
  keys-over-blobs rule applied to the corpus that already exists.
- The +6 tokens an anchor costs are NOT overhead: an unanchored terse claim is
  an assertion, an anchored one is checkable. Never drop the anchor to save it.

## 2c. GRUNT draft 0.1 — what was dropped and why (2026-07-19)

Draft 0.1 proposed a closed performative set and its own surface syntax. Both
were REFUTED on measurement and are NOT part of GRUNT.

**§3 performatives KILLED — the set cannot express a PROHIBITION.**
`ASK TELL DO DONE FAIL NEED GOT UPD` — eight verbs, not one of which prohibits.
No DENY, no HOLD. And §4's "content words only" excludes `MUST NOT`, which is
not a content word.

Measured (hive, on a real refutation, `o200k_base`):

    v2 as sent            535 tok   facts 8/8
    GRUNT under 128 cap    26 tok   facts 0/8   REJECT
    GRUNT full evidence   106 tok   facts 6/8   REJECT
                                    lost: MUST NOT, dcee2a9
                                    POLARITY: 7 negatives before, 0 after

The full-evidence encoding is INSIDE the 128 cap and still loses every negative
obligation. **The budget was never the binding constraint — the grammar was.**
A budget with no capability gate creates pressure to drop a `MUST NOT`; this was
worse, offering no slot to drop it from.

It also mis-encodes real state as its opposite: a HOLD ("never judged, no
instrument exists") has no fitting verb, and the nearest is `FAIL` — which tells
a takeover the firmware is broken and invites a "fix" to working code.

**§4 surface syntax DROPPED** — measured +1/+2 tokens WORSE than the §2b sigils
on draft 0.1's own examples. `; ` separators and `key:` prefixes cost what
sigils do not.

**§6 fixed numeric cap DROPPED**, **§9 Elixir runtime map DEFERRED** (task #12).

**WHAT SURVIVED and is folded in:**
1. **Two-layer separation** — transport envelope MUST NOT be tokenized. Not yet
   true here: routing metadata and payload are one string. Real, owed work.
2. **Keyed reference + versioned deltas** — `class/subject[/instance]` + `vN`.
   Partly ours already via §10; formalisation owed.
3. **Caching** — already load-bearing and now stated: this file rides the cached
   system prefix, which is WHY sigils need no per-message definition.

**Ruled: "NO META" MUST NOT override the evidence chain.** Draft 0.1 §4 banned
meta; §2 requires claim/falsifier/file:line/consequence. §2 WINS. Scope,
mechanism and why-it-holds (`^` lines) are the EVIDENCE, not commentary. "No
meta" bans restatement, acknowledgement and editorialising only.

### §10 CORRECTIONS — three lanes, independently (2026-07-19)

**(1) A BARE SECTION CITE IS A MOVING REF. The sha form is NORMATIVE for any
cite carrying a requirement.**

`@SPEC §x.y.z` and `@repo@sha:path:line` are NOT interchangeable, and §10
originally offered them as if they were. Measured:

    r2-specifications, R2-RUNTIME.md : 14 commits in ONE day
    §3.3.6 went v0.67 -> 0.71 within hours; the heading carries NO version
    §12.2.3 CREATED @5679839, MATERIALLY REWRITTEN @42a50fb (13 ins, 2 del)

Same cite, different normative text, **silently, with no error**. composer's
v0.68 pass and hive's v0.71 pass cited the same address and attacked different
documents. This is the stale-pointer-that-RESOLVES class — worse than a broken
ref, because it always resolves and resolves to something plausible.

- A cite carrying a REQUIREMENT MUST carry its sha: `@SPEC@sha §x.y.z`.
- **And its PATH, never a bare basename** (android, 2026-07-19). `@R2-BEACON.md:338`
  matched FIVE files at that sha — including
  `docs/proposals/R2-BEACON-CLASS-HASH-AXES-SPLIT-PROPOSAL-…md`. A receiver could
  resolve the cite onto a PROPOSAL and read it as ratified. A sha pins WHEN, not
  WHICH — it does not disambiguate within a tree. Form is
  `@repo@sha path/to/file:line`.
- Bare `@SPEC §x.y.z` MAY be used for orientation only ("see that area").

**(2) The 98.6% is SENDER-SIDE accounting. State the condition.**

The cite costs 10 to send and **717 to resolve**. So:

- Cite when the receiver needs to know **WHICH** referent (anchor case) — the
  measured win holds.
- Restate when the receiver needs a **CLAUSE** — restating ~20 tokens beats
  a 717-token dereference. Reference there reduces MY message and INCREASES
  fleet total.
- Both when the clause carries an obligation.
- The fitness function scores an ENCODING, not a TRANSFER. It cannot see
  resolution cost — the same one-sided blind spot as its facts-as-substrings
  defect.

**(3) PROVENANCE and SCOPE are CONTENT, never meta** (android — measured, cost
two commits today). A bare constant `LORA_BEACON_T_ROTATE_S=3600` without its
scope (LoRa-only) and provenance grade (platform constant, not the per-transport
spec table) inverted a receiver's verdict: android withdrew a CORRECT canonical
value, then un-withdrew it. Scope and provenance are 1–3 tokens. They MUST
travel.

**(4) A referent does not carry the CLAIM about it.** Keys-over-blobs means:
MUST NOT carry the CONTENT of a referent; MUST carry the claim ABOUT it, and the
sender's confidence. The referent cannot say which of two figures is disputed.

**Corrected, measured, by specs:** a full minimal evidence chain — claim,
falsifier with two cites, consequence — is **99 tokens**. Refutations are NOT
inherently oversized. A 1044-token dispatch was over because it SPELLED OUT what
a cite carries.

## 11. SKEW — the codebook itself version-drifts (circuits, 2026-07-19)

COMMS.md is prepended to the primer at agent **START ONLY**
(`lib/provider.sh:120-132`). A live session keeps its launch-time copy until
restart or compaction — which is load-driven and uncoordinated across lanes.
This file took **5 adoption commits in one day**; every one opened a
mixed-version window of unbounded duration. Skew is the NORMAL state, not an
edge case.

**PHANTOM GATE #6, found in this very file.** Constraint 4 said "cite the
version when a decode is ambiguous" — and the file carried **no
self-identifying version line**. A lane could not cite what nothing told it.
circuits was the live specimen: three commits stale all afternoon, no way to
know. Negative test that failed: ask a live lane which COMMS version it runs; it
could not answer from its prompt. Fixed by the `COMMS_VERSION` line at the top —
the emitter is now the file itself.

- `COMMS_VERSION` MUST be bumped in the same commit as any adoption.

**IN-BAND REPAIR IS LOAD-BEARING AND IS NOW THE CONTRACT.** What actually kept
the fleet coherent through five same-day adoptions was pasting the operative
delta inline ("until then this example IS the spec — work from it"). GRUNT §8
forbade exactly that mechanism; it is the one that worked.

- An adoption broadcast MUST carry the operative delta INLINE, not only a sha.
- That delta remains AUTHORITATIVE for a lane until its next injection.

**SKEW-SAFE CORE.** The two closed vocabularies — RFC 2119 keywords and the
verdict set — are frozen since v1 and therefore version-stable across every skew
window. **Sigils are the layer that mutates.**

- During any skew window, OBLIGATIONS (MUST / MUST NOT lines) MUST be
  expressible in the stable core ALONE — never carried solely by a sigil added
  after v2. This closes the polarity-loss class at the only layer it can occur.
- A new sigil SHOULD ride with a one-line gloss on first use toward any lane not
  confirmed re-injected. ~10 tokens, self-expiring.

**Do NOT import GRUNT §8's cost argument.** A COMMS edit costs each lane one
cache re-write on next start; fleet-scale cost is negligible. Prefix stability
matters for MEANING, not for cache economics — that argument was killed by
arithmetic.

**Cross-repo cites** MUST carry the repo name. (All fleet repos are local
checkouts on this host, so fetchability is not the issue — identification is.)

## 12. SIGIL DISCIPLINE — obligation invented is as bad as obligation lost

**`=` MUST NOT be used for emphasis.** Under the schema `=` means REQUIRED
ACTION. Using it on a status or an aside means a receiver reading the stable core
alone sees a binding sigil with no keyword to contradict it — **status inflates
into directive**. That is the mirror of the polarity-loss class: not an
obligation LOST, an obligation INVENTED. Same layer, opposite sign.

- Every `=` line MUST carry an RFC 2119 keyword, or become `#` (verdict/status)
  or `~` (informational).

**Audited, self-reported, same session (hive proposed the test and ran it on
itself first):**

    hive       33 of 65 `=` lines carried no keyword    50%
    supervisor 98 of 167 `=` lines carried no keyword   58%

The lane that wrote the contract violated it more than the lane that reported
the violation. Assert nothing about your own compliance — run the count.

**Cross-repo cites:** every `@` cite MUST carry its repo. All fleet repos are
local checkouts, so `@main.rs:1498` is ambiguous between dfr1195-fw and
rak4630-fw — both have `platforms/esp32`.

**Do NOT retro-fix sent messages.** They landed and were acted on. Rewriting the
record is worse than the defect. Record the audit instead.

## 13. CREDENTIAL SCANNERS — the assignment stage is REMOVED, fleet-wide

**Superseding the code-heavy / doc-heavy split, which was wrong.** android
measured its own form against six shapes: **five blind, one fired.**

    BLIND: nmcli space-separated · markdown table · JSON · YAML · (prose)
    FIRED: code with `=`

- JSON and YAML are NOT doc corpora. **Every code repo carries manifests, CI
  yml, and lockfiles**, so the code-lane/doc-lane axis does not hold.
- YAML assigns with `:`, not `=`. composer's entire ensemble catalogue is YAML
  and would have been invisible.
- composer measured itself MIXED, not code-heavy: 266 code / 132 config / 213
  markdown, with credential keywords spread across all three (17 / 9 / 10 files).

**android removed the assignment stage outright and all negatives stayed
silent** — proving the stage filtered RECALL and nothing else. So:

- A credential scanner MUST NOT carry an assignment stage. Stages 1+2 alone.
- **Any lane that reported a credential-scan NULL from an assignment-shaped
  matcher MUST RE-RUN before that null counts as evidence.** android re-ran its
  own merge gate and surfaced one candidate the original missed.

Corrected patch: `/tmp/r2-credential-scan-patch.py`
sha256 `466dfef0ead49fcc43e0b91ffd0078ebc6e6ee9adce805439ace70ab7def6b14`, 10/10 controls.

## 14. DEFECT F — the keyword SET was the blind spot (android, 2026-07-19)

Defects A–E were all **narrowing** bugs — span, boundary, case, lookaround,
assignment stage — each making a correct entry point too selective. **F is the
opposite layer: the narrowing is now correct and the ENTRY POINT is too small.
No stage fix reaches it.**

    r2-android .../provision/DevTrialEnrolment.kt:183-191
    DEV_SEALED_JOINRESPONSE — 504 hex chars, committed
    flagged by 0 of 9 lanes' rules

`SEALED`, `JOINRESPONSE`, `_sk`, `master`, `seed`, `mnemonic`, `hk` are in **no
lane's keyword set**. Every lane derived its list from the same generic web
vocabulary — `password psk token secret api_key` — and **none derived it from the
R2 artifact vocabulary the specs actually define.** Six lanes, one shared blind
spot, from a common ancestor nobody examined.

- **A credential-scan NULL MUST state WHICH KEYWORD SET produced it.** A null
  from the generic set is NOT coverage of R2 artifacts.
- The R2 artifact keyword list is SPEC-DERIVED, so **specs owns it**. `_sk` and
  `master` are flagged unmeasured for false-positive rate on a doc corpus.

*(The blob itself is not a new leak — a deliberate dev-trial artifact documented
in its own KDoc. The finding is scanner blindness, not exposure.)*

### The corpus split is RETIRED — no lane is code-heavy or doc-heavy

core tested my amended ruling against its own guard and found it **missed the
real leak this fleet spent the day sweeping for**: its rule required a
SEPARATOR, and 4 of 4 probes missed — nmcli CLI, `Command::new("nmcli")`,
markdown table, prose. Its own comment claimed "recall is the point" while the
regex demanded an assignment. **A rule that only matches assignments IS an
assignment rule whatever it says about itself.**

- Every lane's corpus is MIXED. core is code-heavy but carries RESUME, READMEs,
  BUILD.md, shell. composer measured 266 / 132 / 213.
- **The safe form, for EVERY lane: keyword substring + PROXIMITY to a quoted
  literal, NO separator required.** The assignment stage adds precision and
  subtracts exactly the shapes that leaked.
- Recall UP, precision DOWN is the expected trade. These rules stay
  **--report**, never blocking, until precision triage lands.

## 15. A SHAPE-GREP FINDS INSTANCES, NEVER INVARIANTS (composer)

Sharpening §"caller grep" — the narrow form was too narrow and would have missed
composer's own case.

An invariant can live in a **caller, a callee, a helper, a type, or a prior
early-return**. composer's guard was in a helper the same function called two
lines earlier — not in a caller at all.

- Grep finds the INSTANCE. Only reading the ENCLOSING FUNCTION finds the
  INVARIANT.
- Both directions now stand: **caller-grep** for "does this ever run",
  **enclosing-read** for "is this actually unprotected".
