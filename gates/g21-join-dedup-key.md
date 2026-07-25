# Gate 21 — the dedup key: CANON ALREADY RULES IT. One narrow question survives.

**Status:** 🟡 OPEN but much smaller than I first wrote — see the correction below
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g21 and R2-WIRE §8.2"*

## Correction first — my earlier brief was wrong, and Roy caught it

I opened this gate offering three options for "what should the dedup key be", with a
recommendation. **Roy said: check canon first.** Canon had already decided it, **normatively,
in v0.68** — and my brief would have had him overrule landed canon without either of us
knowing that is what he was doing.

**R2-WIRE §8.2, as canon actually states it:**

- **Key: `(msg_id, origin_hive_id)` — for the origin-bearing types ONLY** (`EVENT`, `REPLY`,
  `HEARTBEAT`).
- **`GROUP_MGMT` dedups on `msg_id` ALONE — NORMATIVE.** It is the one type exempt from
  ROUTE-ORIGIN-1, carries no origin, and the composite key is **unsatisfiable** for it.
- A receiver **MUST NOT fabricate an origin** to satisfy the composite key — a fabricated
  origin is exactly the false-origin §9.6 forbids.

So: there is **no key to choose**, my `(sender_pk, sequence)` lean is moot, and **the
type-aware rider is already canon** — "must not fabricate an origin" is the same rule stated
from the other side.

## What actually survives — and it is a real question

§8.2 gives its own soundness condition explicitly:

> *"The narrower key is sound here **because `GROUP_MGMT` is not flooded**."*

**Roy's g15 ruling changed how far these frames travel** — from strictly zero hops to
zero-or-one-carried. So the question is not *what is the key*, it is:

**Does at-most-one-carry disturb the premise the existing key's soundness rests on?**

My reading: **no.** One intermediary is not flooding, and specs' terminate-and-re-originate
mechanism makes a carried join **origin-bearing** at the carrier — so it leaves the exempt
class entirely and takes the normal composite key. The exempt narrow key applies only to the
direct, origin-less case, which is exactly the case canon scoped it to.

But that is *my* reading of a soundness rationale whose premise moved, and this is precisely
the orphaned-conclusion class we have been chasing all week: **a conclusion that is still
correct while the premise it cites has quietly changed.** It deserves an explicit look rather
than an assumption.

## What is NOT yours — specs owns these

- **`R2-ROUTE §3.8 :661-662` contradicts `R2-WIRE §8.2`.** The route spec drops a frame with
  an empty route stack; the wire spec says `GROUP_MGMT` dedups on `msg_id` alone and must be
  accepted. That is a canon-internal contradiction, not a decision for you.
- The same shape in **core's dataplane dedup path** and the one-edit-away site in **android**.
- Re-running the enumeration with the encoding-aware method once this settles.

## What I am asking you for

Only this: **confirm the soundness rationale holds under your g15 ruling**, or say you want
it re-examined. If it holds, this gate closes and specs fixes the §3.8 contradiction as
ordinary canon maintenance.

## Ruling syntax

"gate 21: rationale holds, close it" / "gate 21: re-examine the soundness premise"
