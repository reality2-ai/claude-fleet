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

## Prerequisites

| Requirement | Why | Check / install |
|---|---|---|
| **Claude Code CLI** (`claude`) | the worker sessions and the supervisor are Claude Code | `claude --version` — see the Claude Code install docs |
| **bash ≥ 4** | the CLI, libs, and hooks are bash | `bash --version` (default on Linux; `brew install bash` on macOS) |
| **jq** | all state/manifest/message handling is JSON | `jq --version` · `sudo apt install jq` / `brew install jq` |
| **tmux ≥ 3.0** | hosts worker sessions; needed for `up`/`down`/`restart`/`dispatch`/`ask`/`send` | `tmux -V` · `sudo apt install tmux` / `brew install tmux` |
| **flock** *(optional)* | mailbox locking under concurrent sends; degrades gracefully if absent | part of `util-linux` (present on most Linux) |

Platform: Linux or macOS. The observe-only commands (`status`, `conflicts`,
`logs`, `inbox`) work with just `bash` + `jq`; everything else needs `tmux`.

> tmux ≥ 3.0 is required specifically because `fleet` uses `tmux new-window -e`
> to set per-worker environment. Ubuntu 24.04 ships 3.4; check yours with `tmux -V`.

## Install

```sh
# 1) clone
git clone <this-repo-url> claude-fleet
cd claude-fleet

# 2) install prerequisites (Debian/Ubuntu shown; jq is usually already present)
sudo apt install -y tmux jq

# 3) put `fleet` on your PATH (or call ./bin/fleet directly)
ln -s "$PWD/bin/fleet" ~/.local/bin/fleet   # ensure ~/.local/bin is on $PATH
fleet version

# 4) wire it into the workspace that contains the repos you run sessions in
fleet init /path/to/your/workspace

# 5) (recommended) also install user-level hooks so sessions you start by hand
#    inside sub-repos self-report too — they no-op outside a .fleet workspace
fleet install-hooks --user
```

`fleet init` scaffolds `<workspace>/.fleet/` (manifest, state, logs) and merges
the self-reporting hooks into `<workspace>/.claude/settings.json` — it leaves
`settings.local.json`, where your permissions live, untouched. Use
`fleet init --no-hooks <ws>` to scaffold without writing any settings, then
install hooks later with `fleet install-hooks [<ws>|--user]`.

Then edit `<workspace>/.fleet/fleet.toml` to declare your workers (see
`templates/fleet.toml.example`), and you're ready: `fleet up`.

### Hook scope — important if you run sessions in sub-repos

Claude Code loads hooks from the session's **own** project. A session started in
a sub-repo (e.g. `r2-composer/`) does **not** inherit the workspace-root
`.claude/settings.json`, so it won't self-report with only a project-scoped
install. Two mechanisms close that gap:

- **Managed workers** (`fleet up` / `fleet dispatch`) are launched with
  `--settings <workspace>/.fleet/managed.settings.json`, so they always
  self-report regardless of their cwd. Nothing extra to do.
- **Hand-started sessions** in sub-repos need a **user-scoped** install:

  ```sh
  fleet install-hooks --user      # merges hooks into ~/.claude/settings.json
  ```

  These hooks no-op instantly outside any `.fleet` workspace, so a global
  install has no effect on your other projects.

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

fleet ask core "what wire version does r2-core use?"   # ask an expert repo (non-disruptive)
fleet send hive "heads up: API boundary changed"        # nudge a peer's live session
fleet broadcast "pausing for a rebase"                  # message all workers
fleet inbox composer                                    # read a worker's mailbox
```

### Talking between agents

Each worker is primed (at launch) knowing it's the expert on its repo, who its
peers are, and how to reach them. Two modes:

- **`fleet ask <to> "q"`** spins up a *fresh headless expert session* in the
  target's repo, which answers from that codebase and routes the reply back to
  the asker — **the target's own session is never interrupted.** Best for Q&A.
- **`fleet send <to> "msg"`** injects directly into the target's live session
  (hybrid delivery: now if it's idle, else queued and delivered the moment it
  next returns to its prompt). Best for nudges/notifications.

Replies route back to whoever asked: the `[fleet msg from <id>]` prefix names the
sender, and agents are instructed to always answer that id. Mailboxes live at
`<workspace>/.fleet/inbox/<id>.jsonl` as an audit trail.

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

- **Conflict prevention is detection-only.** It warns when two live sessions
  claim the same file; it does not block edits.
- **Reboot recovery resumes conversations, not in-flight tool runs.** A build
  interrupted by a crash is not auto-resumed; the worker returns to where its
  transcript ended.
- **`fleet send` can interrupt a busy peer.** Injection enters the peer's input
  as a user turn; the hybrid mode mitigates this by holding mail until the peer
  is idle, but a mid-task agent that `fleet send`s another mid-task agent still
  enqueues work. Prefer `fleet ask` (which spawns a separate responder) for Q&A.
- **Agent conversations can loop.** Two agents replying to each other won't stop
  on their own beyond the "don't reply unnecessarily" instruction in the primer;
  there is no hop-count limit yet. Watch `fleet inbox` / `fleet logs`.

## Layout

```
bin/fleet              the CLI
lib/                   common, manifest parser, registry, tmux, restart,
                       comms (mailboxes + ask), responder, run-child
hooks/                 self-reporting hooks (session-start, prompt-submit,
                       post-edit, on-stop, session-end)
skill/SUPERVISOR.md    role prompt for the supervising session
templates/             example fleet.toml + illustrative hooks block
```

Runtime state lives per-workspace under `<workspace>/.fleet/` (manifest, state,
run bindings, mailboxes, logs) — never in this repo.

## License

MIT — see `LICENSE`.
