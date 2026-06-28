# ADR-002 — The multibrained-entity fleet (per-provider supervisors + entity binding)

**Status:** Design spec / explored direction (Roy, 2026-06-29). **Extends [ADR-001](ADR-001-r2-native-fleet.md)
Stage 2** ("move agent I/O off tmux keystroke-injection onto programmatic agent control") and gives it the
shape that the rest of ADR-001 only gestured at. **Not a big-bang commitment.** The near-term, low-risk slice
is the *entity-binding core* + one entity running a single native-hosted body; full multibrain is earned
per-provider as each native substrate proves out. This records the model so the choice stays deliberate.

---

## 1. The reframing this rests on

`claude-fleet` was built — and is still mostly described — as a tool that runs **AI agents**. The model in this
ADR inverts that:

> **A fleet member is not an AI agent. It is a sovereign, persistent ENTITY that *mounts* AI as a faculty.**

An entity's identity lives entirely in things that **survive any model**:

- its **id** and its **repo ownership + file-claims** (the one-writer-per-repo rule),
- its **durable memory** — `RESUME.md` (the handoff record a fresh brain rehydrates from),
- its **mailbox address** (`.fleet/inbox/<id>.jsonl` today),
- its place in the **supervision tree** and, ultimately, its **trust-group** membership.

A "Claude brain" and a "Codex brain" are **not what the entity is** — they are interchangeable minds it
currently runs, hot-swapped by `handoff`/`failover`. This is precisely an **R2 sentant**: an entity empowered
*by* AI, not defined by it. The fleet member is a **proto-sentant** (see `self-improving-system-vision`,
`north-north-star-and-values` in supervisor memory).

Two consequences fall straight out:

1. **No native primitive can *be* the entity.** A Claude subagent, a background session, a Managed Agents
   session — each *is-an* "AI agent": its identity *is* that session instance. It can only ever be **a brain
   the entity mounts**, never the entity itself.
2. **The entity is provider-count-agnostic.** Two brains (Claude + Codex) was only today's instance. The model
   is **N-brained / multibrained**: an entity mounts as many faculties as it has providers, and new AI
   providers are added over time without changing what the entity *is*.

## 2. The constraint that makes the topology necessary

Verified by a capabilities sweep (2026-06-29): **every native Claude orchestration primitive is Claude-only** —
subagents, background sessions (research-preview, v2.1.139+: durable, attachable, ID-addressable,
worktree-isolated, `bypassPermissions`), and the Managed Agents API (beta). A non-Claude provider (Codex,
and any future provider) can appear inside a Claude tree only behind an MCP shim — never as a co-equal brain.

This is **not a limitation to route around. It confirms the model**: no single-provider primitive can express a
multibrained entity, because the entity was never supposed to be a provider session.

## 3. Decision — the topology

**Run one native supervisor per provider, and bind their leaves into entities above them.**

```
            ┌─────────────────── entity-binding layer (thin, NON-AI) ───────────────────┐
            │   registry:  entity_id → { claude: leaf_ref, codex: leaf_ref, … }          │
            │   cross-provider mailbox   ·   pairing / failover / fitness-selection       │
            │   A9 firmware/key gate     ·   triage dashboard                             │
            └───────────────▲───────────────────────────────▲──────────────────▲────────┘
                            │ binds                          │ binds            │ binds
        ┌───────────────────┴────────┐   ┌──────────────────┴───────┐   ┌──────┴──────────────┐
        │  CLAUDE supervisor          │   │  CODEX supervisor         │   │  …Nth provider sup.  │
        │  (native Claude tree)       │   │  (native Codex tree)      │   │                      │
        │   leaf(entityA) leaf(B) …   │   │   leaf(entityA) leaf(B) … │   │   leaf(entityA) …    │
        └─────────────────────────────┘   └───────────────────────────┘   └──────────────────────┘
```

- **Each provider-supervisor uses its own provider's native primitives** — native lifecycle, liveness, message
  delivery and permissions *inside* each tree. This is what kills the tmux-injection / pane-scrape / watchdog
  bug class, on every provider at once.
- **The entity-binding layer is thin and carries no AI.** It owns only what is irreducibly *cross-tree* (see
  §5). It is the seed of an R2 sentant registry.
