# claude-fleet

An **OTP-style supervisor for parallel Claude Code sessions.**

If you run several Claude Code sessions at once across a multi-repo workspace,
`fleet` gives you one place to: see them all at a glance, notice when two are
editing the same file, keep an aggregate log, let them message each other, drive
any of them from your phone — and, crucially, **bring the whole suite back after
a crash or reboot.**

It's a small set of `bash` scripts wrapping `tmux` and the `claude` CLI. No
daemon, no background services; all runtime state is plain JSON files under your
workspace.

## The model (Erlang/OTP)

Each Claude session is a supervised "child"; you describe the set declaratively
and `fleet` keeps it running.

| OTP concept | in fleet |
|---|---|
| supervision tree | `fleet.toml` — a list of child specs |
| child spec | one `[[child]]` block: `id`, `cwd`, restart policy, `seed` |
| restart policy | `permanent` / `transient` / `temporary` |
| restart intensity | `max_restarts` within `max_seconds` → breaker trips, child marked `failed` |
| supervisor | an interactive Claude session you talk to (role in `skill/SUPERVISOR.md`) |
| process registry | per-member state derived from transcripts + self-reporting hooks |
| message passing | `fleet ask` / `fleet send` between members, with a hop cap |

## What you get

- **Monitor** — `fleet status`: who's live / idle / dead, each member's current
  task, and the files it's touched.
- **Conflict detection** — flags when two live sessions have edited the same file.
- **Lifecycle & crash recovery** — start / stop / restart members as `tmux`
  windows; `fleet up` resumes every member (by its prior session id) after a
  reboot.
- **Inter-agent comms** — members consult each other (`ask`) or notify each other
  (`send`); replies route back to the asker; a hop cap stops runaway loops.
- **Remote control** — enable Claude Code's own Remote Control on any member and
  drive it from claude.ai/code or the mobile app.

## Prerequisites

| Requirement | Why | Check / install |
|---|---|---|
| **Claude Code CLI** (`claude`) | the members and supervisor *are* Claude Code | `claude --version` (see the official install docs) |
| **bash ≥ 4** | the CLI, libs, and hooks are bash | `bash --version` — default on Linux; `brew install bash` on macOS |
| **jq** | all state / manifest / message handling is JSON | `jq --version` · `sudo apt install jq` / `brew install jq` |
| **tmux ≥ 3.0** | hosts the sessions; needed for everything except observe-only commands | `tmux -V` · `sudo apt install tmux` / `brew install tmux` |
| **flock** *(optional)* | mailbox locking under concurrent sends; degrades gracefully if absent | part of `util-linux` (already present on most Linux) |

Platform: Linux or macOS. The observe-only commands (`status`, `conflicts`,
`logs`, `inbox`, `remote`) work with just `bash` + `jq`; lifecycle, comms, and
remote-control need `tmux`.

> tmux ≥ 3.0 is required because `fleet` uses `tmux new-window -e` to set
> per-member environment. On macOS, `claude` and `tmux` work, but Apple ships
> bash 3.2 — install bash 4+ via Homebrew and put it ahead of `/bin/bash` on
> `PATH` (the hooks themselves run on stock bash; only the `fleet` CLI needs 4+).

## Install

```sh
# 1) clone
git clone <this-repo-url> claude-fleet
cd claude-fleet

# 2) dependencies (Debian/Ubuntu shown; jq is often already present)
sudo apt install -y tmux jq

# 3) put `fleet` on PATH (or just call ./bin/fleet)
ln -s "$PWD/bin/fleet" ~/.local/bin/fleet     # ensure ~/.local/bin is on $PATH
fleet version

# 4) wire it into the workspace that holds the repos you run sessions in
fleet init /path/to/your/workspace

# 5) (recommended) also install user-level hooks, so sessions you start by hand
#    inside sub-repos self-report too (they no-op outside a .fleet workspace)
fleet install-hooks --user
```

`fleet init` scaffolds `<workspace>/.fleet/` (manifest, state, logs) and merges
the self-reporting hooks into `<workspace>/.claude/settings.json` — it leaves
`settings.local.json`, where your permissions live, untouched. Use
`fleet init --no-hooks <ws>` to scaffold without writing settings, then install
later with `fleet install-hooks [<ws>|--user]`.

