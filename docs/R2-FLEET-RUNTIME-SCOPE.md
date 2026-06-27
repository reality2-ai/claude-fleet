# R2 Fleet Runtime Scope

**Status:** scoped proposal, 2026-06-28.

This scopes a fleet-native runtime: something that can give the useful desktop
affordance of tmux, but is built around AI fleet semantics rather than terminal
panes.

## Problem

`claude-fleet` currently uses tmux as the process substrate. That made the first
fleet cheap and inspectable, but tmux only knows about windows and keystrokes.
The fleet now needs first-class concepts tmux cannot enforce:

- one writer per repo;
- adversarial read-only twins;
- clean fail-over promotion;
- provider quota/exhaustion state;
- handoff state and provenance;
- mobile/web visibility;
- process supervision that is aware of agents, not just terminals;
- eventual worktree isolation for non-writer twins.

The target is not "tmux clone". The target is an agent runtime with a terminal
view.

## Goals

- Replace tmux as the source of truth for fleet runtime state.
- Keep a terminal attach/view that feels at least as convenient as tmux on a
  desktop.
- Model agents as typed actors: `writer`, `standby`, `takeover`, `supervisor`,
  `adversary`.
- Enforce one writer per repo at the runtime level.
- Launch Claude/Codex with provider-specific flags that match the actor role.
- Store an append-only event log suitable for audit, recovery, and later graph
  memory ingestion.
- Support provider-neutral commands: `status`, `brief`, `ask`, `send`, `pair`,
  `handoff`, `down`, `attach`.
- Keep `claude-fleet` working as a compatibility shim during migration.

## Non-Goals For V1

- No full R2 self-hosting dependency. The runtime must run when R2 app services
  are broken.
- No distributed multi-host scheduler in the first cut.
- No general shell automation product.
- No full Anthill graph implementation in the runtime MVP.
- No arbitrary mobile shell access.
- No replacement for Claude/Codex provider CLIs themselves.

## Architecture

### `r2-fleetd`

Rust daemon responsible for:

- spawning provider processes under owned PTYs;
- tracking process state, exit status, heartbeats, and provider exhaustion;
- persisting state and an event log;
- enforcing role policy before launch and handoff;
- routing typed messages between agents;
- exposing a local API over Unix socket first, then WebSocket/HTTP for the hive.

Rust is the first implementation language because the immediate problems are
local process control, typed state, file permissions, repo/worktree ownership,
and durable event handling. Elixir/OTP remains a good later fit if the runtime
becomes distributed, but the first useful artifact should be a single-host Rust
daemon.

### `r2-fleetctl`

CLI compatible with the current operator shape:

```sh
r2-fleetctl up
r2-fleetctl status
r2-fleetctl brief
r2-fleetctl pairs
r2-fleetctl ask core "..."
r2-fleetctl send core "..."
r2-fleetctl handoff core core-codex --stop-source
r2-fleetctl attach core
```

The old `fleet` command can become a shim that calls `r2-fleetctl` when the
daemon is present and falls back to bash/tmux otherwise.

### `r2-fleet-tui`

Desktop terminal UI:

- pane-like live views of agent PTYs;
- pair view: writer plus read-only adversarial twin;
- role/provider/status badges;
- inbox and handoff panels;
- quick commands for ask/send/handoff/down;
- keyboard-first operation.

This is the "tmux but fleet-aware" surface. It should not own runtime state.

### `r2-fleet-web`

Mobile/web companion:

- status and brief first;
- authenticated operator actions;
- no arbitrary shell;
- command allowlist mapped to the daemon API;
- eventual Reality2 trust-group identity and WASM hive integration.

This extends `docs/R2-FLEET-CONTROL-HIVE.md`; it should not be required for the
runtime MVP.

## Data Model

Minimum durable records:

- `Agent`: id, provider, role, repo, cwd/worktree, status, session ids, policy.
- `RepoLease`: repo id/path, writer agent id, standby ids, lease epoch.
- `Event`: append-only stream of launches, exits, messages, handoffs, policy
  decisions, exhaustion events, file claims, test results, operator actions.
- `Message`: typed ask/send/handoff packets with delivery state.
- `ProviderState`: rate limit, hard exhaustion, model, launch flags, last error.
- `HandoffPacket`: source, target, resume excerpt, git context, claims, task.

