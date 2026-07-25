# Gate 23 — our working records are published in six public repositories

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

## IT IS NOT ONE REPOSITORY — IT IS SIX

**This is a correction to my own gate, found after I wrote it.** I scoped g23 to the repository
I happened to be standing in. The class is *lane bookkeeping published in a public repository*,
and five other public repos carry a ledger or a takeover snapshot:

| public repo (by role) | file | private repo names | commit-id-shaped tokens |
|---|---|---|---|
| the fleet tooling repo *(this one)* | ledger | 8 | 98 |
| a build/artifact lane | ledger | 5 | 57 |
| same lane | snapshot | 4 | 24 |
| a tooling lane | ledger | 0 | 172 |
| a workshop lane | snapshot | 0 | 9 |
| **the public website repo** | snapshot | 3 | 0 |

Roughly **20 private-repo-name mentions and ~360 commit-id-shaped tokens across six public
repositories** — and the last row is the repository that *serves the public site*.

**Two things follow.** The exposure is already **pushed and live** in those five; only this
repo's recent commits are held. And **I cannot fix them** — they are lane-owned and I do not
write to lane repos, so whatever you rule has to be dispatched to owners rather than executed
by me.

Method note, since it is the day's pattern one more time: my first blast-radius command
**failed green** — a shell construct that does not word-split silently returned all zeros, which
reads exactly like a clean result. The separate positive control caught it. Numbers above are
from the corrected run, with a read-failure negative control.

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

- **Make the repos private.** Closes the class immediately, needs no rewrite. But it now means
  *six* repositories, one of which serves the public website and plainly cannot go private —
  so this option no longer covers the whole class on its own.
- **Scrub forward only, accept the history.** Cheapest. The existing exposure stays
  readable; only new material is clean. Defensible if the exposure is judged low-value.
- **Rewrite the branch history and force-push.** Removes it from the default view. Does not
  remove it from forks, clones, or anything already cached. **Force-push is currently
  forbidden to me**, so this needs your explicit lift.
- **Stop publishing lane bookkeeping anywhere public** *(supervisor lean)*. Keep the tooling and
  the site public; move ledgers, snapshots and gate briefs out of published trees. Structural
  rather than a cleanup, applies uniformly across all six, and it is the only option that stops
  the next instance.

## Supervisor lean

**Stop publishing lane bookkeeping in public trees, uniformly across all six.** Going private
no longer covers the class now that the public website repo is in it. Scrub-forward alone does
not close it either — these repos are *where the fleet writes things down*, so the same leak
recurs the next time any lane cites a path. I would not rewrite history: it buys little against
forks and caches, and force-push carries its own risk.

**Whatever you rule, it has to be dispatched** — five of the six are lane-owned and I do not
write to lane repos.

## Ruling syntax

"gate 23: stop publishing bookkeeping" / "gate 23: make them private" / "gate 23: scrub forward only" / "gate 23: rewrite history"
