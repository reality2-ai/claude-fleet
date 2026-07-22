# RESUME — claude-fleet

Updated 2026-07-22 (eve). Fleet ACTIVE on `/R2` — coex campaign, offline-window phase.
This repo: branch `gate-heredoc-2026-07-20`, tip pushed (ahead=0); remote `master`
deliberately lags the branch (merge = a later stake-in-ground step, Roy-gated).

## Objective

XIAO health key-10 = 0x25 (BLE|LoRa|ESP-NOW) sustained >=10s from real admitted
traffic. bit0 CLOSED on metal (86s, double-framing root cause, PREFIX-ALWAYS canon
D-20260722-10). bit2 fix built (densify 83a2a17f). bit5 = the one open blocker
(ESP-NOW RX-blind at XIAO); instrument ladder staged: ch1 RF sniff (zero-flash,
Roy fires `ssh -t tuxedo-os "sudo bash /tmp/sniff-ch1.sh"`) then v7-diag 78177f50
rxdiag counters (images pre-built + attested: XIAO 8a6dea89, D4 3b412e54,
HELD-NOT-FLASHABLE pending sniff=XIAO-RX verdict + Roy grant).

## Recent repo changes (this branch)

- `hooks/git/pre-push` sk-key scan v3: two-stage boundary + run>=40 + >=2 digits
  (8535c9d; falsifier exchange with composer, reference impl r2-composer
  tools/key-hygiene.sh 80cc2bb). Accepted edge logged in DECISIONS.md.
- DECISIONS.md carries both rounds (d54e6d3 superseded by 8535c9d).

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
