# Gate 15 — may a sovereign JOIN traverse the mesh relay path?

**Status:** OPEN · blocks the specs lane

Three lanes reached an independent **NO**, with the capability argument leading (android's
formulation, adopted on specs' own recommendation). The one datum that favoured relaying —
a TTL value read as deliberate — was **undercut at its source**: it is a nominal comment
mirroring a shipped value, with the confirming question to core still pending. Specs
declined to record it as "refuted" until that answer lands, which was correct.

**Frozen until ruled** — four sites, not three: three named sites including the live
dataplane, plus orphan 5 found later. The `GROUP_MGMT` msg_id-only dedup key is **dead code**
until this is ruled (`r2-dataplane/lib.rs:874-878`); key and admission are to be fixed
*together*, afterwards. Deliberately **not patched** in the meantime — a patch that assumes a
ruling reads as settled.

**A post-ruling enumeration pass is owed either way**, because both answers change premises.

Sources: `r2-specifications/RESUME.md` (READ FIRST block), `r2-core/RESUME.md:97-99`.