## Quick start

```sh
fleet init ~/work/myproject                 # scaffold + hooks
$EDITOR ~/work/myproject/.fleet/fleet.toml  # declare your members (see below)
cd ~/work/myproject
fleet up                                    # launch every member + the supervisor
fleet status                                # the dashboard
fleet attach api                            # drop into a member's tmux window
#   detach with Ctrl-b d — sessions keep running
```

After a reboot, `fleet up` brings the whole suite back, resuming each member's
conversation.

## The manifest — `fleet.toml`

`<workspace>/.fleet/fleet.toml` is your supervision tree. A neutral example —
a workspace with `api`, `web`, and `core` repos:

```toml
[supervisor]
strategy     = "one_for_one"   # restarting one child doesn't touch the others
max_restarts = 3               # >max_restarts within max_seconds → child marked `failed`
max_seconds  = 60
max_hops     = 6               # cap on agent-to-agent conversation depth

[[child]]
id      = "core"               # stable name (also the tmux window name)
cwd     = "core"               # working dir, relative to the workspace root (or absolute)
restart = "permanent"          # permanent | transient | temporary
name    = "core-worker"        # shown in the session's prompt box (claude --name)
seed    = "Resume work in core. Run 'git status' first and summarise where things stand."

[[child]]
id      = "api"
cwd     = "api"
restart = "transient"          # restart only on abnormal (non-zero) exit
seed    = "Resume work in the api service. Summarise open work."

[[child]]
id      = "web"
cwd     = "web"
restart = "transient"
seed    = "Resume work on the web frontend. Summarise open work."
```

Restart policies: **permanent** always restarts on exit; **transient** restarts
only on abnormal exit; **temporary** never auto-restarts. `seed` is the initial
prompt used **only on a fresh start** — once a session exists, `fleet up` resumes
it (`claude --resume`) instead of re-seeding. Window order follows manifest
order (supervisor first); see `fleet order`.

## Commands

```sh
# observe (no tmux needed)
fleet status                 # who's live/idle/dead, current task, file claims, conflicts
fleet conflicts              # files claimed by more than one live session
fleet logs [id]              # aggregate event log, or one member's summary
fleet inbox [id]             # a member's message mailbox (audit trail)
fleet remote [id]            # remote-control status of member(s)

# lifecycle (tmux)
fleet up [--no-supervisor] [id]   # start the suite + supervisor (post-reboot recovery)
fleet down [id]                   # stop the suite / one member
fleet restart <id>                # restart one member
fleet dispatch <id> "<task>" [cwd]  # start a fresh worker seeded with a task
fleet attach <id>                 # attach your terminal to a member's window
fleet order                       # arrange windows: supervisor, then manifest order
fleet reap                        # detect crashed members, apply restart policy

# inter-agent comms (tmux)
fleet ask <to> "<question>"  # ask a member's repo via a fresh expert (non-disruptive)
fleet send <to> "<msg>"      # inject a message into a member's live session
fleet broadcast "<msg>"      # message every member
fleet supervise              # start (or point you to) the supervisor session

# remote control (tmux + Claude login)
fleet remote-control [on|off] [id]   # enable/disable Claude /remote-control on member(s)

fleet help | version
```

## Inter-agent communication

Each member is primed at launch knowing it's the resident expert on its repo, who
its peers are, and how to reach them. Two modes:

- **`fleet ask <to> "q"`** spins up a *fresh, headless* expert session in the
  target's repo, which answers from that codebase and routes the reply back to
  the asker — **the target's own session is never interrupted.** Best for Q&A. The
  responder window is spawned in the background (it won't steal your focus) and
  closes when done.
- **`fleet send <to> "msg"`** injects a message into the target's *live* session
  (hybrid delivery: now if it's idle, else queued and delivered the moment it next
  returns to its prompt). Best for nudges / notifications.

Replies route back to whoever asked: the `[fleet msg from <id>]` prefix names the
sender, and members are instructed to always answer that id. Long replies are
delivered in full (typed in keystroke chunks, one turn). Mailboxes live at
`<workspace>/.fleet/inbox/<id>.jsonl` as an audit trail.

**Hop cap.** To stop two agents ping-ponging forever, every message carries a hop
depth (a reply inherits hop+1; a fresh thread resets to 1). Sends past
`[supervisor] max_hops` are refused.

### Shared context — `primer.md`

The tool itself is domain-agnostic. To give every member the same map of your
project — architecture, who-owns-what, conventions, collaboration rules — put it
in an optional `<workspace>/.fleet/primer.md`. If present, its contents are
appended verbatim to every member's launch primer. (Re-`up`/re-dispatch members
after editing it; the primer is applied at launch.)

