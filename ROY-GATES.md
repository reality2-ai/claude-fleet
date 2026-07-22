# Decisions waiting on Roy

One current list. Supervisor adds a gate when it opens, removes it when you rule;
history lives in DECISIONS.md. Empty file = nothing waiting on you.

**To interrogate a gate with AI help:** `cd ~/Development/R2/claude-fleet && claude`
then: *"read gates/g3 and argue both sides with me"* — a fresh Claude with the brief,
the ledger, and the repo. Or open the brief's GitHub link from any browser and paste
it into claude.ai.

**To rule:** tmux window 0 (supervisor), type e.g. `gate 3: regenerate`. Ruling
syntax is at the bottom of every brief.

---

| # | Gate | One-liner | Lean | Brief |
|---|------|-----------|------|-------|
| 1 | Key-10 liveness window | 8 s window < 10 s cadence — quiet node reads dark by design | tier-keyed, spec-first | [g1](gates/g1-key10-liveness-window.md) |
| 2 | Persistent 0x25 | standing BLE green needs pump or initiator | wait — blerole dissolves it | [g2](gates/g2-persistent-pump.md) |
| 3 | composer manifest.json | dirty generated file | regenerate | [g3](gates/g3-composer-manifest.md) |
| 4 | SEN0676 radar attach | when does D5 get the real sensor | after blerole, before scale-out | [g4](gates/g4-sen0676-radar.md) |
| 5 | Alfred rig fork | merge to one identity vs stay two hives + relay | stay split until phone-pair merge proven | [g5](gates/g5-alfred-rig-fork.md) |

GitHub: https://github.com/reality2-ai/claude-fleet/tree/gate-heredoc-2026-07-20/gates

## Not waiting on you
- Blerole D4 reflash (iter 2, L3 fix) + D5 sensor flash — pre-granted, in flight.
- Multi-hive / multi-TG scale-out — gated on the below-TG substrate lock (the table
  is the gate-keeper, not a ruling).
- Waveform-as-sentant implementation — core owns it under your layer ruling.
