# Gate 5 — Alfred rig: merge to one identity, or stay two hives + relay?

**Status:** ✅ CLOSED 2026-07-23 — #d021 · Roy verbatim: *"gate 5: defer until
phone-pair merge proven"*

## RULING

Alfred stays two sovereign hives + relay (already conformant; keeps real
inter-hive relay traffic under continuous bench test). The merge question
REOPENS automatically when the §10.5 merge-reflash + #d009 secured bridge are
proven on metal on the phone+XIAO pair — Alfred then adopts a proven op rather
than pioneering it. Merge-follows-permanence stands: identity merge suits a
resident MCU; visiting MCUs stay two-hives+relay, attach/detach = a bearer
event, never an identity event.
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → "read gates/g5 and R2-COMPLEX-HIVE §3.2 with me"

## Background

The Alfred bench rig is a Linux host + carrier MCU over USB — the same host+TN-half
architecture you ruled for phone+XIAO (#d009) and the same shape as the proposed
SBC+MCU R2-Hardware. Canon now covers both shapes explicitly (R2-COMPLEX-HIVE v0.14
§3.2 "two shapes, one model"). Today Alfred runs as **two sovereign hives + ordinary
inter-hive relay** — which specs ruled conformant in July, with the fork (merge vs
stay) left explicitly to you and *not* generalized from the phone+XIAO ruling.

## Options

- **Merge (true complex hive):** MCU becomes pure transport under Alfred's identity —
  one external identity, internal bridge. Needs the §10.5 merge-reflash (defined but
  never yet performed anywhere) and, since host and MCU don't share an enclosure, the
  #d009 secured-bridge arm (keyed USB link — also never yet implemented).
- **Stay two hives + relay:** zero flash, already conformant, and the rig keeps
  exercising the *inter-hive* relay path — which is itself a below-TG behaviour worth
  keeping under test on the bench.

## Supervisor lean

**Stay split for now.** Two grounds: (1) the merge machinery (merge-reflash op +
secured bridge) should be proven first on the phone+XIAO pair, where it's the ruled
target and increment 5 will build it — Alfred can then adopt a *proven* op instead of
pioneering it; (2) a two-hive rig on the bench keeps real relay traffic under
continuous test, which a merged rig would remove. Revisit when the phone-pair merge
has happened on metal.

## Ruling syntax

"gate 5: stay split" / "gate 5: merge" / "gate 5: defer until phone-pair merge proven"
(the third is the lean, stated as a condition rather than a date)

## Roy's topology context (2026-07-23)

Two PC+MCU combinations exist: **tuxedo-os** (laptop, travels; test MCUs plugged in
"whenever I can" — itinerant attach) and **alfred** (fixed office PC, currently the
claude-fleet host). Both on Tailscale (a standing Inet tenant path between them).

**Sharpened lean — "merge follows permanence":** identity merge suits a *resident*
MCU (alfred + dedicated board someday; the SBC+MCU single-box shape); *visiting*
MCUs (the carried test boards on tuxedo) stay two-hives+relay — attach/detach should
be a bearer event, never an identity event. Rule per-pair when a resident MCU exists.
Tailscale spanning = a future Inet-leg substrate test, free once below-TG is locked.
