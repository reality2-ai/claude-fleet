# Gate 16 — a branch was described as containment; it never was

**Status:** 🔵 OPEN — no incident, no exposure; a disposition decision
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g16"*

## What happened

Android's handoff described a branch as **held unpushed** so that stale sensitive-adjacent
content would not be published. Verified: that branch is an **ancestor of master with
nothing unique to it** — its content has been on origin all along. **The stated protection
was never real.**

Severity is bounded and I want to be plain about it: **the repo is private, so nothing was
exposed, and there is nothing to undo.** Android changed only the description. It found
this by re-verifying a line it could have copied — the line was true when written and
became quietly false later, with nothing to test it and nothing to grep for.

## The rule that came out of it

**A branch is never a containment boundary.** It is a pointer; ancestry and merges make it
worthless as protection, and the protection can evaporate without anyone touching the
branch. The only real boundaries are not committing the content, repository visibility, and
rewriting history. Any handoff line claiming a branch holds something back is describing an
*intention*, not a mechanism.

## The decision

A **second** branch does hold genuinely sensitive parents that are **not** reachable from
master. Verified. But it is held apart only by **not having been merged** — which is a
state, not a guarantee. **One merge publishes it silently:** no gate, no warning, no failing
test. "Intact" means "not yet merged".

- **Delete the branch** — removes the hazard permanently. Loses whatever was on it.
- **Rewrite the history** — keeps the work, removes the sensitive parents. More effort, and
  history rewriting has its own risks.
- **Accept it** — leave as is, with the hazard recorded, on the basis that the repo is
  private and the content is sensitive-*adjacent* rather than secret.

## Supervisor lean

**Delete, unless you know something is on it you want.** The branch has no active role, the
protection people believed in was imaginary, and the failure mode is silent. Accepting is
defensible given the repo is private — but then it should be accepted *knowingly*, which is
what this gate is for, rather than by a future merge nobody thought about.

## Ruling syntax

"gate 16: delete" / "gate 16: rewrite" / "gate 16: accept"
