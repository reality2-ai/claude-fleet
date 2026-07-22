# Gate 5 — Alfred rig: merge to one identity, or stay two hives + relay?

**Status:** OPEN · no urgency — the rig works as-is
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
