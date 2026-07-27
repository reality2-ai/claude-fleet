# PENDING ROY RULING — #68 vs `baked_persona`

**Status: AWAITING THE PRINCIPAL. Nothing here is canon and nothing is landed in any spec file.**

**Why this file exists.** specs authored the draft below in a session scratchpad and then found the
durability defect itself: **the scratchpad is `tmpfs`.** The only copy of a decision artifact waiting
on Roy sat in one volatile place, on no ref and no remote — *a record that cannot notice itself
disappearing*, which is the same class as several other findings from that night. Copied here by the
supervisor at specs' recommendation, because the ledger is already where
recommendations-pending-Roy live and specs does not write to this repo.

**Provenance.** Authored by **specs**. Reproduced **verbatim** below. The supervisor has not edited a
word of it — corrections are noted here instead, above the line.

**⚠ ONE STALE LINE IN THE SOURCE, FLAGGED RATHER THAN EDITED.** §C retracts the earlier cost warning
(*"the blend is cheaper than I first said; it is its SECURITY VALUE that is smaller, not its price"*),
but the closing **"WHAT IS TRUE UNDER BOTH" item 3 still carries the un-retracted wording**
*"a blend of the two inherits (A)'s cost and (B)'s hole."* **Item 3 is right about the holes and
superseded about the cost.** Left in place because **editing another lane's artifact to fix its
conclusion is how provenance is lost** — the correction belongs beside it, not inside it.

**→ specs has since accepted this and supplied corrected wording. See "AUTHOR'S CORRECTION" at the
foot of this file.** The superseded sentence is deliberately **NOT deleted**: it has been quoted
downstream (D-20260727-65, -67), and **a struck claim that remains findable beats one that vanishes.**

**Supervisor position, offered as a recommendation and explicitly refused by specs as authority:**
the reading was re-grounded after specs attacked it (the original ground cited an *indicative*
sentence, which cannot carry a prohibition), and the supervisor's recommendation of (A) was
**downgraded** once specs showed it is sound for one generation only. See `DECISIONS.md`
**D-20260727-64**, **-65**.

**Outstanding fact that decides (C):** core has been asked whether ESP32-S3 offers any immutable stage
able to hold the comparison. **(A) and (B) are judgeable without it; (C) is not.**

---

# #68 vs baked_persona — TWO CANDIDATE DRAFTS. NEITHER LANDED. Roy picks.

Author: specs. Status: **DRAFT ONLY — not canon, not committed to any spec file.**
Supervisor recommendation explicitly refused as authority; their reading is attacked in §0.

---

## §0 FIRST: THE RECOMMENDATION'S CONCLUSION SURVIVES, ITS GROUND DOES NOT

Supervisor grounded "in scope" on **preservation as an invariant of firmware reload**, citing
R2-DEVICE-LIFECYCLE §6.2 (`:179`) and the lifecycle OTA row (`:50`). **That ground fails.** §6.2 is
two sentences in two different moods:

| Text | Mood | Binds? |
|---|---|---|
| *"A firmware reload **PRESERVES** the owner-TG (and `claim_state = OWNER`)"* | **indicative / descriptive** — no MUST, no SHALL | **No** |
| *"only a full re-key is a re-persona, **permitted only from the open-TG**, … **never a network command**"* | **permissive + prohibitive** | **YES** |

The table row is the same shape: *"A normal firmware reload **preserves** the owner persona"* —
a description of what reloads do.

> **`baked_persona` does not VIOLATE the preservation sentence — it FALSIFIES ITS PREMISE.** That
> sentence was true *because* the persona lived in flash and the image did not carry it. A
> falsified descriptive premise needs **re-grounding**, not enforcement, and a finding built on it
> is refuted the moment someone observes there is no MUST there.

**Ground it on the second sentence instead** — *permitted only from the open-TG, reached by a
physical-only reset, never a network command*. A differently-baked payload accepted from `OWNER`
**is a re-persona by network command**. That is a prohibition, and it binds. **In scope, but for
the other half of the clause.**

**Their dismissal of the "no persona commit at all" escape is correct as far as it goes** (§6.2
forbids a transition, not a storage mechanism) **and there is a stronger, independent form:**