- **It is fractal.** The per-provider supervisors are themselves the brains of the **supervisor-entity**; each
  supervisor's leaves are *its* faculties. Entities composed of entities = an R2 ensemble. The model holds at
  every level.

## 4. Body vs. tool — what a "leaf" is

Claude exposes two primitives that are easy to conflate; the entity model needs both, in distinct roles:

| | **Subagent** (Agent tool) | **Background session** |
|---|---|---|
| Lifetime | Ephemeral (spawn→work→return→gone) | Durable (survives detach/reattach) |
| Human `fleet attach` | No | Yes (`claude agents`) |
| Warm context across turns | No (rehydrate from `RESUME.md`) | Yes (resident) |

**Rule:**

- A brain's **BODY** = a **resident, durable, attachable** leaf bound to the entity (Claude → background
  session; other providers → their durable-session equivalent where one exists). Preserves warm context and
  human oversight (`fleet attach`, the supervisor's safety layer — see `fleet-skip-permissions-and-oversight`).
- A brain's **TOOLS** = **subagents** the brain itself spawns one level down, for bounded fan-out (research,
  verification, the adversarial-refute pass). Subagents are *not* the entity's brains; they are what a brain
  *uses*.
- Because N resident bodies per entity is quota-prohibitive, an entity runs **one resident body + N on-demand
  faculties** (ephemeral leaves spawned per task / per refute pass, released after). Mounting is quota-aware.
  The entity/faculty split makes this safe: the durable state was never in the brain.

## 5. What stays fleet-level vs. what moves to native

| Concern | Where it lives |
|---|---|
| Entity identity + durable memory (`RESUME.md`) + repo-ownership/claims | **Entity layer** (fleet) |
| Entity-binding registry `entity_id → {provider → leaf_ref}` | **Entity layer** (fleet) |
| Cross-provider mailbox, hop-capping | **Entity layer** — subagents only return to their parent; no peer-to-peer (agent-teams not live) ⇒ cross-tree messaging is irreducibly ours. Rides on programmatic delivery, not keystrokes. |
| Pairing / failover / **fitness selection** / quorum refutation | **Entity layer** (see §6) |
| A9 firmware/key gate | **Entity layer** (security; → R2 trust groups eventually) |
| Triage dashboard (`status`/`brief`) | **Entity layer**, fed by *native* liveness instead of pane-scraping |
| Per-brain lifecycle, liveness, message-deliver-in, permissions, isolation | **Native** (per provider tree) |

## 6. Ensemble semantics (the generalization of pair/failover)

Two brains gave a binary pair + failover. N brains give a richer, mission-aligned set:

- **One writer** at a time per repo (existing rule); the other brains are **adversarial reviewers / standbys**
  (existing twin model).
- **Failover** = promote *any* standby, not just "the other one."
- **Fitness-based selection** = the entity picks which brain for a task by capability / cost / quota /
  availability. Survival-of-the-fittest at the *faculty* level (`self-improving-system-vision`, Thurisaz).
- **Quorum refutation** = N *genuinely independent* models voting on a claim. More providers = more independent
  perspectives = stronger refutation. Scales `test-design-conjecture-refutation` and the standing
  `codex-adversarial-helper` practice directly with brain-count.

## 7. The payoff

- **Occam.** The biggest simplification in the codebase is not an edit — it is this substrate move, which
  **deletes** the watchdogs, most of `fleet doctor`, the inject-verify Enter-race loop, and the
  unstick/reconcile + pane-scraping machinery in `registry.sh`/`comms.sh` (hundreds of lines that exist *only*
  because we type into TUIs). The remaining provider differences collapse from binary `claude|codex` branches
  into one **faculty-adapter contract** with N implementations (see [the contract spec](FACULTY-ADAPTER-CONTRACT.md)).
- **Sovereignty over cognition.** A provider-agnostic, multibrained entity is beholden to **no single AI
  vendor** — it can blend or swap faculties, and eventually mount on-grid / local / open models as they earn it.
  That is `north-north-star-and-values` one layer deeper than previously stated: not just sovereign data and
  networking, but **sovereign intelligence**.

## 7a. The supervisor as the flagship multibrain entity — a local-model body

