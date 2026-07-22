# Gate 6 — Durable member registry: baked roster from composer's custody?

**Status:** OPEN · opened 2026-07-23 · blocks the "list-membership miss" defect class
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → "read gates/g6 and argue both sides with me"

## Why this gate exists

Three times in one day, a board failed to recognise a co-member because a hardcoded
hive-ID list in source didn't contain the right value: the blerole resolver shipped
with an empty registry, then with a list missing the XIAO, and the D5 coverage claim
cited stale FR4-era IDs instead of the bench personas. The mechanism is fine — the
*list* keeps being wrong, because source constants are hand-maintained while the real
membership lives in composer's custody roster (the TG's actual enrolment record,
which minted D5 this morning and knows all 5 members).

## Core's proposed durable shape

A **persona-adjacent baked roster**: a new `DFR_ROSTER_PATH` build input (mirroring
the persona/role bake mechanism) bakes composer's roster export — the list of member
hive IDs — into the image. BLE and LoRa resolvers build their registries from it.
The hardcoded `KNOWN_HIVE_IDS` list and one-off peer constants retire.

- Mint a board → composer updates custody → next bake carries it → every board
  resolves the newcomer. Zero source edits; the defect class dies.
- Separate `.roster` blob (not inside the persona) so membership churn never forces
  a persona re-mint.
- Brick-safe by construction (baked at build; no NVS writes).
- Future door: a signed roster *descriptor* could later update membership over the
  air without reflash — same pattern as the sentant-config door.

## The three sub-questions

1. **Separate blob vs in-persona?** Lean: separate — membership changes more often
   than identity; coupling them forces re-mints.
2. **Roster cap?** 5 members today, 9-board TG plausible soon, "numerous DFR1195s +
   XIAOs" on the shelf. A u32 per member is 4 bytes — a cap of 32/64 costs nothing;
   pick generous.
3. **hive_id only, or (hive_id, pubkey)?** Core believes hive_id suffices for rbid
   resolution (session keys derive from the shared TG key + member id; per-member
   Ed25519 stays where it lives today). Lean: hive_id-only until something needs the
   pubkey — smaller blob, weaker coupling.

## Cost of saying no

Every new board or persona change is another hand-edit to source constants on every
image, and today proved how reliably that goes wrong. The alternative is living with
the miss class and catching it via falsifier instruments each time.

## Supervisor lean

**Adopt**: baked roster, separate blob, generous cap, hive_id-only. It moves the
source of truth to where the truth already is (custody), kills a proven defect
class, and both future doors (OTA descriptor, multi-TG rosters) stay open.
**Would refute the lean:** if the derivation reconcile (blerole's current blocker)
reveals per-transport keying that needs more than hive_id per member, question 3
flips to (id, key-material) and the blob design needs a second look before adopting.

## Ruling syntax

"gate 6: adopt" (lean) / "gate 6: adopt, but …" / "gate 6: hold until derivation
reconcile lands"