> **THE LIFECYCLE TABLE HAS NO ROW FOR THE RESULTING STATE.** Every legitimate persona change in
> §2 is `epoch++` — Claim `→ OWNER@epoch++`, Recovery `OWNER → OPEN@epoch++ → OWNER@epoch++`. A
> baked-persona reload yields **OWNER@G → OWNER@G with the identity changed and `hw_epoch`
> untouched**, because nothing writes the keystore. It is not merely an unpermitted transition —
> **it is one the lifecycle model cannot represent.**

**Confirmed and not disputed:** nothing checks it. Gate-4 (`r2-update/src/lib.rs:471`, `:476`)
compares `header.issuer_pk == ctx.tg_pk` — **the signer** — and never inspects the payload's baked
persona. A differently-baked payload sealed by the current TG passes.

---

## DRAFT (A) — IN SCOPE, with an apply-time refusal

**PERSONA-RELOAD-1 (MUST).** An update apply **MUST NOT install a firmware image whose carried
persona differs from the persona currently in force**, unless `claim_state == OPEN`. On mismatch
the apply **MUST refuse**, install nothing, and leave the in-force persona intact.

**PERSONA-RELOAD-2 (MUST).** The refusal **MUST be evaluated before activation**, and the rejecting
gate **MUST be identified in the failure record** (not merely "rejected").

**PERSONA-RELOAD-3 (MUST).** An image whose persona cannot be **located and read** at apply time
**MUST be treated as carrying a differing persona** (fail closed). *A build that hides its persona
MUST NOT thereby bypass the check.*

*Falsifier:* build two images with **different** baked persona blobs, both sealed by the current
TG; apply the second to an `OWNER` device. **The apply MUST refuse and the device MUST retain its
identity.** *Vacuity guard:* the same-blob payload **MUST** apply normally — otherwise the rule is
satisfied by refusing everything.

**COST.** The applier must be able to **read the incoming image's persona**, so the image must
**declare where its persona is**. On a rodata bake that address is a link-time artefact. **This is
R2-KEYSTORE §9.12.1's resolved-not-baked rule arriving from the opposite direction** — (A) cannot
be implemented without the region descriptor §9.12.1 already requires. *(Cheap if §9.12.1 is
honoured; otherwise (A) forces that work first.)*

**HOLE — and it is structural, not an oversight.** The check runs **in the currently-installed
firmware**. A payload that replaces the applier **removes the check in the same operation it is
meant to be stopped by**. So (A) is sound only for **one generation** unless the comparison lives
in a stage the payload cannot replace (immutable bootloader / ROM). **State that in the clause or
(A) is a guard that a hostile payload disables by definition.**

---

## DRAFT (B) — OUT OF SCOPE, with the replacement prohibition named

**Ruling.** `#68` governs **keystore-committed** personas — `claim_state`, `hw_epoch`, the
acceptance classifier. An image-borne persona is a **build-time identity assignment**, not a
lifecycle transition, so `#68` does not reach it.

**Then these MUST hold, or the exemption is a hole:**

**BAKED-SCOPE-1 (MUST).** A build carrying a compiled-in persona is a **BENCH/DEV artefact** and
**MUST NOT be distributed as an OTA payload**, nor shipped in a production profile — **structurally
excluded at compile time**, the R2-DIAGNOSTICS §6.1 pattern, **not by policy or convention**.

**BAKED-SCOPE-2 (MUST).** The exclusion **MUST be enforced by a NAMED gate in the release path**,
and that gate **MUST fail the build** — a bench-only limit that no component enforces is a
[scaffold acquiring a role by usage](R2-WIFI §3.0a).

**BAKED-SCOPE-3 (MUST).** Canon **MUST NOT** describe an image-borne persona as *preserving* or
*dropping* identity. It can also **change** it; the three outcomes are distinct and the third is
the one that matters.

*Falsifier:* submit a baked-persona build to the release path. **The gate MUST fail it.**
*Vacuity guard:* an unbaked build of the same source **MUST** pass.

**COST.** Cheapest of the two — no device-side machinery, no descriptor work, no bootloader
change. Enforcement is build/release, which an existing consumer gate can carry.

**HOLE — and it is at the boundary that matters.** **Build-time enforcement gives the DEVICE no
check at all.** Anyone able to sign an update for the TG can bake a persona, and the device
**accepts it, because nothing on the device looks**. (B) prohibits the *production* of such a
payload and is silent on its *acceptance* — so it is unenforceable against exactly the actor the
rule exists to constrain, and the §0 unrepresentable lifecycle state remains reachable by anyone
who ignores it.

---