The supervisor is an entity too (ADR-001/`supervisor-purpose`), and it is the best place to *prove* the model —
because its job (coherence + mission-alignment + surfacing directional decisions) is the **highest-judgment** in
the fleet, so it forces the discipline that stops the model degrading accuracy.

**The trap:** "run the supervisor on a small local model (LM Studio)" naively fails exactly where it is most
dangerous — nuanced alignment judgment.

**The resolution: decompose the supervisor's work by judgment level and route by fitness-selection (§6).** The
supervisor-entity is multibrained:

| Supervisor work | Frequency | Brain | Why it fits |
|---|---|---|---|
| Poll `brief`/`doctor`/event-log (JSON), detect stall/conflict/throttle, draft routine nudges, summarize into the entity-memory head, decide "this needs a hard brain / a human" | constant | **Local body** — Codex-OSS via `codex exec --oss --local-provider lmstudio` | extraction + routing over *structured* data is what small models do reliably; free per token |
| Real coherence/alignment judgment, cross-cutting architecture, "who owns X", surfacing a/b/c choices to Roy | rare | **Cloud body** (Claude/Codex), on-demand faculty | the hard judgment; pay cloud tokens only here |

The local brain is the always-on **resident body** doing cheap continuous monitoring; it **escalates** to a
cloud faculty (or to Roy) the moment a decision exceeds its confidence. Net: **most supervision becomes free and
local; cloud tokens are spent only on rare hard calls** — the "accuracy with minimal tokens" constraint applied
to the most important entity.

**Why the architecture already supports it:**
- *Mount path:* reuse the **Codex adapter** in its `--oss --local-provider lmstudio` mode — the local model
  inherits Codex's session / sandbox / tooling / event-stream machinery; no new adapter.
- *Feasible only because of [ENTITY-MEMORY](ENTITY-MEMORY.md):* local models have small context windows; the
  pull-not-push design means the supervisor reads the `brief`/`doctor` JSON + the entity-memory **head** (small),
  never a transcript — it fits.
- *Safety holds:* the local supervisor is confined to **observe / draft / escalate** — never unattended
  authority over high-stakes ops (the A9 gate + prompt-gating still apply, `fleet-skip-permissions-and-oversight`).
  A weaker model is *safe* because its remit is monitoring + routing, not autonomous action. Policy: conservative
  escalation (when uncertain, escalate — cheap to over-escalate, costly to miss); a cloud brain audits a sample
  (quorum backstop, §6).

**Payoff:** the fleet's *coordinating intelligence runs on-grid, owned by no cloud vendor*, falling back to cloud
cognition only for rare hard judgment — and it satisfies ADR-001's requirement that the fleet keep a **non-cloud
path to operate and to recover R2** when the cloud is unreachable. Sovereign supervision, cloud judgment on tap.

## 7b. Graceful degradation when the supervisor's brain exhausts

A multibrained supervisor must degrade *down a judgment ladder*, never off a cliff — and the lower rungs cannot
fail the way the top can. Token exhaustion becomes a **quality reduction**, not an outage, and **never a silent
wrong call**.

```
  cloud brain A (best judgment)     ──exhausts──▶  fail over to…
  cloud brain B (other provider)    ──exhausts──▶  fall back to…
  local body (LM Studio, NO quota)  ── can't exhaust; keeps monitoring, QUEUES hard calls ──▶
  human (Roy, ultimate brain)       ── can't mis-judge alignment, by definition
```

Each rung is reached from the one above on **exhaustion** — which must be distinguished from **throttle**
(transient rate-limit: wait, the api-watchdog unsticks; never a reason to switch). The fleet already separates
these (`fleet_pane_is_provider_exhausted` vs `fleet_pane_is_throttled`); the `liveness` verb returns both
states. This is §6 fitness-failover + the existing `cmd_failover` exhausted-handling, with the **local body as
the non-exhausting floor** and the **human as the top**.

**But the switch itself must not depend on the brain being switched (§7c), or a brain "suddenly unable to act"
deadlocks — unable even to fail itself over.**

Two guardrails keep the degraded supervisor *accurate*, not merely alive:

- **Losing a brain loses *capability*, not *knowledge*.** Supervisor state lives in the entity-memory head +
  decision log ([ENTITY-MEMORY](ENTITY-MEMORY.md)), not a cloud brain's context — so an exhausted brain strands
  nothing; a fresh local body or Roy resumes from the same durable head (verify-then-record paying off).
