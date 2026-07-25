# Gate 23 — our working records are published in five public repositories

**Status:** 🔴 OPEN — no secrets exposed; internal structure is
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g23 and verify the counts yourself"*

## READ THIS FIRST — it is no longer the biggest thing in this gate

The vendoring-name and dependency-URL material below is real but structural. **The answer to the
invented-versus-captured question changed the gate's centre of gravity, and this part is about
your home network.**

The bench-flash lane answered plainly and against itself: **two of the three groups are CAPTURED,
and they are its rig.** Not documentation examples — an operational test log with measured timings.
Specifically: **a named home wireless network, four real hosts at specific addresses on that
subnet, a mesh-VPN presence, per-host service ports, and real sequentially-named boards.**

**And it is not only in the specification files. It is in that lane's own repository — which is
public, and fully pushed.** I verified: the repo's visibility is public, the file is tracked, it
carries nine private-range addresses, three mesh-VPN references and a network name, and the lane
is at zero commits ahead of its remote. **So this is live right now, not pending a push.**

That is a different class from everything else in this gate. Repository names and commit ids are
*development* structure. **A named home network with host addresses is the physical location and
topology of where you live and work**, published under the org's name.

**Nothing has been scrubbed and I have told the lane to keep it that way** — for the reason
established earlier: a scrub destroys the evidence needed to establish what was captured. The lane
volunteered the finding about its own tree rather than confining its answer to the file I asked
about, and it is holding for your go-ahead. It can enumerate the exact file-and-line set privately
on your word.

**The third group is unowned.** The electrical-design lane verified negatively that it is not
theirs; the bench-flash lane says the subnet is not its dev network either. Under fail-closed it
stays real with no owner identified. **If it is yours, you are the only one who can say so.**

**What I need from you on this item, in priority order:** (1) go-ahead to enumerate privately,
(2) a scrub decision for captured values, (3) an answer on the third group. It sits ahead of every
other half of g23.

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
and its cargo config states in plain words that the remote is private. **I said that file
"explains the credential arrangement", which reads worse than it is — specs read the file rather
than trust my description, and it was right to.** It is five comment lines and one setting: it
says fetching reuses the git credential helper already present on dev machines and CI so no
separate deploy key need be minted. **No token name, no path, no key location.** Nothing there to
upgrade the finding.

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
And unlike prose it is **durable**: it is load-bearing, so it cannot drift out on its own, and
every future consumer of that repo re-states it.

### Why the two halves have different canon status — and where canon simply stops

The identifier and the dependency URL are **not** the same problem wearing different clothes, and
the difference is in the text rather than in convenience:

- The secrets canon defines a real value as one that *"is derived from, or uniquely identifies, a
  real device, persona, deployment, or operator"*, then lists categories under that umbrella.
  Trust-group identifiers are **named** in that list.
- A dependency URL is in **no category**. A public code-host name identifies no device, persona,
  deployment or operator; an organisation/repository path is source-control structure; a
  40-character revision identifies a commit, not a person or a board. The infrastructure category
  does list *hostnames* flatly — but the umbrella disciplines the list, and a public third-party
  code host is not a hostname that identifies a real deployment. **That is the load-bearing step,
  so I am showing it rather than asserting the conclusion.**
- **The fail-closed clause does not close this gap.** Read without a bound it would make every
  unlisted string secret-until-certified, which would swallow the dependency URLs too — and
  contradict the umbrella definition. It governs the **provenance of a value already inside a
  custody category**; it does not create categories. Specs bounded its own earlier argument on
  this point *before* it could be turned against the accept it then supported, which is the
  reason the split holds.

**And that step now has evidence behind it, of the strongest kind available — canon-internal.**
Specs measured the specification corpus; I re-ran it wider and with a nonsense-scheme negative
control that correctly returned nothing. Across 234 tracked documents: **87 URLs spanning 50
distinct public hostnames**, the public code host appearing 15 times, alongside standards bodies,
component vendors, academic archives and news sites.

**Under the flat reading, every one of those is a real value — and real values must not appear as
a literal in any tracked file of any repo. The flat reading puts the specification corpus in
violation of its own rule.** That is not a competing interpretation to be weighed; it is a
refuted one.

