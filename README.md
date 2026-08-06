# claude-fleet

[![CI](https://github.com/reality2-ai/claude-fleet/actions/workflows/ci.yml/badge.svg)](https://github.com/reality2-ai/claude-fleet/actions/workflows/ci.yml)

**Run a whole team of AI coding agents — and direct them like a project lead,
in plain English, from one place (even your phone).**

One AI coding agent in one chat window can build you one thing. But real
projects are bigger than one chat window: an app *and* its backend *and* the
docs, each in its own repository, each needing sustained attention. `fleet`
lets you run a **team** of agents — one per repository, powered by **Claude
Code** and/or **OpenAI Codex** — with a **supervisor agent as your single point
of contact**. You tell the supervisor what you want built, in ordinary
language; it coordinates the workers, the workers write the code, and they
consult each other directly when their pieces need to fit together.

You don't have to be a programmer to direct a fleet — describing what you want,
deciding between options the supervisor brings you, and saying "yes, ship it"
is project leadership, not coding. What you do need: comfort copy-pasting a few
terminal commands to install it, and a home for it. Like **OpenClaw** and its
ilk, `fleet` is built to live on an **always-on machine** — an old desktop, a
mini-PC, a home server — where your team keeps working overnight and while
you're away, and you check in and steer from your phone. It runs fine on a
laptop for a working session; the always-on host is where it earns its keep
(see [Where it runs](#where-it-runs)).

For the technically inclined: `fleet` keeps the whole thing inspectable and
boring on purpose. It watches every agent, restarts the ones that die, flags
two agents editing the same file, keeps an aggregate log, and **brings the
whole team back — mid-conversation, not from scratch — after a crash or
reboot.** It's a small set of `bash` scripts wrapping `tmux` and the agent
CLIs: no daemon, no database, no cloud service — all runtime state is plain
JSON files in your workspace, and every agent is an ordinary terminal session
you can attach to and read.

**The shape it works best with.** `fleet` shines on a workspace with a clear
line of authority between repositories: a *specifications* repo that says what
the system should do, a *core* library that implements it, and downstream repos
(apps, services, firmware, tooling) that consume the core. One expert agent per
repo, listed in dependency order; when a downstream agent needs a behaviour
decided, it asks the specs agent rather than inventing an answer, and changes
flow in one direction instead of rippling back and forth. You describe that
structure once in a shared [primer](docs/COMMS-AND-DECISIONS.md#shared-context--primermd)
so every agent knows who to consult; a flat collection of unrelated repos works
fine too — you just get less of the team effect.

> **Two co-evolving tracks.** `fleet` isn't just a runner — it carries a working
> *doctrine* (autonomy with a failsafe, spec-first, refutation by a *different*
> model, self-improvement). The tool is meant to be improved *alongside* the work
> it drives, held to the same bar. See **[Operating doctrine](docs/DOCTRINE.md)**.

![The fleet supervisor session coordinating members: inter-agent messages, a live fleet status, the member windows along the bottom, and Remote Control active](docs/fleet-supervisor.png)

*The supervisor coordinating the fleet — inter-agent messages (`fleet msg from hive · hop 1/6`), a `fleet status` it ran itself, the member windows along the bottom (`0:supervisor 1:specs 2:core 3:hive …`), and Remote Control active.*

> **This repository dogfoods itself.** It is both the tool and one live instance
> of it: `bin/`, `lib/`, `hooks/`, `templates/`, `skill/`, `tests/`, and `docs/`
> are the reusable tool; `DECISIONS.md`, `RESUME.md`, `ROY-GATES.md`, and
> `gates/` are the *operational state of our own fleet* (the R2 project), kept
> in-repo as working examples of the ledger/handoff discipline described below.
> If you adopt `fleet`, don't inherit ours — `fleet init-repo` scaffolds fresh
> `AGENTS.md` / `DECISIONS.md` / `RESUME.md` files in *your* repos, and your
> workspace state lives under *your* `<workspace>/.fleet/`, not here.

## The model (Erlang/OTP)

Each coding-agent session is a supervised "child"; you describe the set declaratively
and `fleet` keeps it running.

| OTP concept | in fleet |
|---|---|
| supervision tree | `fleet.toml` — a list of child specs |
| child spec | one `[[child]]` block: `id`, `cwd`, restart policy, `seed` |
| restart policy | `permanent` / `transient` / `temporary` |
| restart intensity | `max_restarts` within `max_seconds` → breaker trips, child marked `failed` |
| supervisor | an interactive agent session you talk to (role in `skill/SUPERVISOR.md`) |
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
- **Remote control** — enable Claude Code's own Remote Control on Claude-backed
  members and drive them from claude.ai/code or the mobile app.
- **Context & token control** — `fleet tokens` meters what each member re-processes
  every turn (the dominant cost of a long-running fleet); proactive compaction keeps
  it off the ceiling, and fat command output spills to disk instead of living in the
  context window forever. See
  [Context, tokens, and the agent clock](docs/OPERATIONS.md#context-tokens-and-the-agent-clock).
- **A sense of time** — agents have no running clock. Every peer message is stamped,
  and each turn carries how long since the member last spoke, how long it has been on
  this task, and any decision deadline close enough to matter.

## Where it runs

`fleet` is designed to live on an **always-on machine** — a home server, a
mini-PC, a desktop that stays up — in the same spirit as other long-running
agent hosts. Members are tmux sessions: they keep working while you're away,
and anything that suspends the host (a laptop lid-close) pauses every agent
mid-thought until it wakes. It works fine on a laptop for a working session;
the always-on host is what makes overnight runs, `fleet ask` from your phone
via Remote Control, and crash recovery worth having. See
**[Surviving logout & reboot](docs/OPERATIONS.md#surviving-logout--reboot-remote-hosts)**
for the systemd user unit that brings the whole fleet back after a reboot.

**One machine can host several independent fleets.** A fleet is scoped to its
workspace (the directory holding `.fleet/fleet.toml`); each workspace derives
its own tmux socket and session name from the workspace path, so fleets never
collide — even when two workspaces use identical member ids
(`tests/multi-workspace.sh` proves this end-to-end). Run `fleet` commands from
inside a workspace (or set `FLEET_WORKSPACE`) to address that fleet; state,
mailboxes, and logs stay under each workspace's own `.fleet/`.

## Prerequisites

| Requirement | Why | Check / install |
|---|---|---|
| **Claude Code CLI** (`claude`) | the default agent backend for members + supervisor | `claude --version` (see the official install docs) |
| **OpenAI Codex CLI** (`codex`) *(optional)* | alternative agent backend (`provider = "codex"`); also powers `codex-review` / `codex-scan` | `codex --version` · https://github.com/openai/codex |
| **bash ≥ 4** | the CLI, libs, and hooks are bash | `bash --version` — default on Linux; `brew install bash` on macOS |
| **jq** | all state / manifest / message handling is JSON | `jq --version` · `sudo apt install jq` / `brew install jq` |
| **tmux ≥ 3.0** | hosts the sessions; needed for everything except observe-only commands | `tmux -V` · `sudo apt install tmux` / `brew install tmux` |
| **python3 ≥ 3.6** | fd-bound safe I/O for the mailbox & state store (`lib/fleet-safeio.py`); without it those paths **fail closed**, so comms + state writes stop working. pidfd controller-reap additionally needs Linux ≥ 5.3 (python ≥ 3.9) | `python3 --version` — default on Linux; `brew install python` on macOS |
| **GitHub CLI** (`gh`) *(optional)* | only for `fleet wizard` (discovers repos under a gh owner) | `gh --version` · https://cli.github.com, then `gh auth login` |

Platform: Linux or macOS. The observe-only commands (`status`, `conflicts`,
`logs`, `inbox`, `remote`) work with just `bash` + `jq`; lifecycle, comms, and
remote-control need `tmux`; the mailbox and state store additionally need
`python3` (they fail closed without it — see the safe-I/O note above).

> tmux ≥ 3.0 is required because `fleet` uses `tmux new-window -e` to set
> per-member environment. On macOS, `claude` and `tmux` work, but Apple ships
> bash 3.2 — install bash 4+ via Homebrew and put it ahead of `/bin/bash` on
> `PATH` (the hooks themselves run on stock bash; only the `fleet` CLI needs 4+).

## Safety & permissions

`fleet` members are **autonomous coding-agent sessions** running in your repos —
Claude Code by default, Codex when configured. They read, edit files, and run
shell commands on their own. Each member's `permission_mode` in `fleet.toml`
controls how much it may do unprompted; the intended model is **autonomy with a
failsafe, not a leash** — managed workers run unattended by default
(skip-permissions, toggle `FLEET_SKIP_PERMISSIONS=off`) so they never stall,
while the supervisor stays prompt-gated and *monitors* them. Run members in
version control and review their diffs like any other contributor's.

A `PreToolUse` hook auto-approves a curated, non-destructive set of actions so
members don't stall on press-enter-for-yes prompts; destructive or ambiguous
actions still prompt, and one high-stakes class (firmware flash/sign, key
mint/handling) is **hard-denied and escalated to you** even under
skip-permissions. The doctrine is to make risky changes *recoverable*
(checkpoint to git) rather than blocked.

Full details — the permission modes, the auto-approve allowlist and its
toggles, the firmware/key escalation gate, and the self-reporting hooks — are
in **[docs/SAFETY.md](docs/SAFETY.md)**.

## Install

```sh
# 1) clone
git clone https://github.com/reality2-ai/claude-fleet.git
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
the self-reporting hooks into `<workspace>/.claude/settings.json` by default —
it leaves `settings.local.json`, where your permissions live, untouched. Use
`fleet init --all <ws>` to install both Claude and Codex hooks, or
`fleet init --no-hooks <ws>` to scaffold without writing settings, then install
later with `fleet install-hooks [--all|--claude|--codex] [<ws>|--user]`.

Each workspace is isolated automatically — its canonical path produces a stable
tmux socket/session and systemd unit name (see
[Workspace identity](docs/OPERATIONS.md#workspace-identity--isolation)).

## Quick start

**Guided (recommended for a new workspace)** — `fleet wizard` discovers the repos
under a GitHub owner, lets you pick which to clone into the workspace and which
should run an agent, and writes the manifest for you:

```sh
fleet wizard ~/work/myproject              # needs `gh` (logged in)
#   → lists repos under your gh owner/org
#   → "Which repos make up this workspace?"  (clones the missing ones)
#   → "Which should run an AI agent?" (in dependency order)
#   → writes .fleet/fleet.toml + installs hooks
```

**Manual:**

```sh
fleet init ~/work/myproject                 # scaffold + hooks
$EDITOR ~/work/myproject/.fleet/fleet.toml  # declare your members (see below)
FLEET_WORKSPACE=~/work/myproject fleet init-repo  # onboard each declared repo
```

Then, either way:

```sh
cd ~/work/myproject
fleet up                                    # launch every member + the supervisor
fleet status                                # the dashboard
fleet attach api                            # drop into a member's tmux window
#   detach with Ctrl-b d — sessions keep running
```

After a reboot, `fleet up` brings the whole suite back, resuming each member's
conversation. Default topology is deliberately small: one supervisor and one
writer per manifest repo. Opposite-provider pairs (`fleet up --pairs`) and the
on-demand `fleet refute` / `pair` / `handoff` / `failover` commands are covered
in [docs/MANIFEST.md](docs/MANIFEST.md#providers--claude-code-or-codex).

In `fleet status`, `STATE` is derived honestly from the transcript
(live / idle / dead / failed), `WIN` shows a live tmux window, `CLAIMS` counts
files the member has touched, and a `⚠` flags a file claimed by more than one
live member.

## The manifest — `fleet.toml`

`<workspace>/.fleet/fleet.toml` is your supervision tree — a `[supervisor]`
block plus one `[[child]]` per member:

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
seed    = "Resume work in core. Run 'git status' first and summarise where things stand."

[[child]]
id      = "api"
cwd     = "api"
restart = "transient"          # restart only on abnormal (non-zero) exit
seed    = "Resume work in the api service. Summarise open work."
```

Required per-child fields are `id` and `cwd`; `restart` defaults to `permanent`.
The full reference — every field (`name`, `permission_mode`, `provider`,
`resume_nudge`, …), restart semantics, versioning your config, and the
Claude/Codex provider options and tuning env vars — is in
**[docs/MANIFEST.md](docs/MANIFEST.md)**.

## Commands

```sh
# observe (no tmux needed)
fleet status                 # who's live/idle/dead, current task, file claims, conflicts
fleet brief                  # triage: what needs you, who's waiting at their prompt, who's working
fleet conflicts              # files claimed by more than one live session
fleet logs [id]              # aggregate event log, or one member's summary
fleet inbox [id]             # a member's message mailbox (audit trail)
fleet decisions [--all] [--json] [--watch]
                             # decisions waiting on YOU — open, oldest-first
                             #   (--all: history; --watch: self-refreshing pane)
fleet remote [id]            # remote-control status of member(s)
fleet doctor [--quiet]       # self-check the oversight wire from ground truth
                             #   (state docs, mailboxes, Git sync, throttling)
fleet tokens                 # per-member live context size vs the ceiling (needs a live window)

# lifecycle (tmux)
fleet up [--no-supervisor] [--pairs] [id]
                                  # one writer/repo + supervisor; pairs are opt-in
fleet down [id]                   # stop the suite / one member
fleet restart <id>                # restart one member
fleet dispatch [--provider claude|codex] <id> "<task>" [cwd]
fleet compact [--force] <id> | --all  # inject /compact to bound a heavy member's context
fleet init-repo [id]             # add missing repo contract/log/handoff + publish guard
fleet init-resume [--force] [id]  # scaffold repo-local RESUME.md handoff file(s)
fleet install-git-hooks [repo...] # install/refresh publish + attribution hooks
fleet pair [--provider claude|codex] [--id companion-id] [id]
fleet pairs [id]                    # logical pair view: base + provider lanes
fleet pair-send <id> "<msg>"        # send to all lanes in a pair
fleet pair-ask <id> "<question>"    # ask all lanes off-thread
fleet handoff [--provider claude|codex] [--stop-source] <from> [to-id]
fleet failover [--provider claude|codex] [--all|--exhausted] [id...]
fleet refute [--provider claude|codex] [--id id] <target> [claim]
fleet attach <id>                 # attach your terminal to a member's window
fleet order                       # arrange windows: supervisor, then manifest order
fleet reap                        # detect crashed members, apply restart policy
fleet install-service             # per-user systemd unit: auto-start on boot + resume

# inter-agent comms (tmux)
fleet ask <to> "<question>"  # consult a peer off-thread (forked context); reply → your inbox
fleet send <to> "<msg>"      # brief FYI into a member's thread (no reply)
fleet broadcast "<msg>"      # brief FYI to every member
fleet supervise              # start (or point you to) the supervisor session

# decision ledger — durable gates + mechanically latched operational choices
fleet decision add "<question>" [--for <agent>] [--options "a|b|c"] [--authority <who>]
fleet decide <id> "<answer>"                     # ratify once; contradictory re-answer fails
fleet decision challenge <id> "<claim>"          # wound confidence, keep operational latch
fleet decision revoke <id> "<reason>"            # named authority explicitly invalidates
fleet decisions --current [--for <scope>]         # bounded authoritative takeover view

# remote control (tmux + Claude login)
fleet remote-control [on|off] [id]   # enable/disable Claude /remote-control on member(s)

fleet help | version
```

## Further reading

**Guides** (the operational detail moved out of this README):

- [`docs/MANIFEST.md`](docs/MANIFEST.md) — full `fleet.toml` reference: fields, restart semantics, config versioning, providers (Claude/Codex) + tuning env vars, pair/handoff/failover.
- [`docs/SAFETY.md`](docs/SAFETY.md) — full safety & permissions model: permission modes, skip-permissions rationale, auto-approve hook, firmware/key escalation gate, self-reporting hooks.
- [`docs/COMMS-AND-DECISIONS.md`](docs/COMMS-AND-DECISIONS.md) — inter-agent communication (`ask`/`send`, hop cap, comms doctrine + dense form), the decision ledger, shared context (`primer.md`).
- [`docs/OPERATIONS.md`](docs/OPERATIONS.md) — day-to-day operations: repo onboarding, `RESUME.md` handoffs, the supervisor, `/fleet` slash command, surviving logout & reboot (systemd), remote control, [context/token control and the agent clock](docs/OPERATIONS.md#context-tokens-and-the-agent-clock) (what a fleet costs to run, and every knob for it), troubleshooting, project layout.
- [`docs/DOCTRINE.md`](docs/DOCTRINE.md) — the operating doctrine: autonomy with a failsafe, Codex as an adversarial helper, the reusable working process, non-goals, and direction.

**Working doctrine** (project-agnostic, drop-in prompts):

- [`docs/FLEET-WORKING-PRINCIPLES.md`](docs/FLEET-WORKING-PRINCIPLES.md) — the operating principles: spec-first, secure-over-calm, GitHub-as-failsafe, the permission model, roles.
- [`docs/THURISAZ-WORKING-MODE.md`](docs/THURISAZ-WORKING-MODE.md) — the self-improving conjecture → cross-agent refutation → memory loop.
- [`docs/REFUTATION-WORKING-PROCESS.md`](docs/REFUTATION-WORKING-PROCESS.md) — the same discipline distilled into copy-pasteable prompt layers for any project's agents.
- [`docs/grow-strong-ideas.md`](docs/grow-strong-ideas.md) — the conjecture-and-refutation method itself: how a claim earns confidence by surviving non-trivial attacks.

**Design explorations** (recorded directions — not commitments to build):

- [`docs/ADR-001-r2-native-fleet.md`](docs/ADR-001-r2-native-fleet.md) — the north-star of a fully self-hosting fleet, and the one concrete near-term move it endorses.
- [`docs/ADR-002-multibrained-entity-fleet.md`](docs/ADR-002-multibrained-entity-fleet.md) — reframing a member as an *entity* mounting multiple provider "brains" behind one identity.
- [`docs/ADR-003-claude-bg-adapter.md`](docs/ADR-003-claude-bg-adapter.md) — delivering turns programmatically (background sessions) while keeping the unified tmux view.
- [`docs/FACULTY-ADAPTER-CONTRACT.md`](docs/FACULTY-ADAPTER-CONTRACT.md) — the single interface a provider implements to be mountable as a brain.
- [`docs/ENTITY-MEMORY.md`](docs/ENTITY-MEMORY.md) — how an entity's brains share what they know accurately *and* cheaply.
- [`docs/R2-FLEET-CONTROL-HIVE.md`](docs/R2-FLEET-CONTROL-HIVE.md) — the intended provider-neutral mobile/web control shape for mixed Claude/Codex fleets.
- [`docs/R2-FLEET-RUNTIME-SCOPE.md`](docs/R2-FLEET-RUNTIME-SCOPE.md) — a scoped fleet-native runtime (`r2-fleetd`) built around agent semantics rather than terminal panes.

## Status & contributing

A small, pragmatic bash toolkit — primarily developed and tested on **Linux
(systemd)**. It works on macOS with the caveats noted above; other platforms are
untested. Expect rough edges.

Issues and pull requests welcome at
<https://github.com/reality2-ai/claude-fleet>. A smoke test runs in CI on every
push/PR (syntax + a full `up` / resume / `down` lifecycle against a stub
`claude`); run it locally with `tests/smoke.sh` (needs `bash`, `jq`, `tmux`).
Please add coverage for behaviour you change, and match the surrounding style:
POSIX-ish bash, `jq` for all JSON, and graceful degradation when `tmux` is absent
(observe-only commands must keep working without it).

## License

MIT — see `LICENSE`.
