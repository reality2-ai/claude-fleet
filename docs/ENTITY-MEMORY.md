# Entity memory — sharing knowledge across an entity's brains, accurately and cheaply

**Status:** Design spec (2026-06-29). Companion to [ADR-002](ADR-002-multibrained-entity-fleet.md) and
[the faculty-adapter contract](FACULTY-ADAPTER-CONTRACT.md). Answers: *how do an entity's N brains (Claude,
Codex, future/local providers) share what they know, with maximum accuracy and minimum token cost?*

The two goals pull against each other — a cheap summary can confabulate; perfectly accurate ground truth can be
token-explosive to ship around. The whole design is the resolution of that tension.

---

## The one principle

> **Brains share the *world*, never their *conversations*.**

An entity's brains do **not** share context windows. They do **not** replay or translate each other's
transcripts. Cross-translating a Claude transcript into a Codex context (or vice-versa) is the worst possible
option on **both** axes: it is token-explosive *and* lossy *and* provider-specific. It is forbidden by this
spec.

Instead, brains coordinate through small, durable, **provider-agnostic artifacts that describe the world and the
decisions made about it** — read **lazily**, on demand. Everything below is a consequence of this principle.

## The five pillars

### 1. Ground truth IS the shared memory
The repository — code, tests, git history, commit messages, the diff — is the most accurate *and* most
token-efficient shared memory available: it is the actual state, it is provider-neutral, and a brain reads only
the slice it needs (`grep`/read a file), paying tokens per-need. A Codex brain learns what a Claude brain did by
reading the **commit/diff** (`codex apply` even consumes diffs as a first-class unit), not by being told.
*Accuracy: perfect. Tokens: pay-per-need.*

### 2. One small, structured, canonical entity-memory doc
What isn't yet in the code — intent, decisions-and-why, open questions, claims, next steps, refutation status —
lives in a single bounded document per entity (today's `RESUME.md`, formalized). It has a **living head**
(current state, overwritten) and an **append-only log** (decisions, never rewritten). It is the shared *working
memory* both brains read on mount and update verify-then-record. Bounded by construction (the head is O(KB); the
log is tail-truncated like `fleet_journal_append` already does). *Accuracy: a curated digest. Tokens: bounded.*

### 3. Append-only decision log + delta reads
For accuracy without re-reading everything, decisions append to a **sequence-numbered, content-addressed** log,
each entry carrying **provenance** (which brain, when, verified-against-what). A brain mounting reads only the
**delta since its last seen sequence number** — not the whole history. "What's new since seq N" is a cheap,
exact query. Content-addressing dedups identical facts two brains might both record. *Accuracy: provenanced +
append-only (no silent overwrite). Tokens: O(delta), not O(history).*

### 4. Pull, don't push (retrieval over injection)
The single biggest token lever. Do **not** stuff all memory into every brain's prompt — that pays for memory the
task doesn't need. On mount a brain is seeded with the **head only** (small) and the knowledge that it can
**recall** more on demand: the log-delta, a repo grep, its `inbox`. Add a `recall(entity, query)` verb to the
faculty contract; each brain pays only for what it actually retrieves. Eager context-stuffing is the default
failure mode and this spec rejects it. *Tokens: pay-per-retrieval.*

### 5. Verify-then-record makes the cheap digest trustworthy
This is what dissolves the accuracy/token tension. A fact enters the canonical memory **only after being checked
against ground truth at write time** (the fleet's existing verify-then-record doctrine, see
`fleet_peer_primer`). So a downstream brain can *trust the cheap digest without re-deriving it*, because the
expensive verification was paid **once, at write**, not on every read. This converts an expensive-per-read
accuracy problem into a cheap-per-read one — the core economic move of the whole design.

## Mechanism

```
.fleet/memory/<entity>.md         # living HEAD: intent, claims, open Qs, next steps, refute status (overwritten, bounded)
.fleet/memory/<entity>.log.jsonl  # append-only DECISION LOG: {seq, ts, brain, claim, evidence, supersedes?} (tail-bounded)
```

- **Plain text + JSONL, provider-agnostic.** Claude and Codex read/write the *identical* files — no translation
  layer. Codex emits a structured update cheaply via `codex exec --output-schema <file>` /
  `--output-last-message <file>`; Claude via its structured output. The artifact is the lingua franca.
- **On mount:** seed the brain with the head only, plus "you may `recall` the log delta / grep the repo /
  read your inbox." Never the transcript.
- **On a meaningful turn / before idle:** the brain appends verified decisions to the log and refreshes the
  head — verify-then-record, bounded.
- **Conflict:** disagreeing brains both append with provenance; the **writer** brain (or a **quorum**, ADR-002
  §6) records the resolution as a new entry that `supersedes` the old. No silent overwrite — accuracy preserved.
- **Token accounting:** head = O(KB); recall = O(delta); repo = O(targeted grep). **No O(transcript) path
  exists anywhere.** That is the design's guarantee.

## What this is NOT
- Not a shared context window. Not transcript replay or cross-provider transcript translation (forbidden, §"one
  principle").
- Not eager prompt-stuffing of all memory (rejected, pillar 4).
- Not a database to stand up — it is two files per entity, an evolution of `RESUME.md` + the existing journal /
  event log.

## Contract + ADR hooks
- Faculty contract gains one verb: **`recall(entity, query) → text`** (lazy retrieval from head + log-delta +
  repo). The body/tool split (ADR-002 §4) is unchanged; on-demand faculties rehydrate purely from the head on
  each spawn, which is *why* ephemeral leaves are cheap and safe.
- The entity-memory doc is the durable-memory contract ADR-002 §5 already requires the entity to keep current so
  any brain can be mounted cold.

## Mapping to today
| Concept | Today | This spec |
|---|---|---|
| durable handoff memory | `RESUME.md` (free-form) | `<entity>.md` head — same file, sectioned + bounded |
| decision history | (implicit in transcript) | `<entity>.log.jsonl` append-only, provenanced, delta-readable |
| bounded growth | `fleet_journal_append` tail-truncate | same mechanism, applied to the log |
| cross-brain transfer | tmux-visible / `handoff` transcript tail | read the head + recall; **never** ship the transcript |
| trust in a digest | hope | verify-then-record at write time (pillar 5) |
