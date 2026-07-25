# Gate 23 — the fleet repo is public, and our own working records are in it

**Status:** 🔴 OPEN — no secrets exposed; internal structure is
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g23 and verify the counts yourself"*

## What I found

`reality2-ai/claude-fleet` is **public** — confirmed from the API, not assumed
(`isPrivate: false`). The working branch this fleet has been committing to all week is
**pushed to it**. That branch carries the supervisor's decision ledger, RESUME snapshot and
gate briefs, and those documents name private repositories, a private branch, and a great
many commit ids.

Counts I ran on the **published refs**, not the working tree:

| ref | private repo names in the ledger | commit-id-shaped tokens |
|---|---|---|
| `master` | 3 mentions, all structural (an authority chain, a tool path, one doc citation) | — |
| the pushed working branch | 6 in the ledger, plus one private **branch name** | **93** in the ledger alone |

Four repositories in the org are private and named in these files. Public ones named
alongside them are fine and I have left those alone.

## What this is, and what it is not

**Not** a credential leak. No keys, no MAC addresses, no personas, no device identifiers.
The published output guard for those held.

**Is** internal structure: which private repositories exist, one private branch name, and
enough commit ids to fingerprint development history. On its own each is small; together
they are a map of a private codebase published under a public org. This is the class you
already ruled on — *documenting IS publishing* — arriving from a direction that guard did
not cover, because the leak vector here is **the fleet's own bookkeeping**, not a generated
artifact.

**And I have been adding to it.** The gate brief I committed and pushed yesterday named a
private repository and a firmware worktree path. I have scrubbed those forward in this
commit, but I did not notice at the time, which is the part worth taking seriously: the
guard I was applying was about *content I generate for publication*, and I never asked
whether the notebook itself was published.

## What I have already done

Scrubbed the private names **forward** from the gate briefs and the RESUME snapshot —
replaced with lane descriptions that keep the meaning. That is safe and needed no ruling.

## What I have not done, and will not without you

**Anything touching published history.** The ledger's 93 commit ids and its private branch
name are in commits already on the public remote. Removing them means rewriting published
history and force-pushing, which standing rules forbid me. So it stays exactly as it is
until you rule.

## The decision

- **Make the repo private.** One action, closes the whole class immediately, needs no
  rewrite. Costs whatever the public repo was *for* — and I do not know that reason, so I
  cannot weigh it for you.
- **Scrub forward only, accept the history.** Cheapest. The existing exposure stays
  readable; only new material is clean. Defensible if the exposure is judged low-value.
- **Rewrite the branch history and force-push.** Removes it from the default view. Does not
  remove it from forks, clones, or anything already cached. **Force-push is currently
  forbidden to me**, so this needs your explicit lift.
- **Stop publishing the ledger.** Keep the fleet tooling public and move the working
  records — ledger, RESUME, gates — out of the published tree. Structural fix rather than a
  cleanup, and it is the only option that stops the next instance.

## Supervisor lean

**Make it private if the public repo has no active audience; otherwise stop publishing the
ledger.** Both close the class. Scrub-forward alone does not — this repo is *where the fleet
writes things down*, so the same leak recurs the next time a lane cites a path. I would not
rewrite history: it buys little against forks and caches, and force-push carries its own
risk.

## Ruling syntax

"gate 23: make it private" / "gate 23: scrub forward only" / "gate 23: rewrite history" / "gate 23: stop publishing the ledger"
