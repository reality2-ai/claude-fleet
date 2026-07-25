# Gate 23 — our working records are published in five public repositories

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

## IT IS NOT ONE REPOSITORY — IT IS FIVE

**Two corrections to my own gate, both found after I wrote it.** First, I scoped g23 to the
repository I happened to be standing in; the class is *lane bookkeeping published in a public
repository*. Second — and this one I got wrong while correcting the first — **I then reported
"six repositories" when it is six FILES across FIVE repositories.** One repo carries both a
ledger and a snapshot and I counted its rows as repos. Specs enumerated the class independently
and got five; it is right.

Of 22 org repositories, 10 are public and **five carry a ledger or snapshot on the pushed ref**:

| public repo (by role) | file(s) | private repo names | commit-id-shaped tokens |
|---|---|---|---|
| the fleet tooling repo *(this one)* | ledger | 8 | 98 |
| a build/artifact lane | ledger + snapshot | 9 | 81 |
| a tooling lane | ledger | 0 | 172 |
| a workshop lane | snapshot | 0 | 9 |
| **the public website repo** | snapshot | 3 | 0 |

Roughly **20 private-repo-name mentions and ~360 commit-id-shaped tokens across five public
repositories** — and the last row is the repository that *serves the org's public site*. Specs
reached the same five independently, with a positive control proving its comparison discriminated
and two genuine nulls.

**Two things follow.** The exposure is already **pushed and live** in those five; only this
repo's recent commits are held. And **I cannot fix them** — they are lane-owned and I do not
write to lane repos, so whatever you rule has to be dispatched to owners rather than executed
by me.

Method note, since it is the day's pattern twice more: my first blast-radius command **failed
green** — a shell construct that does not word-split silently returned all zeros, which reads
exactly like a clean result. The separate positive control caught it. And the "six" above was a
plain miscount of table rows as repositories, made *in the act of widening the scope*. Numbers
here are from corrected runs with read-failure negative controls.

**Scope of what was checked, stated so it is not read as more:** private-repo-name tokens,
commit-id-shaped tokens, and the key/MAC/persona classes named above — on the ledger and snapshot
files only. It is **zero evidence** about any other file in those repositories.

## THE SUBCLASS THAT CHANGES THE MENU — build metadata, and it cannot be scrubbed

Specs found it and I verified it, then found it is **wider than either of us had it**.

A public repository's `Cargo.toml` declares its dependencies with the **full URL of a private
repository** and a **pinned 40-character commit id** — thirteen such lines in one file alone —
and its cargo config states in plain words that the remote is private and explains the
credential arrangement used to fetch it.

I then asked how many public repos do this. **Seven of the ten**, across roughly **48 files**.
Positive and negative controls both behaved.

**This is a different problem from everything above, and it defeats one of the options.** The
prose bookkeeping can be scrubbed; **this cannot** — the URL is load-bearing, the build fetches
through it. So *scrub forward only* is not merely cheapest-and-weakest, it is **incomplete**: it
covers prose and does not touch build metadata at all. That needs its own answer — accept it,
vendor the dependency, or make the dependency repo public.

It also reframes the whole gate. Prose mentions are an accident of bookkeeping. **A dependency
declaration is a deliberate, structural, machine-readable statement that a private repository
exists at a specific address and that this public code is built from a specific commit of it.**

### On the count, since specs and I reported different numbers

Specs said three repos, I said five. **Neither is a correction of the other** — they are answers
to different questions. Five public repos carry a file *named* like lane bookkeeping; three of
those five also *contain* private repo names. Both true, different subjects. Worth stating
because the reflex was to adjudicate.

Specs also retracted two of its own attempts before they reached me: one scan over-alarmed at
~1400 hits (the private repo names are also ordinary crate names, so most hits were dependency
paths), and a narrower one **failed its positive control** — it returned zero on the very repo
this gate was opened on, because it demanded org-qualified forms while the ledger names repos as
**bare prose tokens**. Matching the topic rather than the encoding, again.

## What this is, and what it is not

**Not** a credential leak. **I have now checked all five rather than just this one**, because my
original "no keys, no MACs, no personas" was verified here and asserted everywhere — a claim
broader than its check, which is the error this gate keeps producing.

Result across all five: **no MAC addresses** (colon-form zero; every MAC-shaped hex string
triaged to either a UUID segment or a truncated artifact hash), **no keys** (the long hex strings
are ELF and image digests, quoted beside their byte sizes; the one key-flavoured passage is a
*policy* discussion recording that a raw signing key never reaches a filesystem), and **no
personas**.

**One thing does surface, and it is a different class from anything in this gate so far:** a
**trust-group identifier** appears in two of the public ledgers. It is not a key and not derived
from one — but it is a *chosen* identifier of a real trust group, and the chosen-versus-derived
distinction is yours, so I am putting it in front of you rather than filing it as clean.

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
  *five* repositories, one of which serves the public website and plainly cannot go private —
  so this option no longer covers the whole class on its own.
- **Scrub forward only, accept the history.** Cheapest. The existing exposure stays readable;
  only new material is clean. **Now known to be incomplete** — it cannot touch the build
  metadata, which is the structural half.
- **Rewrite the branch history and force-push.** Removes it from the default view. Does not
  remove it from forks, clones, or anything already cached. **Force-push is currently
  forbidden to me**, so this needs your explicit lift.
- **Stop publishing lane bookkeeping anywhere public** *(supervisor lean)*. Keep the tooling and
  the site public; move ledgers, snapshots and gate briefs out of published trees. Structural
  rather than a cleanup, applies uniformly across all five, and it is the only option that stops
  the next instance.

## Supervisor lean

**Stop publishing lane bookkeeping in public trees, uniformly across all five.** Going private
no longer covers the class now that the public website repo is in it. Scrub-forward alone does
not close it either — these repos are *where the fleet writes things down*, so the same leak
recurs the next time any lane cites a path. I would not rewrite history: it buys little against
forks and caches, and force-push carries its own risk.

**The build-metadata half needs a separate answer from you**, since no amount of scrubbing
reaches it: accept it as the cost of a private core with public consumers, vendor the dependency,
or make the dependency repo public. My lean is **accept and stop pretending otherwise** — seven
public repos build from it, the arrangement is deliberate, and the alternative is either a large
vendoring change or a visibility decision far bigger than this gate.

**Whatever you rule, it has to be dispatched** — four of the five bookkeeping repos and all seven
of the build-metadata repos are lane-owned, and I do not write to lane repos.

## Ruling syntax

"gate 23: stop publishing bookkeeping" / "gate 23: make them private" / "gate 23: scrub forward only" / "gate 23: rewrite history"