## DRAFT (C) — (A)+(B) TOGETHER. **SURVIVES, BUT ONLY WITH ITS CLAIM DOWNGRADED.**

Added on request, with the threat analysis that decides it — and **it does not do what it looks
like it does.**

**Ask which actor each half stops:**

| Actor | (B) build gate | (A) apply-time check |
|---|---|---|
| No TG signing key | irrelevant — **gate-4 already rejects** | irrelevant |
| Honest release path, wrong artefact **by mistake** | **STOPS IT** | stops it |
| **Holder of the TG signing key, hostile** | **bypassed — they do not use the release path** | **defeated in one step** |

> **AGAINST THE ONLY ACTOR THAT MATTERS, ONE PAYLOAD DEFEATS BOTH.** A TG-key holder ships a
> single image that **changes the persona AND replaces the applier**. (B) never sees it; (A) is
> removed by the same operation it was meant to stop. **The two holes are not complementary —
> they are the same hole seen from two ends.**

**So (C) is DEFENCE AGAINST ERROR, NOT A CONTROL AGAINST A KEY HOLDER.** That is worth having —
most real incidents are mistakes, and (C) catches the wrong-artefact case twice — **but it MUST NOT
be recorded as closing the #68 exposure.** Labelling it security is how a mitigation becomes a
believed control.

**⚠ AND I MUST CORRECT MY OWN COST CLAIM FROM THE (A) SECTION:** I wrote that a blend *"inherits
(A)'s cost."* **That overstates it.** The region descriptor is **owed by R2-KEYSTORE §9.12.1
independently of any of this**, so (A)'s *marginal* cost is only the comparison logic — cheap.
**The blend is cheaper than I first said; it is its SECURITY VALUE that is smaller, not its price.**

**(C) IS CONDITIONAL ON ONE FACT NOBODY HAS YET** — core is being asked: **does this silicon offer
an immutable stage that can hold the comparison?**

- **If YES:** (A) stops being one-generation, becomes a real control against a key holder, and
  **(C) is strictly the strongest option.**
- **If NO:** (A) is one-generation **as a matter of fact on this silicon, not of design**, and (C)
  stays an error-defence. **Then (B) alone is nearly as good for less**, and the honest recording
  is *"exposure open, mitigated against error."*

**Recommendation to Roy: do not pick (C) before that answer.** It is the only one of the three
whose value is decided by a fact still outstanding.

## WHAT IS TRUE UNDER BOTH

1. **Gate-4 checks the SIGNER, never the PAYLOAD's persona.** Whichever horn Roy picks, that
   sentence belongs in canon, because the current text lets a reader assume otherwise.
2. **"Preserve or drop" is an incomplete enumeration.** A third outcome — **change** — exists.
3. **Nothing is landed and no wording is committed.** (A) and (B) are drafted to be compared, not
   merged; **a blend of the two inherits (A)'s cost and (B)'s hole.**

---

## AUTHOR'S CORRECTION — supplied by specs after the copy above was taken

**Applies to "WHAT IS TRUE UNDER BOTH", item 3.** The copy above is verbatim as at
`58f439d`; this is the author's own correction, appended rather than merged so both the
superseded claim and its retraction stay findable.

> **3.** (A) and (B) are drafted to be compared, not merged. **CORRECTED** — this item previously read
> *"a blend inherits (A)'s cost and (B)'s hole."* **RIGHT ABOUT THE HOLE, WRONG ABOUT THE COST:** the
> region descriptor is owed by R2-KEYSTORE §9.12.1 **independently**, so a blend's marginal cost is
> only the comparison logic. See (C): **the blend is CHEAPER than that line claimed and worth LESS than
> it looks — its defect is security value, not price.**

**specs' own note on why the superseded wording stays:** it has been quoted downstream, and
**a struck claim that is still findable beats one that vanishes.**

**AND THE SHAPE IS THE ONE THE FILE ITSELF ARGUES ABOUT.** specs retracted the cost claim in §C and
**left the summary line standing four paragraphs below, in the same document, in the same session** —
hours after putting the phrase *"a retraction is done when it reaches every artifact"* into use.

> **PROXIMITY IS NOT PROTECTION. A correction that does not sweep its own document has not landed.**

**The supervisor did not silently fix it, and specs confirmed that was the right call:** a preamble
beside the file preserves *that it was wrong, and when*. **A silent correction would make the record
show an argument its author never made.**
