# Gate 15 — may a join request be relayed? — THREE LANES AGREE: NO

**Status:** 🔴 OPEN — canon + security; **freezing the specs lane and four code sites**
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g15 and argue both sides with me"*

## Why this reached you

I asked core, android and specs the same question separately, told none of them to
coordinate, and told core and android not to read specs' reasoning first. **All three
said no, from three different grounds.** Two independently found the same second problem.
It converged rather than deferred, which is why it is worth your time now.

**Two specs currently contradict each other about the same frame.** The wire spec says a
join must be accepted although it carries no origin; the routing spec says any frame with
no origin must be dropped and never forwarded. The same unconditional drop sits in core's
live dataplane. Four sites are frozen on this.

## The strongest argument, in one sentence

**A relay cannot authorise a join even in principle.** The frame has no verifiable origin,
no outer authentication, and its signing key is carried *inside itself* — so anyone can
mint a validly-signed join. A relay has nothing it can check that separates a real joiner
from an attacker, and by definition the sender is not a member yet. Forwarding means every
node relays attacker-mintable, unattributable frames with a hop budget.

*(Specs, whose own argument is below, told me to give you this one instead — it is an
impossibility of capability, where its own is about consequence.)*

The second argument, independently reached: **origin-less plus relayable equals
unmeterable.** The only rate-limiting primitive canon has is a per-origin quota. It keys on
origin; a join has none. An unauthenticated frame could cross five hops with no relay able
to throttle it, because the one metering tool available needs exactly the field the
exemption removes.

## The best case FOR relaying, and why it collapsed

The frame sets a hop limit of **5**, not 1 — which looks like the designers provisioning
joins to travel. That datum troubled both specs and core, and neither would dismiss it.

**Android undercut it from its own code:** the value is documented there as *nominal*,
pinned to match a shipped test vector, because the transport it was written for is
single-hop anyway. The field that genuinely controls propagation is set to its minimum —
the frame's own routing parameters say *don't spray*.

**Specs then checked android's evidence rather than taking it**, and found the chain
stopped one step short: that comment explains why *android* chose 5, mirroring core's
value — not why *core* chose it. So I asked core, and the answer closes it at the source.

**Core's deliberate join intent is one hop, and it says so in a comment.** Its real
sovereign-join producers set the hop limit to 1, one annotated *"direct point-to-point
over L2CAP — no relay"*. The value 5 appears in exactly two places: a cross-vendor test
vector pinned for parser compatibility with no hop-budget rationale anywhere, and an older
board file where *every* frame type is 5. Across the tree, 5 occurs 24 times on all frame
types while every other value appears once. **It is the generic default.**

So the one datum that looked like provisioning turns out to be inherited boilerplate, and
the considered value — written by the lane that produces the frame — is single-hop with an
explicit no-relay note. **There is no surviving argument for relaying.**

## What you should know before ruling

**Specs weakened its own case, unprompted.** It had told me proximity justifies
trust-on-presentation. On re-reading, that clause covers only auto-pairing — the mode with
no cryptographic ceremony — and elsewhere canon *explicitly* admits joins with no physical
adjacency. Its position did not change; its grounds and confidence did. Its words: do not
present this as specs being confident on proximity.

**This is a new call, not you ratifying your own prior rulings.** Specs volunteered that
distinction. Canon-derived: the textual conflict, the hop value, the cryptographic trust
chain, and that canon admits non-proximate joins. Judgement: whether relaying is a
meaningful threat increase, and whether a guarantee we currently get *by accident* is worth
preserving *deliberately*.

**Two lanes flagged a coupling — please rule both together.** The dedup key for these
frames is a single global identifier, safe *only* because joins are not flooded. Rule them
relayable without fixing that and it becomes trivially collidable the moment the first join
travels. Either way, key and relay question move in one ruling.

**The honest alternative nobody is pushing:** two lanes noted a modest spec change — a
defined return path for a relayed join plus a properly namespaced dedup key — could make
"yes" safe. So this may be less *is it allowed* than *what would have to change first*.

**One loose end your ruling resolves either way:** core flagged, without acting, that an
older board file emits a group-management frame at the generic 5 rather than the single-hop
value the proximity path uses. Almost certainly the same boilerplate, but it is a second
producer that *would* send such a frame five hops.

## Recommendation

All three lanes: **no relay — a join is one hop.** Say it explicitly rather than leaving it
to a drop that happens for an unrelated reason.

**A post-ruling enumeration pass is owed either way**, because both answers change premises.

## Ruling syntax

"gate 15: no relay" / "gate 15: relay allowed" / "gate 15: no relay + fix the dedup key" / "gate 15: what would have to change first"