- **Queue hard calls, never guess them.** With cloud judgment unavailable, the supervisor records the decision
  as `awaiting-judgment, reason=cloud-exhausted` and surfaces it to Roy; the queue drains when a cloud quota
  resets or Roy answers. At-least-once for *decisions*, mirroring the mailbox's at-least-once for messages.

The inverse risk — a local model **over-confidently** treating a hard call as routine — is blocked structurally:
**capability is bounded by an allowlist, not by the model's confidence.** The local body may autonomously do
only mechanical things (nudge a stalled worker, mark throttled, refresh the head); everything else is
escalate-only *by policy*. Under-confidence degrades to "ask the human" (safe); over-confidence is impossible
because the judgment verb is not on the local body's allowlist (safe).

## 7c. The actor of last resort — failover must not share the brain's failure domain

The deadlock §7b must avoid: if failover is a *decision a brain makes*, then a brain **suddenly unable to act**
(exhausted mid-turn, hung, crashed) is also unable to fail itself over. The switcher cannot be the thing being
switched — the classic *who-restarts-the-restarter*.

**Rule:** the actor of last resort must share **no failure domain** with the brains, hold **no quota**, and
depend on **no judgment** — i.e. it must be **non-AI**. This is the real reason ADR-002 §3 insists the
entity-binding layer is thin and non-AI: so it can *always act*. **The brain never switches itself; the entity
layer switches the brain out from under it**, driven by the **watchdog** (already pure bash in a separate
process: `fleet-api-watchdog.sh`, `fleet-watchdog.sh`, `cmd_reap`, `fleet_pane_is_provider_exhausted`, the
systemd user unit). For the watchdog, "acting" is just running a command — it cannot be "unable to act."

**Failure-domain stack** — each lower layer is simpler, quota-free, and a separate process from the one above:

```
  AI brains            (judgment; CAN exhaust / hang / crash)
     ▲ switched by
  entity-binding layer (bash; non-AI; no quota)
     ▲ driven by
  watchdog             (bash; separate process; polls liveness + acts)
     ▲ kept alive by
  systemd user unit    (restart=always; OS-level)
     ▲
  kernel
```

This yields **two floors, both required**:
- **Mechanical floor** (watchdog + systemd) — can *act* unconditionally; cannot think.
- **Cognitive floor** (the local LM Studio body, §7a) — can *think* cheaply and never exhausts; cannot restart
  itself.

The watchdog *performs* the switch; the local body is *what it switches to*. ("Add a local brain" and "the
switch must be external" are two halves of one answer.)

**Worst case — local body also down** (crashed, not merely exhausted): the mechanical floor can act but has
nothing cognitive to mount. Degrade, in order: (1) **workers keep running** — independent entities; a dead
supervisor removes *oversight*, not *work*; (2) the **A9 gate still guards** every high-stakes op (a per-tool
hook, independent of the supervisor) — safety holds with zero supervision; (3) the watchdog raises an
**unmissable, quota-free alert** to Roy (local push / a `BLOCKED` marker — never a cloud call). Floor of the
floor: *runs unsupervised-but-safe, and Roy is loudly told* — never halts, never acts wrongly.

**Pre-emption (optimization):** demote on the provider's *approaching-limit* signal, while the brain can still
cleanly verify-then-record its head — so the common case is graceful. The mechanical watchdog is the
*guarantee* for the no-warning case.

## 7d. Display — fidelity at the leaf, overview at the entity

The one genuinely hard cost of leaving tmux is **output rendering**: today, attaching to a tmux window gives a
brain's provider TUI (Claude Code / Codex) **nicely formatted, for free**. Losing that would be a real
regression, so the model splits display the same way it splits everything else:

- **Rich formatting is a property of a *leaf*, obtained by *attaching*.** For resident **bodies** on attachable
  native sessions this is preserved at **zero rebuild cost** — `claude attach <id>` reattaches you to the real,
  formatted session. This is a concrete reason **body = background session**, not subagent.
- **The *entity* view is deliberately coarser** — a structured dashboard of status / messages / tool-results /
  failovers / quorum verdicts over a normalized event stream. It must **not** try to merge N provider TUIs into
  one terminal (that is the trap — unbounded effort, lower fidelity than just attaching).
- **Non-attachable leaves** (ephemeral subagent *tools*; later, cloud Managed-Agents leaves that emit an SSE
  event stream) surface their **result** into the owning body's transcript and their **activity** into the
  entity log — never a fake terminal.
- **The beautiful unified entity view is a `composer` / R2 proof-surface concern** (`composer-as-user-app`),
  built over the same normalized stream — not a CLI responsibility. The CLI's honest job is attach-through +
  structured dashboard (it already has the weak form: `fleet attach`, `fleet logs`, `fleet brief`).

See the `attach` / `stream` verbs and the **Display principle** in
[the contract spec](FACULTY-ADAPTER-CONTRACT.md).

## 8. Migration stages (no big-bang; each behind a fallback)

1. **Now:** keep bash/tmux. This ADR + the contract spec are the design record; the bugs remain discovered
   requirements.
2. **Entity-binding core (near-term, low risk):** introduce the explicit entity registry
   (`entity_id → {provider → leaf_ref}`) and the faculty-adapter contract as a *seam* — the existing
   `transport.sh` / `provider.sh` become its first (tmux/CLI) implementation, behaviour unchanged.
3. **First native body:** mount one entity's Claude brain as a **background session** behind the seam (add a
   `bg` branch beside `tmux`). Measure: does the stuck-message / idle-guess / watchdog class disappear? Keep
   that entity's Codex brain and all cross-tree coordination in the fleet. **Never migrate the prompt-gated
   supervisor first.**