Two precisions, both specs', both worth keeping:

- **This refutes the competitor; it does not prove the umbrella reading was intended.** It leaves
  that reading standing unopposed, which is enough to act on and is not the same as positive
  proof. The weaker true statement beats the stronger convenient one.
- **The rule file itself cites no URL** — I checked, zero. So this is a collision with the corpus
  the rule *governs*, not with its own text. "Self-refuting" would have been the better line and
  a false one.

**One genuine subset should not be laundered by that argument, so I separated it** — and it
turned out to be a live finding rather than a caveat. Most of those 50 hosts are third-party
documentation and plainly identify no R2 deployment. But private-range addresses, service
hostnames and local-network device names are the class the infrastructure category actually means,
and the reductio does not clear them.

Specs measured that subset, with controls. Most of it **is** cleared as synthetic-by-construction —
vendor default gateways, protocol defaults, documentation examples, generic schematic names.
Vendor and protocol constants identify no deployment. **Three groups are not cleared**, and all
three have *the shape of capture rather than invention*: two private subnets each carrying several
specific hosts (one lab-shaped, one home/office-shaped), and a set of sequentially-named boards
with the shape of a rig roster. Not a documented default among them.

**Whether those were invented or captured is answerable only by whoever ran the hardware**, and
fail-closed treats them as real meanwhile. It has deliberately **not** been remediated, for a
reason I would not have thought of: **a scrub would destroy the evidence needed to answer the
question.** Four of the affected files are canonical specs, so edits are gated anyway. I have
asked the hardware lanes the invented-versus-captured question; nothing gets allowlisted that
turns out to have been captured.

### The one line from all of this that belongs in front of you

A third blind spot turned up in the same pass: a hostname of the form `r2-<8 hex>.local` embeds
what is almost certainly a **derived device identifier** — and the gate cannot see it. I ran the
pattern myself: the mDNS form returns **no match**, while the *same value written as a labelled
field* matches, and a negative control returns nothing. So the detector discriminates fine; the
hostname form is **structurally invisible** to it.

That makes three, and they share one shape:

> **This detector finds *labelled* identifiers. It is blind to identifiers *embedded in a
> structured name*** — a dashed UUID, a contiguous hex run (deliberately, to protect test
> vectors), and now a hostname.
>
> **A green from this gate is evidence about labelled identifiers only.**

That sentence is the honest scope of every clean identity scan we have run, and it should sit
wherever those scans are cited.

**Stated honestly rather than claimed: canon does not adjudicate repository names either way.**
This is the **absence of a category**, not an exemption written for them. If you want
source-control structure in custody, that is a **canon addition**, not a reading of the present
text — and you should know which of the two you are doing when you rule.

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

**One thing does surface, and canon already governs it — I asked you the wrong question about
it.** A **trust-group identifier** appears in two of the public ledgers. I put it to you as a
*chosen-versus-derived* judgement call. **It is neither a judgement call nor that distinction.**
Specs cited the secrets canon; I read the clauses myself and they say:

- Trust-group identifiers are **named in the custody set**, when they come from a real
  persona or board.
- The governing test is **real-provenance versus synthetic-by-construction**, and a value is real
  if it was *"chosen from, **or** derived from, real hardware/persona/deployment"*. **Chosen is on
  the real side.** My framing offered you a distinction canon does not draw.
- **"Prior public exposure does not make a value synthetic"** — which forecloses in advance the
  *it is already out there* argument this gate would otherwise attract.
- **Fail-closed:** a value whose provenance is *unconfirmed* is **treated as real until
  certified**. So the burden runs the other way from how I presented it.

I checked the synthetic-fixture allowlist: **this identifier is not in it.** Under the
fail-closed clause it is therefore treated as real, and real values **must not appear as a
literal in any tracked file of any repo**.

**Two consequences, and the first breaks an option outright:**

1. **Making the repos private does not remediate this item.** The requirement says *any repo*,
   not *any public repo* — a private repo tracking it is the same violation. Option one fixes the
   other classes and leaves this one standing.
