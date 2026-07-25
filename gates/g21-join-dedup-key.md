# Gate 21 — the dedup key: your g15 ruling is half-effective until this is ruled

**Status:** 🔴 OPEN — **blocks the g15 ruling from taking effect**
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g21 and gates/g15"*

## Why this is urgent rather than tidy

Two lanes asked you to rule the relay question and the dedup key **together**. You ruled the
relay half. Executing it, specs found the reason they asked:

**R2-ROUTE §3.8, the dedup path:** `if parsed.route_stack is empty: return // DROP
non-conformant`.

That is a **different code path** from the relay exception you just authorised. The step-c
relay exception does not reach it. So **an origin-less join arriving at its target is still
dropped there** — the relay half is permitted and the dedup half still forbids it.

Specs deliberately did **not** patch it, because patching the dedup drop *is* choosing the
key, which I had told it not to infer. That was the right call. But it means your ruling
does not yet function end to end.

## The decision

The dedup key for these frames is currently a **single global message identifier**. That was
safe only while joins were never carried. Now that one intermediary may carry them, the
namespace matters.

- **`(sender_pk, sequence)`** — android's proposal, from the §10.2 header. Properly
  namespaced per joiner, so two joiners cannot collide by construction.
- **Keep the global identifier, scoped** — simplest, but two joiners minting the same
  identifier collide, and a join is attacker-mintable by design.
- **Something else specs proposes** — it now owns the surrounding mechanism and may have a
  better fit.

Whatever you choose, the §3.8 drop needs the matching exception so a carried join survives
its own dedup check.

## What has changed since the lanes first raised it

Specs' mechanism ruling — **terminate-and-re-originate, never blind forwarding** —
materially reduces the exposure. A carried join arrives **origin-bearing**, because the
carrier stamps its own origin, so the per-origin quota applies and the carrier spends its
*own* quota. The unmeterable hazard is **dissolved rather than capped**. Collision risk is
correspondingly narrower than when the lanes first flagged it: a join reaches one
intermediary and its target, not a five-hop flood.

So this is now a **correctness** question — does a carried join survive dedup — more than a
flooding-defence question.

## Supervisor lean

**`(sender_pk, sequence)`, and rule the §3.8 exception in the same breath.** It is
namespaced by construction rather than by assumption, it is already in the header so it
needs no new wire field, and it removes the collision question instead of bounding it. The
global identifier is safe only under an argument about how far joins travel — and we have
just changed how far joins travel.

## Ruling syntax

"gate 21: sender_pk + sequence" / "gate 21: keep global, scoped" / "gate 21: specs proposes"
