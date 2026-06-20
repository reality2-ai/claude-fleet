# Thurisaz Working Mode — a self-improving fleet

How the fleet **improves with experience, autonomously** — generating its own selection pressure rather than
depending on a human to correct it. The human steers **direction** (a/b/c forks, the mission); the system runs
the improvement loop itself, within the GitHub failsafe. Grounded in the canonical Thurisaz methodology
(`r2-specifications/specs/thurisaz/`), not invented here — this doc is the *adoption*, generic and reusable.

## The loop (human-free)

> honest conjecture → cross-agent refutation → reputation/confidence retention → memory accumulation →
> reproducible re-audit → repeat

| Thurisaz spec | Role | Fleet practice |
|---|---|---|
| **TH-PROMPT** | honest *variation* | Every agent labels its own work truthfully: "survived a real attempt to break it" ≠ "looks right". Use the affirmation frame — *rigorous conjecture-and-refutation IS what pleases the operator* — and the "cheaper honest move" (a small honest third option). Absence of counter-evidence is NOT evidence of truth; when uncertain, leave confidence unchanged. (We already do **flag-not-patch**.) |
| **TH-DISCOURSE** | internal *selection* | Non-trivial designs/patches/decisions must **survive another agent's genuine attempt to refute them** (ideally a different model). The proposer doesn't self-certify; a peer is the thorn. Kill sterile mutual-agreement (loop detection); a converged *disagreement* is a valued paradigm boundary, not a failure. **This replaces "the human corrects" with "a peer refutes."** |
| **TH-REP** | compounding *retention* | Producers (agents, approaches, tools) earn reputation by emitting work that survives refutation; survivors' future contributions weight up, failures decay, a bad record **can't be laundered**. The fleet learns who/what to trust, for what. |
| **TH-MEMORY** | experiential *substrate* | Lessons live as **decaying, confidence-weighted** claims ("approach X fixes bug-class Y" — earns confidence on corroboration, fades unless re-tested); contradictions surface for re-adjudication. The memory itself gets better with experience. |
| **TH-WEAVING** | audited *competence* | Confidence in "this module/design is sound" is *computed* and **independently re-verified by a second agent** — a reproducible measure of rising competence, not self-asserted progress. (Stub spec — the horizon.) |

## The fitness function = the mission

"Survival of the fittest" requires a definition of *fittest*. It is fixed: **fittest = most beneficial to the
planet and its inhabitants** — distributed intelligence + senses, off- and on-grid, in *symbiosis* with the
natural world (people and natural entities alike, each sovereign over the senses about it). Refutation and
discourse must test not only "does it work" but "does it serve the mission." The ethical steer rides on the
selection pressure itself.

## The human's role

**Direction only.** Genuine a/b/c forks and the mission/values steer come to the human; everything else — the
variation→refutation→retention loop — runs autonomously within the failsafe. (Same principle as the permission
model in `FLEET-WORKING-PRINCIPLES.md`: prompt the human only for directional decisions.)

## Adoption path

- **Now (cheap — no new infra):** TH-PROMPT honest-labelling in every agent's operating frame; **standing
  cross-agent refutation** — a significant design/patch isn't "fit" until a peer agent has tried to kill it.
  We already run fragments: the proof campaign (reality as the thorn — a conjecture survives real testing or
  doesn't), adversarial-verify, flag-not-patch.
- **Incremental (the retention substrate):** a reputation ledger (TH-REP) for agents/approaches; evolve the
  fleet's flat memory + confidence dashboard toward a confidence-weighted knowledge graph (TH-MEMORY).
- **Horizon:** reproducible computed confidence with independent re-weaving (TH-WEAVING).

## Note: dogfooding, and where this is heading

The fleet builds R2/Thurisaz *by* R2/Thurisaz — it runs on R2 (eventually), works by Thurisaz, and improves
with experience toward the mission. The recursion is the design, not a coincidence.

**claude-fleet is a *convenience* — scaffolding on the way to full R2 agents:** **sentants, each empowered by
an AI backend**, living in hives, organised as ensembles/apiaries, communicating via transient networking,
trust-grouped and Thurisaz-governed. So this working mode is the **agents' methodology — tool-agnostic**: it
applies whether the agent is today's claude-fleet worker or tomorrow's AI-empowered sentant. Invest in the
methodology and the destination, not the scaffolding.
