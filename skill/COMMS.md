# FLEET COMMS STANDARD — binding on every fleet member, both providers

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
spec section numbers, the falsifier itself. Never invent abbreviations —
`cfg`/`impl`/`req` tokenize the same as the full word.

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
- RESUME.md / handoff / AGENTS.md: PROSE. A takeover MAY be a human.

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

Note #4 was authored *in the act of ruling that prose is not a gate*. The trap
survives knowing about it, so apply the test mechanically, not by intuition.

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
