# RESUME — claude-fleet

Updated 2026-07-21. The fleet is intentionally stopped; this worktree is clean and pushed
after the current change.

## Current state

- `.fleet/fleet.toml` is the sole membership authority. Each workspace gets an isolated
  tmux socket and state directory, so `/R2` and `/R2-codex` can run different fleets.
- Default startup is one supervisor plus one writer per configured repo. Refuters,
  twins, watchdogs, and standbys are opt-in.
- Prompts are terse: `skill/COMMS.md`, `skill/SUPERVISOR.md`, and the workspace primer
  contain only active rules. Git retains superseded detail.
- Doctor evaluates the current workspace only and ignores stopped historical state.
- Mail/state IO fails closed on unsafe paths. Off-thread asks use isolated read-only
  checkouts and cannot take over a live worker.
- The pre-push scanner rejects real secret assignments while allowing explicit
  `R2-SCRUBBED`, `REDACTED`, and `PLACEHOLDER` sentinels.

## Verification

Latest full local pass: smoke 213/213; robustness 39/39; window allocation 93/93;
liveness 12/12; faculty 99/99; ask isolation 59/59; multi-workspace 6/6;
config 10/10; commit-msg 9/9; firmware gate 63/63.

## Next action

Await a new objective. Before starting agents, run `fleet doctor`, confirm the intended
workspace manifest, and fetch each repo. Do not merge preserved safety/WIP branches merely
because they exist; inspect intent and tests first.