## The supervisor

`fleet up` starts a dedicated **supervisor** window — a Claude session primed with
the role in `skill/SUPERVISOR.md` — alongside the members. Start or jump to it
directly with:

```sh
fleet supervise            # start it (or tell you it's already up)
fleet attach supervisor    # drop into it
```

It's a first-class member (id `supervisor`): it self-reports, can be messaged
(`fleet send supervisor "..."`), and resumes on the next `fleet up`. It is the
**single workspace-root session** — oversight and cross-cutting coordination;
per-repo work belongs to the member experts, so there's no separate "root"
worker. Just talk to it: *"status?"*, *"anything conflicting?"*, *"restart api"*,
*"bring the suite back up"*. Use `fleet up --no-supervisor` to skip it.

## Remote control (phone / web)

Claude Code's own **Remote Control** (`/remote-control`) lets you drive a local
session from claude.ai/code or the Claude mobile app — an outbound HTTPS
connection, no ports opened. `fleet` toggles it on live members by injecting the
slash command (no relaunch). It's a per-member toggle, meant to be enabled
piecemeal, checked, and turned off again:

```sh
fleet remote-control on api    # enable one member  (default action is "on")
fleet remote-control off api   # disable it again   (/remote-control is a toggle)
fleet remote-control on        # enable every live member at once
fleet remote                   # show each member's status (active | -)
```

`fleet` reads each member's current state first, so `on`/`off` only act when they
actually change something. Enabled members appear **by name** in claude.ai/code
and the mobile app (signed in as you). Requires a Pro/Max/Team/Enterprise login
(`/login`); each enabled member is a separately controllable session on your
account.

## Self-reporting hooks

`fleet init` installs hooks into `<workspace>/.claude/settings.json` that make
every session record its id, current task, and edited files to
`<workspace>/.fleet/state/<id>.json`. Liveness is derived honestly from the
session transcript's mtime (plus a tmux window if managed), so a session that
dies uncleanly still shows as `dead`.

**Hook scope — important if you run sessions in sub-repos.** Claude Code loads
hooks from the session's *own* project, so a session started in a sub-repo does
**not** inherit the workspace-root `.claude/settings.json`. Two mechanisms close
that gap:

- **Managed members** (`fleet up` / `fleet dispatch`) launch with
  `--settings <workspace>/.fleet/managed.settings.json`, so they always
  self-report regardless of cwd. Nothing to do.
- **Hand-started sessions** in sub-repos need the user-scoped install:
  `fleet install-hooks --user`. These hooks no-op instantly outside any `.fleet`
  workspace, so a global install has no effect on your other projects.

## What it does NOT do (by design)

- **Conflict prevention is detection-only.** It warns when two live sessions claim
  the same file; it does not block edits.
- **Reboot recovery resumes conversations, not in-flight tool runs.** A build
  interrupted by a crash is not auto-resumed — the member returns to where its
  transcript ended.
- **`fleet send` can interrupt a busy peer.** Injection enters the peer's input as
  a turn; hybrid delivery holds mail until the peer is idle, but a mid-task agent
  that `send`s another still enqueues a turn. Prefer `fleet ask` for Q&A — it never
  touches the target's session.

## Project layout

```
bin/fleet              the CLI (the only entrypoint)
lib/                   common, manifest parser, registry, tmux, restart,
                       comms (mailboxes + ask), responder, run-child
hooks/                 self-reporting hooks: session-start, prompt-submit,
                       post-edit, on-stop, session-end
skill/SUPERVISOR.md    role prompt for the supervising session
templates/             example fleet.toml + illustrative hooks block
```

Runtime state lives per-workspace under `<workspace>/.fleet/` (manifest, state,
run bindings, mailboxes, logs) — never in this repo.

## License

MIT — see `LICENSE`.
