# FLEET COMMS STANDARD v2 — binding on every fleet member, both providers

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

## 2b. DENSE WIRE FORMAT — agent-to-agent default

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