SQLite is sufficient for v1. The event log should be exportable to Anthill later.

## Policy

The runtime enforces these rules:

- A repo can have at most one writer lease.
- Claude workers are normally writer leases.
- Codex twins are normally adversarial read-only standbys.
- A standby can inspect, question, and propose patches/tests, but cannot launch
  with write permissions.
- Handoff to a standby stops or demotes the current writer before starting the
  target as writer.
- Provider hard exhaustion triggers a handoff recommendation, not a retry loop.
- A provider UI is never the control plane; fleet state is.

## Provider Adapter Contract

Each provider adapter must define:

- launch command for writer;
- launch command for read-only standby;
- launch command for takeover;
- resume semantics;
- hard exhaustion signatures;
- transient throttle signatures;
- transcript/session discovery if available;
- safe shutdown behavior.

V1 adapters: Claude Code and Codex CLI.

## Milestones

### M0: Spec And Compatibility Harness

Deliverables:

- this scope doc accepted;
- JSON schema or Rust types for `Agent`, `RepoLease`, `Event`, and `Message`;
- fixture tests that replay current `claude-fleet` scenarios.

Exit criteria:

- current smoke/robustness cases are mapped to runtime requirements;
- no dependency on R2 services.

### M1: Single-Agent PTY Runtime

Deliverables:

- daemon can launch one Claude or Codex agent under a PTY;
- `status`, `attach`, `down`, and event logging work;
- exhaustion classifier works from PTY output.

Exit criteria:

- can replace `tmux new-window` for one member;
- attach is reliable enough for daily inspection.

### M2: Fleet State, Messaging, And Roles

Deliverables:

- manifest loading;
- multiple agents;
- typed roles;
- `ask`/`send` message routing;
- read-only standby launch;
- one-writer-per-repo lease enforcement.

Exit criteria:

- can run Claude writer plus Codex adversarial standby for one repo;
- runtime refuses a second writer for the same repo.

### M3: Handoff And Fail-Over

Deliverables:

- handoff packet generation;
- standby promotion to writer;
- source writer stop/demotion;
- provider exhaustion recommendations;
- compatibility `fleet handoff` path.

Exit criteria:

- hard Claude exhaustion can move one repo to Codex without concurrent writers;
- role transition is visible in event log and CLI status.

### M4: TUI Replacement For Daily Desktop Use

Deliverables:

- pane-like agent views;
- pair dashboard;
- inbox/handoff panels;
- keybindings for common commands.

Exit criteria:

- normal desktop use no longer requires tmux;
- tmux fallback remains available.

### M5: Worktree Isolation

Deliverables:

- per-standby git worktree allocation;
- cleanup/reuse policy;
- diff handoff from standby proposal to writer;
- conflict-safe promotion.

Exit criteria:

- adversarial twins physically cannot modify the writer's working tree;
- standby proposals can be reviewed/applied intentionally.

### M6: Mobile/Web Hive

Deliverables:

- local web UI;
- authenticated command allowlist;
- brief/status/inbox views;
- ask/send/handoff/down actions;
- audit trail for mobile actions.

Exit criteria:

- Termius is no longer required for basic mobile supervision.

## Migration Plan

1. Keep `claude-fleet` as the operator tool.
2. Build `r2-fleetd` behind an opt-in flag.
3. Route one non-critical repo through the daemon.
4. Add compatibility commands until `fleet status`, `brief`, `pair`, and
   `handoff` can read daemon state.
5. Move daily operation to daemon/TUI.
6. Retire tmux as source of truth, but keep a fallback attach mode.

## Open Questions

- Should the first daemon repo live in `claude-fleet`, or a new
  `r2-fleet-runtime` repo?
- Should event storage be plain SQLite, SQLite plus JSONL export, or an
  append-only log with SQLite projections?
- How much provider transcript state should be retained locally?
- What is the minimum trust model for mobile actions before full R2 trust groups?
- Should worktree isolation arrive before or after the TUI?

## First Build Slice

The smallest useful slice is:

1. Rust daemon launches one agent under a PTY.
2. CLI can attach to that PTY.
3. State and event log persist.
4. Provider exhaustion is detected from output.
5. A compatibility wrapper can start one existing fleet member through the daemon.

That proves the substrate move without taking on web, graph memory, distributed
supervision, or full self-hosting.
