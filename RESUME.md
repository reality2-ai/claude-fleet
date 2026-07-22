# RESUME — claude-fleet

Updated 2026-07-23 (overnight). COEX CAMPAIGN CLOSED — PASS (#d008). This repo:
branch `gate-heredoc-2026-07-20`, tip pushed (ahead=0); remote `master` deliberately
lags the branch (merge = a later stake-in-ground step, Roy-gated).

## Objective — ACHIEVED

XIAO key-10 = 0x25 sustained 41.6 s contiguous (4x the >=10 s bar), 2026-07-23
overnight under Roy's #d007 grant. Root was NEVER an RX defect: sniff (corpus-proven
filter) + console correlation refuted all three pre-registered signatures; cause =
30 s keepalive cadence vs 8 s ADMIT_W window (structural, intentional design).
Fix = benchkeepalive 8000->4000 + densify riding (core bee0e996); hive images
XIAO d12ddcc8 / D4 d818ffda; composer flashed under per-op .fleet/flash-authorization
grants, banners app@0x20000 + personas intact; 0x24 sustained 94.2 s pre-pump; CoC
pump at fresh XIAO BLE addr lit bit0 => 0x25. v7-diag images (8a6dea89/3b412e54)
ARCHIVED unflashed. Boards left meshing, soak logger + tuxedo keep-awake running.
Morning items for Roy: see DECISIONS.md #d008 (window design tension, persistent
pump, composer manifest.json dirty file, blerole flash slot).

## Recent repo changes (this branch)

- `hooks/git/pre-push` sk-key scan v3: two-stage boundary + run>=40 + >=2 digits
  (8535c9d; falsifier exchange with composer, reference impl r2-composer
  tools/key-hygiene.sh 80cc2bb). Accepted edge logged in DECISIONS.md.
- DECISIONS.md carries both rounds (d54e6d3 superseded by 8535c9d).

## BLE board-to-board (b) — pre-metal COMPLETE, queued behind diag campaign

Core increment 2 landed dfr1195-fw-blerole c01c9db9 (08fa87ed threads
profile.ble_role into ble_task + boot-print; c01c9db9 initiator scan-dial:
captures first valid-R2 acceptor BdAddr, N=5 empty windows => hive_id fallback;
cocbench BENCH_ADDR cfg-split). Composer delivered D4 initiator blob sha256
a55810f9d25e... (48B RPF1, b[6]=0x01, b[4]=0x02 Bridge ground-truthed vs
e4031efd:3347 — b[6] sole behavioral delta), on alfred:~/d4-initiator.role;
gen-role CLI = composer 4a4b0cb. XIAO gets NO blob (absent = acceptor-only,
bit0-proven role preserved). Bake input: DFR_ROLE_PATH=~/d4-initiator.role.
DONE bar = seen-on-metal (boot-print + scan-to-connect handoff); flash rides a
LATER Roy per-op grant, never conflated with the 78177f50 diag flow.

## Fleet state

#d006 standing (drain-first, ownership registry, report-don't-act) — working.
All five lanes completed the offline-window slate 2026-07-22 eve; Roy standing
order active: when idle, commit+push everything (ahead=0 vs ls-remote) + README/
docs currency pass, public-hygiene-gated. Android junit execution bench-gated
(no local JDK17 — ruled no install). Known defect: fleet mail queue can LOSE
queued messages (2 suspected losses this session) — re-verify queued sends landed.

## Verification

Latest full local pass (2026-07-21): smoke 213/213; robustness 39/39; window
allocation 93/93; liveness 12/12; faculty 99/99; ask isolation 59/59;
multi-workspace 6/6; config 10/10; commit-msg 9/9; firmware gate 63/63.
Pre-push v3 pattern: six-fixture control run green 2026-07-22 (production-extracted).

## Next action

On Roy's return: sniff verdict -> relay to core/hive -> either flash grant flow
(XIAO-RX-side: composer two-party SHA verify, then run-6 with counter split) or
re-aim at D4-TX diag. Before starting agents elsewhere run `fleet doctor`.
