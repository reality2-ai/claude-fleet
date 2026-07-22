# Decisions waiting on Roy

One current list. The supervisor adds a gate the moment it opens and removes it the
moment you rule; history lives in DECISIONS.md, not here. If this file is empty,
nothing is waiting on you.

`cat ~/Development/R2/claude-fleet/ROY-GATES.md` any time you dip in.

---

## Open now

### 1. Key-10 liveness-window design tension (from #d008 morning items)
The 8 s admit window is smaller than the 10 s default health cadence, so a fully
conformant but quiet node shows bit-dark by design. Question: per-transport windows,
or tier-keyed windows (importing the R2-ROUTE §2.4 class rule)?
**My lean:** tier-keyed, handed to specs as a spec-first task. Low urgency — the bench
runs the 4 s benchkeepalive, so nothing is currently wrong on metal.

### 2. Persistent CoC pump — do you want standing 0x25?
The passed 0x25 needed the host pump for bit0. If you want the XIAO's key-10 to show
0x25 permanently on the bench, something must keep a BLE link alive (pump service, or
the board-to-board initiator once proven). **My lean:** wait for blerole to land —
board-to-board makes the pump obsolete. Then this gate dissolves.

### 3. composer webapp/dist/manifest.json left dirty (half-corrupt regen)
Regenerate or revert? One word either way. **My lean:** regenerate.

### 4. SEN0676 radar attach (D5 water-level sensing)
Post-proof unlock from the field-node design; hardware on hand. Blocked only on your
go for the bench slot. **My lean:** after D5 is current + blerole closed — it rides
the same board.

### 5. Alfred rig complex-hive fork
Same shape as phone+XIAO (host + carrier MCU) — merge to one identity, or stay two
hives + relay? Explicitly not generalized from your phone+XIAO ruling. No urgency;
the rig works as-is. **My lean:** stays two-hives+relay until the merge-reflash op is
proven on the phone pair, then decide with evidence.

---

## Not waiting on you (for reference)
- Blerole D4 reflash + D5 sensor flash — both pre-granted sha-conditioned; in flight.
- Multi-hive / multi-TG scale-out — gated on the below-TG substrate lock you set;
  the gate-keeper is the table, not a ruling.
- §6(d) detach/reattach semantics — deferred to increment-5 build-time by your #d010.
