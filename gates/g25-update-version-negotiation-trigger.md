# g25 — does the pre-release premise still hold?

**Opened 2026-07-27 by supervisor, from a metal result.** One judgement. Canon wrote the
trigger down in advance; the only question is whether it has fired.

## What is NOT in question

**The version itself needs no ruling.** Canon is explicit: **v3 at 137 bytes is canonical**
(R2-UPDATE §2.2, layout §5, reject table §3.1.2.3), changed at spec v0.46 on 2026-07-10.
The pusher was conformant; the **firmware's vendored copy is stale** at v2/123, seventeen
spec revisions behind. Core is re-vendoring. No operator decision applies to a canon read.

**And the board was right.** §2.2: a receiver accepts *only* the current header version and
rejects any other, **checked before the signature** — no sender fallback, no receiver
dual-accept, no dual-version support. So the rejection firing before the signer check is
**exactly the specified order.** The board behaved conformantly; the defect was entirely the
stale copy.

## What needs you

Canon **deliberately defers** version negotiation, and states the condition for revisiting:

> *"This is acceptable pre-release (no v1 packages are deployed in the field). If/when the
> fleet is deployed and a future header bump must coexist with in-flight old packages, add
> explicit version negotiation then; for now, cutover is canon."*

**The premise is "no old packages deployed."** Tonight two divergent copies were found
**running on real hardware** — one on a board, one in the pusher — and the mismatch blocked
the entire update path in both bearers.

**Whether that trips the trigger is a judgement about deployment status, not a canon read.**
A bench board is not "the field", so a reasonable person could call this still pre-release.
But the failure mode canon was protecting against — a sender and a receiver disagreeing
about the format, in flight — is precisely what happened.

**`gate 25: still pre-release`** — cutover stays canon, and re-vendor discipline is what
keeps the copies together. Cheaper, and consistent with a bench-only divergence.

**`gate 25: add negotiation`** — spec the negotiation now, before more boards diverge. Costs
spec work and receiver complexity, buys immunity to exactly this class.

## The sharper finding underneath, which needs no decision

Canon **already required a test for this exact case.** §2.2 names the cross-version behaviour
as a **required KAT, not an assumption**, and lists **"a v2 parser's handling of a v3 header"
as the first item** that must be proven before that milestone can be called frozen. **The
milestone is still open. The test was never built.**

So **its first execution was a blocked update path on metal at one in the morning, instead of
a red test in CI.** The drift was not the defect — **the missing drift-detection test was.**
The skew is what an unbuilt KAT looks like when it finally runs.

Specs is authoring all five required items now, with the **signed-byte-coverage** one
prioritised, because it is the only one on the list that can **fail silently**: a wrong
version is loud — the board named it — whereas a signature covering the wrong byte range
verifies successfully at both ends while protecting less than we believe, and nothing reports
it.

## Ruling syntax

`gate 25: still pre-release` · `gate 25: add negotiation`