4. **First native cut of an ephemeral faculty:** move the `fleet ask` responder to a managed subagent — native
   worktree isolation **structurally fixes** the live-checkout-write hazard
   (`fleet-ask-fork-writes-live-checkout-hazard`).
5. **Entity memory:** formalize `RESUME.md` into the bounded head + append-only decision log and add the
   `recall` verb ([ENTITY-MEMORY](ENTITY-MEMORY.md)) — the pull-not-push memory that makes small-context (local)
   brains viable and keeps cross-brain sharing accurate + cheap.
6. **Local-model supervisor body:** mount a Codex-OSS(lmstudio) body for continuous structured monitoring,
   escalating to a cloud faculty / Roy for hard judgment (§7a) — sovereign supervision.
7. **Per provider, as it earns it:** stand up each provider-supervisor as a native tree; generalize binary
   pairing to ensemble semantics; add providers beyond Claude+Codex through the same contract.
8. **End-state (earned, possibly never in full):** the entity layer is an R2 ensemble on BOS, entities are
   sentants, `composer` is the kaitiaki surface (per ADR-001).

## 9. Open questions / where this would be wrong

- **Provider durability asymmetry — RESOLVED (2026-06-29).** Verified against Codex 0.142.3: Codex *can* be a
  resident attachable **body** — named resumable/archivable/forkable sessions, plus the experimental
  `app-server` daemon + `remote-control` with TUI attach over `--remote` (ws/wss/unix), a `--json` JSONL event
  stream, and a versioned app-server protocol. Maturity is symmetric (both Codex daemon and Claude
  background-sessions are experimental/preview). See the [verified provider matrix](FACULTY-ADAPTER-CONTRACT.md).
  Residual: harden the experimental daemon paths before relying on them; keep the tmux/exec fallback.
- **No native cross-tree (or even intra-tree peer) messaging.** Agent-teams is announced, not live. The
  mailbox stays ours for the foreseeable future; this ADR assumes that and keeps it thin.
- **Cost.** Multibrain multiplies token/quota spend. The one-body-plus-on-demand rule (§4) is the mitigation;
  fitness-selection must be quota-aware, not just capability-aware.
- **Research-preview risk.** Background sessions are a research preview; the seam (Stage 2) must keep the
  tmux implementation as a working fallback until the native path is proven.
- **Don't port like-for-like.** Migrate a piece only when its bash brittleness costs more than its replacement
  (ADR-001's standing caution).

## 10. Decision trigger

Begin Stage 2 (entity-binding core + one native body) in a calm window. Stand up a second provider-supervisor
only once the single-provider native path is proven and the cross-tree binding is exercised. Add a third
provider only through the faculty-adapter contract, never by special-casing.
