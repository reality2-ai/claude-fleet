# AGENTS.md — fleet member

Before edits, read this file, `DECISIONS.md`, `RESUME.md`, and relevant project docs;
then run `git status`. Ground truth beats transcript or memory.

## Repository map — complete before substantive work

- Role: TODO(fleet-onboarding)
- Canonical authority: TODO(fleet-onboarding)
- Upstream dependencies: TODO(fleet-onboarding) (or `none`)
- Downstream consumers: TODO(fleet-onboarding) (or `none`)
- Owns: TODO(fleet-onboarding)
- Does not own: TODO(fleet-onboarding)
- Invariants: TODO(fleet-onboarding)
- Verification commands: TODO(fleet-onboarding)

Unresolved fields are blockers for cross-repo or behavioural changes. Ask the
supervisor; do not guess dependency direction, ownership, or authority.

## Shared fleet contract

- Make the smallest verified change. Treat claims as conjecture until tested.
- Consult `DECISIONS.md` before revisiting established behaviour. Append key rulings,
  holds, reviews, and consequential delegated agent choices before commit; record the
  real decision-maker, authority basis, rationale, alternatives, and evidence. Routine
  commits carry `Decision-Log: none`.
- Keep `RESUME.md` as one concise current handoff, not a diary.
- Stage task-owned named paths only. Commit verified increments, non-force-push the
  upstream, and confirm no local commit remains ahead before idle or done.
- Never bypass safety gates, force-push, discard others' work, or perform destructive or
  high-stakes actions without explicit authority.