2. **The route to clean is an action, not a judgement.** If that trust group is the bench/demo
   group, it is certifiable synthetic-by-construction and belongs in the allowlist. If it
   identifies a real deployment, it does not. **That is a question of *which* group, answerable
   by its owner — and it is the entire decision.**

**But that route is weaker than I described it, and the lane that owns the allowlist said so
against its own interest.** The certification scanner matches **contiguous** hex runs after an
identity label. A trust-group identifier in UUID form is `8-4-4-4-12` with dashes. I ran the
compiled pattern myself against three inputs, with a negative control that correctly returned
nothing:

- **UUID form → one match, the first 8 hex digits only.** The other 24 are never scanned.
- **The same value written as one 32-character run → no match at all.** *(I reported this as
  "worse still". It is not a defect — see below.)*

Two consequences, and the second is the one that bites here:

- **Allowlisting a UUID-form value certifies a fragment, not the value** — and it silences any
  other identity sharing those first 8 digits.
- **Two different trust groups sharing a first segment are indistinguishable to this gate.** So a
  green is **not evidence about *which* group a file carries** — which is exactly the question
  the route-to-clean turns on.

**My "worse still" was wrong, and the correction inverts the fix.** The scanner deliberately
refuses to match a hex run longer than the widths it looks for — its own comment says a 64-character
test vector "must not light up as four identities". It is an anti-false-positive guard, not a gap,
and I read an intentional design as a bug.

**And the cost figure I then gave you was wrong too — both of us, in the same way.** We each
counted **raw literals**: 71 at 32 characters, ~250 at 64. My number matched specs' exactly, and
*that agreement is why neither of us questioned it* — we had run the same method, so it could not
have disagreed. Precisely the rule this gate produced, caught for the fourth time today.

The scanner requires an identity **label** adjacent to the hex. **A bare test vector in a data
table has no label and is therefore not flagged even at the widened width.** So the flood I warned
you about does not exist on this corpus.

Specs re-measured by widening the compiled pattern and reported a true delta of **zero**. I ran it
independently and **can confirm the mechanism but not that exact figure**: a planted *labelled*
32-character value scores 0 on the current pattern and 1 on a widened one, while an *unlabelled*
one scores 0 on both — so the label condition is doing the work, exactly as specs says. My own
widening also *lost* six existing matches, which means I widened the pattern clumsily rather than
conservatively. **I am reporting that rather than quoting a delta I did not cleanly obtain.** The
widening should be done properly before anyone relies on a number for it.

**What this changes:** "widening by width is harmful" is **refuted** — it is *inert* here, and
cheap insurance against a future labelled value. The conclusion survives on a better reason:
**widen by shape because only the dashed form catches the UUID case at all** — the 37 candidates,
which is the actual gap. **The best fix is both**, and neither of us proposed that while each was
defending a single option.

The instrument was **held, not fixed**, and I agree with that: widening it changes what the gate
flags fleet-wide and moves the candidate count *while a gate about a UUID-form identifier is in
front of you*. Changing the instrument mid-ruling pre-empts the ruling. It is documented in the
file's header instead — non-normative and invariant across every outcome you might choose.

Worth knowing, because it is the best evidence the instrument works within its stated width:
**the explanatory note tripped its own gate on first draft.** A literal example identifier written
into the header raised the candidate count by one — an identity-shaped literal in an identity
context, added *by the note explaining the hazard*. Rewritten schematically; count restored.

**One standing consequence, fleet-wide and not confined to this gate: the identity scanner reads
commit messages.** Prose *about* an identity defect can permanently add a candidate to the backlog
it documents — and history is not rewritable here. Commit messages about identity work must be
written as though they were scanned files, because they are. That is now three self-trips in one
day: an explanatory note, a commit message, and a stale figure quoted from an earlier run.

When you rule, widening the matcher **by shape** and **re-baselining** is queued. The widened matcher will
surface segments no previous pass has ever scanned, so **the new count will not be comparable to
the old one and must not be read as a regression.**

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

- **Make the repos private.** Needs no rewrite. But it now covers **less than half the gate**:
  one of the five serves the public website and cannot go private; the build metadata is
  unaffected; and per the secrets canon a private repo tracking a real identifier is **the same
  violation** as a public one.
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
