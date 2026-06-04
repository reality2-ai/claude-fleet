# claude-fleet

An **OTP-style supervisor for parallel Claude Code sessions**.

If you run several Claude Code sessions at once over a shared codebase, `fleet`
gives you one place to see them all, notice when two are editing the same files,
keep an aggregate event log, dispatch new workers, and — crucially — **bring the
whole suite back after a crash or reboot**.

The model is borrowed from Erlang/OTP supervision:

| OTP concept | here |
|---|---|
| supervision tree | `fleet.toml` (a list of child specs) |
| child spec | one `[[child]]` block (id, cwd, restart policy, seed) |
| restart policy | `permanent` / `transient` / `temporary` |
| restart intensity | `max_restarts` within `max_seconds` → breaker trips, child marked `failed` |
| supervisor | an interactive Claude session you talk to (see `skill/SUPERVISOR.md`) |
| process registry | per-child state derived from transcripts + self-reporting hooks |

## How it works

- **Self-reporting hooks** (installed into the workspace's `.claude/settings.json`)
  make every session record its id, current task, and edited files to
  `<workspace>/.fleet/state/<id>.json`. No change to how you start sessions.
- **Liveness** is derived honestly from the session transcript's mtime (and a
  tmux window if managed), so a session that dies uncleanly still shows as `dead`.
- **Lifecycle** (`up`/`down`/`restart`/`dispatch`) hosts workers as windows in a
  single `fleet` tmux session, resuming each from its last session id.

## Install

```sh
# 1. one-time dependency for lifecycle commands (status/conflicts work without it)
sudo apt install tmux          # jq is also required (usually already present)

# 2. put fleet on PATH (or call bin/fleet directly)
ln -s "$PWD/bin/fleet" ~/.local/bin/fleet

# 3. wire it into a workspace (creates .fleet/, installs hooks)
fleet init /path/to/your/workspace
```

`fleet init` scaffolds `<workspace>/.fleet/` and merges the self-reporting hooks
into `<workspace>/.claude/settings.json` (it leaves `settings.local.json`, where
your permissions live, untouched).

## Use

```sh
fleet status                       # the dashboard
fleet conflicts                    # files claimed by >1 live session
fleet logs [id]                    # aggregate events, or one child's summary

fleet up [id]                      # start the suite (post-reboot recovery)
fleet down [id]                    # stop the suite / one child
fleet restart <id>                 # restart one child
fleet dispatch build "Fix the failing wire tests" r2-core
fleet attach <id>                  # jump into a worker's window
fleet reap                         # detect crashed children, apply restart policy
```

Edit `<workspace>/.fleet/fleet.toml` to declare your workers (see
`templates/fleet.toml.example`).

### Running the supervisor session

Start an interactive Claude session primed with the supervisor role:

```sh
claude --append-system-prompt "$(cat /path/to/claude-fleet/skill/SUPERVISOR.md)"
```

Then just ask it: *"status?"*, *"anything conflicting?"*, *"restart composer"*,
*"bring the suite back up"*.

## What it does NOT do (by design)

- **No live puppeteering.** It can launch, resume, seed, and stop interactive
  workers; it cannot type follow-up turns into a running one. "Dispatch" = start
  a worker seeded with a task.
- **Conflict prevention is detection-only.** It warns when two live sessions
  claim the same file; it does not block edits.
- **Reboot recovery resumes conversations, not in-flight tool runs.** A build
  interrupted by a crash is not auto-resumed; the worker returns to where its
  transcript ended.

## Layout

```
bin/fleet              the CLI
lib/                   common, manifest parser, registry, tmux, restart logic
hooks/                 self-reporting hooks run by worker sessions
skill/SUPERVISOR.md    role prompt for the supervising session
templates/             example fleet.toml + illustrative hooks block
```

Runtime state lives per-workspace under `<workspace>/.fleet/` (never in this repo).

## Requirements

`bash`, `jq`, and (for lifecycle commands) `tmux ≥ 3.0`. Linux/macOS.

## License

MIT — see `LICENSE`.
