# Gate 6 — Durable member registry: baked roster from composer's custody?

**Status:** OPEN · opened 2026-07-23 · blocks the "list-membership miss" defect class
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → "read gates/g6 and argue both sides with me"

## Why this gate exists

Four times in two days, a board failed to recognise a co-member because a hardcoded
hive-ID value in source was wrong: the blerole resolver shipped with an empty
registry, then with a list missing the XIAO; the D5 coverage claim cited stale
FR4-era IDs instead of the bench personas; and the CoC L3 path carries a stale
scaffold peer constant (0x0dcadbf8) that mismatches the scan-resolved XIAO and
drops the frame. The mechanism is fine — the *list* keeps being wrong, because
source constants are hand-maintained while the real membership lives in composer's
custody roster (the TG's actual enrolment record, which minted D5 this morning and
knows the membership). Core's roster design is ready, and composer's export CLI
is **done and verified** on branch `feat/tg-roster-blob` @7346f8a — emits the
real TG's roster (4 members: RAK, D4, XIAO, D5; 16 bytes). Ruling "adopt"
executes as: merge that branch + core wires the bake. One open sub-check:
the CLI skips a wire_id-0 placeholder member (android-fieldchecker) — composer
is confirming that's a test artifact and not the real phone member silently
dropped from every roster.

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

## Roy's reframe (2026-07-23) — membership knowledge is LEARNED

Verbatim: *"Every fresh new hive knows nothing about what is around it — the
table is empty. The only thing set is its persona. Its first task is to make
noise — I'm here — and listen for other devices nearby. If a hive has a baked-in
TG, it may well be difficult for it to learn about other TG members initially if
they are not physically nearby (or available via a relay). A fresh hive when not
in dev mode will come ready to have its TG membership set, and this will
primarily be by proximity to other TG hives. Therefore, the routing table gets a
kickstart."*

And per Roy's follow-up, **the learned roster is already canon** — R2-PROVISION:
the §2.2 join flow admits a member, Step 7 `member_announce` teaches existing
members (defined in canon; the wire opcode is a recorded follow-on), and the §3.2
identity-split rule fixes roster identity as the per-TG `mesh_pk` (never the
stable device_id). So the production mechanism needs no invention: the resolver
registry becomes the **canon roster materialized on-device** — runtime state,
kickstarted by proximity enrolment, extended by `member_announce` and
GroupHmac-verified frames as members are met (formation is already rbid-free —
core's enumeration). The rbid resolver computes rbids for *roster* members, not
compile-time constants. One reconciliation for specs: composer's blob carries u32
wire_ids while canon roster identity is the per-TG `mesh_pk` — the mapping and
its bake-time linkability hygiene need stating.

The baked roster survives as exactly what the baked persona already is: a
**dev-tier seed** — bench boards bypass live enrolment, so their member-set gets
pre-seeded from composer's custody at bake. Same blob, same CLI, demoted from
"the mechanism" to "the dev seed of the mechanism".

## Supervisor lean (reshaped)

**Adopt as dev-tier seed of a runtime member-set.** Core's registry work shifts
shape: resolvers read a runtime set; the baked blob pre-seeds it in dev builds;
production populates it via enrolment + verified frames. Composer's CLI stands
as-is. Kills the hardcoded-list class *and* aligns with the enrolment lifecycle.

## Ruling syntax

"gate 6: adopt as dev seed" (reshaped lean) / "gate 6: adopt baked-only for now,
runtime set later" / "gate 6: hold"
