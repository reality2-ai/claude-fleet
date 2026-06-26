# claude-fleet

[![CI](https://github.com/reality2-ai/claude-fleet/actions/workflows/ci.yml/badge.svg)](https://github.com/reality2-ai/claude-fleet/actions/workflows/ci.yml)

An **OTP-style supervisor for parallel autonomous coding-agent sessions** —
**Claude Code** and/or **OpenAI Codex.**

If you run several agent sessions at once across a multi-repo workspace,
`fleet` gives you one place to: see them all at a glance, notice when two are
editing the same file, keep an aggregate log, let them message each other, drive
any of them from your phone — and, crucially, **bring the whole suite back after
a crash or reboot.**

It's a small set of `bash` scripts wrapping `tmux` and the agent CLI (`claude`
or `codex` — chosen per member). No daemon, no background services; all runtime
state is plain JSON files under your workspace.

> **Two co-evolving tracks.** `fleet` isn't just a runner — it carries a working
> *doctrine* (autonomy with a failsafe, spec-first, refutation by a *different*
> model, self-improvement). The tool is meant to be improved *alongside* the work
> it drives, held to the same bar. See **[Operating doctrine](#operating-doctrine)**.

![The fleet supervisor session coordinating members: inter-agent messages, a live fleet status, the member windows along the bottom, and Remote Control active](docs/fleet-supervisor.png)

*The supervisor coordinating the fleet — inter-agent messages (`fleet msg from hive · hop 1/6`), a `fleet status` it ran itself, the member windows along the bottom (`0:supervisor 1:specs 2:core 3:hive …`), and Remote Control active.*

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

## Prerequisites

| Requirement | Why | Check / install |
|---|---|---|
| **Claude Code CLI** (`claude`) | the default agent backend for members + supervisor | `claude --version` (see the official install docs) |
| **OpenAI Codex CLI** (`codex`) *(optional)* | alternative agent backend (`provider = "codex"`); also powers `codex-review` / `codex-scan` | `codex --version` · https://github.com/openai/codex |
| **bash ≥ 4** | the CLI, libs, and hooks are bash | `bash --version` — default on Linux; `brew install bash` on macOS |
| **jq** | all state / manifest / message handling is JSON | `jq --version` · `sudo apt install jq` / `brew install jq` |
| **tmux ≥ 3.0** | hosts the sessions; needed for everything except observe-only commands | `tmux -V` · `sudo apt install tmux` / `brew install tmux` |
| **GitHub CLI** (`gh`) *(optional)* | only for `fleet wizard` (discovers repos under a gh owner) | `gh --version` · https://cli.github.com, then `gh auth login` |
| **flock** *(optional)* | mailbox locking under concurrent sends; degrades gracefully if absent | part of `util-linux` (already present on most Linux) |

Platform: Linux or macOS. The observe-only commands (`status`, `conflicts`,
`logs`, `inbox`, `remote`) work with just `bash` + `jq`; lifecycle, comms, and
remote-control need `tmux`.

> tmux ≥ 3.0 is required because `fleet` uses `tmux new-window -e` to set
> per-member environment. On macOS, `claude` and `tmux` work, but Apple ships
> bash 3.2 — install bash 4+ via Homebrew and put it ahead of `/bin/bash` on
> `PATH` (the hooks themselves run on stock bash; only the `fleet` CLI needs 4+).

## Safety & permissions

`fleet` members are **autonomous coding-agent sessions** running in your repos —
Claude Code by default, Codex when configured. They read, edit files, and run
shell commands on their own. Treat them with the same care as any agent you let
act unattended:

- **Mind `permission_mode`.** Each member can set `permission_mode` in `fleet.toml`
  (`default` · `acceptEdits` · `plan` · `bypassPermissions`). `bypassPermissions`
  skips Claude Code's per-action approval — handy for unattended runs, but the
  session can then edit and execute without prompting. Start at `default` /
  `acceptEdits` and only loosen it for repos you're willing to let an agent change
  on its own.
- **Run them in version control.** Members work directly in your working trees;
  commit or stash anything you don't want touched, and review their diffs like any
  other contributor's.
- **Autonomy with a failsafe, not a leash.** The intended model: managed
  **workers run unattended** by default (Claude:
  `--dangerously-skip-permissions`; Codex:
  `--dangerously-bypass-approvals-and-sandbox`; toggle
  `FLEET_SKIP_PERMISSIONS=off`) so they never stall waiting for a human, while
  the **supervisor stays prompt-gated and *monitors*** them — that oversight,
  plus the hook below, is the safety layer.
  The doctrine is to make risky changes *recoverable* (checkpoint to git) rather
  than to block them. See [Operating doctrine](#operating-doctrine).
- **Routine prompts auto-confirmed; high-stakes ops escalated.** A `PreToolUse`
  hook auto-approves a non-destructive set (reads, in-repo edits, read-only shell)
  so members don't stall on "press-enter-for-yes" — destructive/ambiguous actions
  still prompt, and one high-stakes class (firmware-flash / firmware-sign /
  key-mint / writes to key-or-signature artifacts) is **hard-denied and escalated
  to you**, even under skip-permissions. See
  [Auto-confirming routine prompts](#auto-confirming-routine-prompts); toggles
  `FLEET_AUTOCONFIRM=off`, `FLEET_FIRMWARE_GATE=off`.
- **Remote control is opt-in and per-member.** `fleet remote-control` exposes a
  session to claude.ai/code and the mobile app (signed in as you) — enable it
  deliberately and turn it off when done.
- **State is local, not secret-scrubbed.** `<workspace>/.fleet/` holds tasks,
  mailboxes, and logs as plain JSON. The bundled `.gitignore` already excludes the
  runtime parts — keep it that way; don't commit a workspace's `.fleet/` runtime to
  a public repo.

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
conversation.

In `fleet status`, `STATE` is derived honestly from the transcript
(live / idle / dead / failed), `WIN` shows a live tmux window, `CLAIMS` counts
files the member has touched, and a `⚠` flags a file claimed by more than one
live member.

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
permission_mode = "acceptEdits"  # default | acceptEdits | plan | bypassPermissions (optional; see Safety)
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

Required per-child fields are `id` and `cwd`; `restart` defaults to `permanent`.
Optional: `name`, `seed`, `permission_mode` (see [Safety & permissions](#safety--permissions)),
`provider` (`claude` *(default)* or `codex` — see [Providers](#providers--claude-code-or-codex)),
and `resume_nudge` (below).

A resumed session reopens **idle at its prompt**, so `fleet up` nudges each
resumed member to pick its work back up — by default with `carry on`. Override
per child with `resume_nudge = "…"` in `fleet.toml`, or globally with
`FLEET_RESUME_NUDGE`; set either to `""` to leave members idle on resume.

## Portability — version your config

`fleet init` drops a `.gitignore` into `<workspace>/.fleet/` that excludes runtime
state (`state/`, `run/`, `inbox/`, `log/`, `managed.settings.json`) but keeps your
**config** (`fleet.toml`, `primer.md`). So you can version just the config and run
the same fleet on any machine:

```sh
cd <workspace>/.fleet && git init && git add . && git commit -m "fleet config"
# push to a (private) repo, then on another machine:
git clone <your-fleet-config-repo> <workspace>/.fleet
fleet install-hooks <workspace> && fleet install-hooks --user
cd <workspace> && fleet up
```

(The repos your members work in are cloned separately, as usual.)

## Providers — Claude Code or Codex

Each member runs on an agent backend — **Claude Code** (`claude`, the default) or
**OpenAI Codex** (`codex`) — chosen per member in `fleet.toml`:

```toml
[[child]]
id       = "reviewer"
cwd      = "core"
provider = "codex"              # default is "claude"
# optional codex tuning (or the FLEET_CODEX_* env equivalents):
model           = "..."         # --model
sandbox         = "read-only"   # --sandbox (read-only | workspace-write | …)
approval_policy = "on-request"  # --ask-for-approval
```

`provider` is also settable fleet-wide with `FLEET_AGENT_PROVIDER=codex`, and the
binary / model / profile / sandbox / approval via `FLEET_CODEX_BIN` ·
`FLEET_CODEX_MODEL` · `FLEET_CODEX_PROFILE` · `FLEET_CODEX_SANDBOX` ·
`FLEET_CODEX_APPROVAL`. The fleet wires its self-reporting + permission hooks into
Codex too (via Codex's `--cd`, hook-config, and sandbox flags), so a Codex member
self-reports, is messaged, and is gated just like a Claude one. Running a **mix**
is deliberate: a different model is a different *perspective* — see
[Codex as an adversarial helper](#codex-as-an-adversarial-helper).

Managed Codex workers follow the same low-interaction default as managed Claude
workers: when `FLEET_SKIP_PERMISSIONS` is left `on`, non-supervisor Codex members
are launched with `--dangerously-bypass-approvals-and-sandbox`. Set
`FLEET_SKIP_PERMISSIONS=off` to honor prompt-gated modes such as
`permission_mode = "plan"`; `fleet refute` does this automatically for read-only
adversaries.

Two commands make mixed-provider operation first-class:

```sh
fleet handoff core                 # default: start core-codex from core's state
fleet handoff --provider claude api api-claude
fleet pair core                    # start core-codex as a live companion
fleet pair                         # pair every manifest child with its opposite provider
fleet refute core                  # default: opposite-provider read-only adversary
fleet dispatch --provider codex audit "Review the auth diff" core
```

`handoff` does **not** pretend Claude and Codex can resume each other's private
transcripts. If the target id is already running, it delivers a takeover packet
to that live member; otherwise it starts a fresh target-provider session with
the same packet: the repo-local `RESUME.md`, source provider/session metadata,
current task, claimed files, git status/diff context, and a transcript excerpt.
That is the right shape for token exhaustion: the next engine verifies ground
truth from the repo and carries on from durable state instead of inheriting a
hidden, provider-owned context. Add the new member to `fleet.toml` if the
handoff or companion should be durable across `fleet up` later.

`fleet pair` is the standing co-work mode. It starts an opposite-provider
companion in the same repo as a member (`core` + `core-codex`, for example).
Companions are normal implementation workers, not read-only reviewers: they
coordinate through `fleet ask/send`, split hypotheses or files where possible,
keep the same repo-local `RESUME.md` current, and challenge each other's work
before either engine treats the repo as done. This also simplifies failover:
when both engines have tokens, `fleet handoff core --stop-source` finds and
promotes the already-running opposite-provider companion instead of cold-starting
context after the source is exhausted.

### Repo-local handoff state — `RESUME.md`

Every implementation worker is expected to maintain `<repo>/RESUME.md` as the
durable takeover record. The file should be updated after each meaningful turn
and before the worker goes idle with:

- current objective
- last verified state, with commands/results
- next concrete actions
- changed files / claims
- blockers, risks, and open decisions
- branch/commit and any "do not assume" notes

Use `fleet init-resume [id]` to scaffold the file for one member, or
`fleet init-resume` for every manifest child. `fleet handoff` includes this file
ahead of transcript excerpts, and `fleet doctor` reports managed non-adversary
workers whose `RESUME.md` is missing, empty, still full of `TODO` placeholders,
or stale. Tune with `FLEET_RESUME_FILE`, `FLEET_RESUME_CHECK=off`,
`FLEET_RESUME_TODO_CHECK=off`, and `FLEET_RESUME_STALE_SECS`.

## Commands

```sh
# observe (no tmux needed)
fleet status                 # who's live/idle/dead, current task, file claims, conflicts
fleet brief                  # triage: what needs you, who's waiting at their prompt, who's working
fleet conflicts              # files claimed by more than one live session
fleet logs [id]              # aggregate event log, or one member's summary
fleet inbox [id]             # a member's message mailbox (audit trail)
fleet remote [id]            # remote-control status of member(s)

# lifecycle (tmux)
fleet up [--no-supervisor] [id]   # start the suite + supervisor (post-reboot recovery)
fleet down [id]                   # stop the suite / one member
fleet restart <id>                # restart one member
fleet dispatch [--provider claude|codex] <id> "<task>" [cwd]
fleet init-resume [--force] [id]  # scaffold repo-local RESUME.md handoff file(s)
fleet pair [--provider claude|codex] [--id companion-id] [id]
fleet handoff [--provider claude|codex] [--stop-source] <from> [to-id]
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

# remote control (tmux + Claude login)
fleet remote-control [on|off] [id]   # enable/disable Claude /remote-control on member(s)

fleet help | version
```

### The `/fleet` slash command

So you can drive the fleet from *inside* a Claude session (the supervisor, or any
member) without dropping to a shell, fleet ships a `/fleet` slash command:

```sh
fleet install-commands --user     # makes /fleet available in every session
#   (fleet init also installs it into the workspace .claude/)
```

Then, in any session: `/fleet brief`, `/fleet status`, `/fleet up`, `/fleet ask
core "…"`, `/fleet remote-control on`, etc. It runs the `fleet` CLI and the session
reports the result. Like the hooks, the user-level install is what makes it reach
members running in sub-repos. (Commands load live — no restart.)

## Surviving logout & reboot (remote hosts)

The fleet runs in tmux on its **own** tmux socket (`-L fleet`), kept separate from
any personal tmux you run. When you `fleet up` over SSH or a remote desktop you
expect the fleet to keep running after you disconnect — and on most hosts it does.

The exception is systemd hosts that set `KillUserProcesses=yes` (common on
xrdp/rdesktop boxes). There, a tmux server started inside a login session lives
in that session's cgroup scope and gets reaped the moment the session ends —
even with lingering enabled. To avoid that, `fleet up` launches the tmux server
as a **transient unit of your per-user systemd manager** (`systemd-run --user`,
`Type=forking`). That manager outlives any single login, so the fleet survives
SSH/rdesktop logout. This is automatic; opt out with `FLEET_TMUX_USER_SCOPE=off`.

For the per-user manager to run before you log in (and to keep the fleet alive
with no active session), enable lingering once:

```sh
loginctl enable-linger "$USER"
```

To also bring the fleet back **on reboot** — resuming every agent's recorded
session — install the user service:

```sh
fleet install-service                 # renders ~/.config/systemd/user/fleet.service
systemctl --user start fleet.service  # 'fleet up' now; starts on boot thereafter
# systemctl --user stop fleet.service # runs 'fleet down'
```

> The user manager's `PATH` at boot is minimal — make sure `claude` is reachable
> from it (the unit sets a sensible default `PATH`; otherwise set `FLEET_CLAUDE_BIN`
> in the unit). `fleet up` resumes members via `--resume`, so a boot-time start
> restores conversations, not just processes.

> **Linux/systemd only.** The per-user-manager trick, `loginctl`, and
> `fleet install-service` are systemd features. On macOS there's no systemd: the
> dedicated tmux socket already lets the fleet survive terminal/SSH disconnect the
> normal way, and `fleet install-service` exits with a clear message. For boot
> auto-start on macOS, wrap `fleet up` in a `launchd` agent.

## Inter-agent communication

Each member is primed at launch knowing it's the resident expert on its repo, who
its peers are, and how to reach them. The design goal: **a peer's question never
hijacks your live thread.**

- **`fleet ask <to> "q"`** — consult a peer. A transient responder resumes the
  target's provider-native context off-thread (Claude uses `--fork-session`;
  Codex uses a headless resumed run), answers the question, and closes. The
  target's own session is never interrupted; it only gets a brief *"peer asked
  you X — answered off-thread, no action needed"* note when it's next idle. The
  answer routes back to **the asker**: a one-line summary in its thread, the full
  reply saved in its inbox (`fleet inbox`).
- **`fleet send <to> "msg"`** — a brief FYI delivered into the target's thread
  (held until it's at its prompt, so no mid-task corruption). No reply expected.

So an `ask` costs the target nothing but a one-line heads-up, while the asker gets
a real answer informed by the peer's current context. Members are told they do
**not** answer incoming asks themselves — the fork does. Mailboxes live at
`<workspace>/.fleet/inbox/<id>.jsonl` (full answers + an audit trail of who asked
whom).

> Why the off-thread responder? An earlier version delivered the question straight
> into the target's live thread — visible, but disruptive. A still-earlier one
> answered in a *fresh* headless session that didn't know what the target was
> working on. Provider-native resume/fork gets both: off-thread **and**
> context-aware.

**Hop cap.** To stop chains running away, every message carries a hop depth (a
reply inherits hop+1; a fresh thread resets to 1). Messages past `[supervisor]
max_hops` are refused.

### Shared context — `primer.md`

The tool itself is domain-agnostic. To give every member the same map of your
project — architecture, who-owns-what, conventions, collaboration rules — put it
in an optional `<workspace>/.fleet/primer.md`. If present, its contents are
appended verbatim to every member's launch primer. (Re-`up`/re-dispatch members
after editing it; the primer is applied at launch.)

## The supervisor

`fleet up` starts a dedicated **supervisor** window — an agent session primed with
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

## Codex as an adversarial helper

Beyond running members, the fleet can launch a read-only **opposite-provider**
reviewer with `fleet refute <target> [claim]`. This is the operational form of
cross-model adversarial work: a Claude-backed target gets a Codex reviewer by
default; a Codex-backed target gets a Claude reviewer by default. The reviewer is
seeded with the target's current task, claimed files, git context, and transcript
excerpt, then told to refute from live ground truth.

The fleet also ships two standalone tools that use **Codex as an independent,
_different-model_ adversary** — read-only, so it critiques but never edits,
flashes, or commits. The premise (from
[`docs/THURISAZ-WORKING-MODE.md`](docs/THURISAZ-WORKING-MODE.md), §TH-DISCOURSE):
a significant design or fix isn't trustworthy until a *different* mind has
genuinely tried to break it — and a different model/architecture catches what
same-model self-review structurally can't.

- **`bin/codex-review`** — point Codex at a finding, a design, or a git diff and
  have it try to refute it:
  ```sh
  codex-review notes.md            # review a finding/design in a file
  codex-review --diff HEAD~1       # adversarially review a diff
  echo "<claim>" | codex-review -  # review piped text
  ```
- **`bin/codex-scan`** — a full-pass audit of a repo by Codex across
  `security | usability | sovereignty | both`, supplied your project's **mission +
  values** so it audits *against what you're building for*, not generic
  best-practice:
  ```sh
  codex-scan ./core both
  ```

Run them **selectively** — Codex is quota-limited, so reserve them for high-stakes
checks. Recurring scans are an **annealing** process: scan → harden → re-scan
*converges* (each pass is also a closure-check on the last — did the fixes hold?),
and the point of a *different* adversary is to shake the system out of a
comfortable "all-green" local minimum that same-model verification settled into.
`codex-scan` can be pointed at **claude-fleet itself** — the tool gets the same
treatment as the code it builds.

## The working process, as reusable prompts

The adversarial/annealing discipline above is one piece of a larger working
process: conjecture/refutation, verify-then-record, the confirmation-bias and
anti-sycophancy guards, edge-first testing, and the git habits that make results
durable and auditable.
[`docs/REFUTATION-WORKING-PROCESS.md`](docs/REFUTATION-WORKING-PROCESS.md) distills
the whole thing into copy-pasteable prompts — **Layer 1** standing mindset ·
**Layer 2** the adversary · **Layer 3** the orchestrator's process loops ·
**Layer 4** git — that drop into any project's agents. It's project-agnostic, the
prompt-text companion to
[`docs/FLEET-WORKING-PRINCIPLES.md`](docs/FLEET-WORKING-PRINCIPLES.md).

## Remote control (phone / web)

Claude Code's own **Remote Control** (`/remote-control`) is still useful for
Claude-backed windows: it lets you drive a local session from claude.ai/code or
the Claude mobile app — an outbound HTTPS connection, no ports opened. `fleet`
toggles it on live Claude members by injecting the slash command (no relaunch).
It's a per-member toggle, meant to be enabled piecemeal, checked, and turned off
again:

```sh
fleet remote-control on api    # enable one Claude member  (default action is "on")
fleet remote-control off api   # disable it again   (/remote-control is a toggle)
fleet remote-control on        # enable every live Claude member at once
fleet remote                   # show provider + remote-control status (active | - | n/a)
```

`fleet` reads each member's current state first, so `on`/`off` only act when they
actually change something. Enabled members appear **by name** in claude.ai/code
and the mobile app (signed in as you). Requires a Pro/Max/Team/Enterprise login
(`/login`); each enabled member is a separately controllable session on your
account.

For mixed Claude/Codex pairs, do not use provider UIs as the control plane.
Codex will not appear in Claude's mobile app, and manually steering two provider
consoles loses the shared audit trail. Treat `fleet` as the provider-neutral
remote layer instead: `fleet brief/status`, `fleet ask/send`, `fleet pair`,
`fleet handoff`, `fleet inbox`, and repo-local `RESUME.md` are the durable
interface. At a computer, the normal operator view remains tmux: attach to the
supervisor or workers directly, keep the full panes visible, and use `fleet`
commands from there. The mobile-friendly companion should be a Reality2
trust-group webapp / WASM hive: read-only status by default, explicit actions for
`ask`, `send`, `pair`, `handoff`, and `down`, with trust-group identity and audit
on every operator command. See
[`docs/R2-FLEET-CONTROL-HIVE.md`](docs/R2-FLEET-CONTROL-HIVE.md). Until that
exists, a mobile shell such as Termius still works, but it is a fallback, not the
intended mixed-provider UI.

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

## Auto-confirming routine prompts

Fleet members are semi-autonomous, so stopping to approve every routine action
gets in the way. A `PreToolUse` hook (`hooks/auto-approve.sh`) auto-approves a
**curated, non-destructive set** so members don't wait on the usual
press-enter-for-yes prompts — while anything risky or ambiguous still stops for
you. For most tools it never *forces* an outcome: worst case it stays silent and
the normal prompt appears. The **one deliberate exception** is the high-stakes
gate described below, which actively *denies* and escalates.

**Auto-approved:** read-only tools (`Read`, `Glob`, `Grep`, `LS`, `NotebookRead`,
`WebSearch`); file edits **inside the workspace**; safe shell reads; named
`git add`, `git commit`, non-force `git push`; and scoped build/test runners
(`cargo check|build|test`, `npm run test|build|lint|typecheck`, etc.). Safe
pipelines and `&&` chains are allowed only when every segment is itself allowed.

**Still prompts (everything else):** writes outside the repo, `rm`/`mv`/`dd`,
installs, arbitrary network (`curl`/`ssh` …), `sudo`, force-push, destructive git
ops (`reset`, `rebase`, `pull`, broad checkout/restore/clean), publish/install
runners, redirection/substitution, and unknown tools. Genuine decision questions
an agent raises ("which approach?") aren't permission prompts, so they always
wait for you.

**The firmware / key escalation gate (hard-deny).** Under
`--dangerously-skip-permissions` a silent fall-through would *run* a dangerous
action, so one high-stakes class is **actively denied and escalated to a human**
instead — flashing/signing firmware and minting/handling key material, where a
wrong move is irreversible. The hook denies (telling the agent to escalate with
the exact artifact/target/authority/reason) on:

- **commands** — `espflash` / `esptool` / `probe-rs download|run|erase` /
  `dfu-util` / `openocd` / `nrfjprog` … (flash); `openssl genpkey|genrsa|-sign|dgst`
  / `ssh-keygen` / `gpg --sign|--gen-key` … (key-gen / sign); `dd of=/dev/…`; and
  explicit `ota … sign|push` / `mint … cert` / `… write-persona` verbs;
- **writes** to key/signature artifacts — `*.key` `*.pem` `*.sig` `*.der` `*.p12`
  `*.seed` `tg_priv*` `*persona*.bin` `keystore*.db` `wallet*.dat` …

Source edits, builds, and reads are **unaffected** — only the dangerous
operations escalate. See the `hs_bash` / `hs_path` patterns in
`hooks/auto-approve.sh`.

It only acts inside a `.fleet` workspace, and is **on by default** for managed
members. Toggles (env): `FLEET_AUTOCONFIRM=off` disables it entirely;
`FLEET_AUTOCONFIRM_EDITS=off` keeps prompting for edits while still auto-approving
reads; `FLEET_FIRMWARE_GATE=off` disables the firmware/key gate. Tune the safe
set in `hooks/auto-approve.sh` (the `bash_safe` allowlist + the `hs_bash` /
`hs_path` gate).

## Operating doctrine

`fleet` carries a working *doctrine*, not just mechanics. Two short, generic,
project-agnostic docs hold it (project-specific context lives in a private
`primer.md`, never here):

- **[`docs/FLEET-WORKING-PRINCIPLES.md`](docs/FLEET-WORKING-PRINCIPLES.md)** —
  spec-first; secure-over-calm; **GitHub as the failsafe** (checkpoint to git so
  risky changes are *recoverable* rather than *blocked* — small named commits,
  never `git add -A`, a pre-push secret-scan, commit + push each verified unit);
  the permission / auto-approve + firmware-gate model; public-code /
  private-context; and roles (a coordinating **supervisor** that monitors but
  writes only its own infra repos; per-component **experts** do the hands-on work).
- **[`docs/THURISAZ-WORKING-MODE.md`](docs/THURISAZ-WORKING-MODE.md)** — the
  self-improving loop: honest conjecture → **cross-agent refutation (ideally by a
  different model)** → reputation → memory → reproducible re-audit. A non-trivial
  design isn't "fit" until a *peer* has tried to kill it; the human steers
  *direction*, the refutation loop runs itself within the failsafe.

Two principles worth stating outright:

- **Verify-then-record.** Confidence is what *survives* a genuine attempt to break
  it, not what looks right. Label work honestly; absence of counter-evidence is not
  evidence. The Codex tools and cross-agent refutation are how it's enforced.
- **Improve the tools alongside the work.** The fleet is the apparatus that builds
  the product, so a better apparatus compounds — `fleet` is meant to be sharpened
  *while* it runs, held to the same bar (refutation, a different-model perspective,
  annealing convergence, verify-then-record). The firmware-gate and the Codex tools
  are themselves examples.

> **Editing a *running* fleet is hot-wiring a live circuit** — the supervisor runs
> *on* the thing it's editing, so a bad change to the message bus / registry /
> hooks can take down the supervisor and every worker at once. The rule: prefer
> **additive** changes (new files/tools/toggles nothing depends on) over altering
> the live critical path; **test offline** on a stub workspace first; keep every
> change **one toggle from off** (hooks are read per-invocation, so a bad one is
> instantly disable-able); do invasive surgery (bus changes) only in a **calm,
> paused** window, never mid-flight.

## Direction (roadmap, not shipped)

Honest about where this is heading, not what's done:

- **Self-regulation.** The fleet should sense its own **health and load** and
  degrade *gracefully*. Today the message bus can degrade *silently*, and
  concurrent members can collectively hit provider **rate limits**. The direction
  is a fleet that detects both — backs off / re-routes / surfaces rather than
  failing quietly — and **never goes silently blind** (the supervisor's view should
  derive from ground truth — tmux, transcripts, git — that can't silently empty
  out). Spreading load across providers (Claude *and* Codex) is part of this.
- **Off the hand-rolled bus.** The tmux + file-mailbox + watchdog transport is
  pragmatic but fragile; the longer arc moves delivery + liveness onto native
  primitives (background sessions / agent-teams / a managed-agents API) behind the
  same `fleet` surface — a seam-swap, not a rewrite.

## What it does NOT do (by design)

- **Conflict prevention is detection-only.** It warns when two live sessions claim
  the same file; it does not block edits.
- **Reboot recovery resumes conversations, not in-flight tool runs.** A build
  interrupted by a crash is not auto-resumed — the member returns to where its
  transcript ended.
- **Messages become a turn in the peer's session.** `ask`/`send` deliver into the
  peer's live thread; hybrid delivery holds mail until the peer is at its prompt, so
  it won't corrupt a mid-task turn — but it does add a turn the peer must handle. That's
  by design (it's visible to you); just know inter-agent chatter consumes peer turns.

## Troubleshooting

- **`fleet status` shows everything `dead`, but the sessions are running.** `fleet`
  only sees members on its own tmux socket (`-L fleet`). A fleet started by older
  code, or a hand-rolled tmux, won't be matched — `fleet down` then `fleet up` to
  bring it under management.
- **The fleet dies when I close SSH / log out.** Your host sets
  `KillUserProcesses=yes`. Run `loginctl enable-linger "$USER"` once; `fleet up`
  already parks the tmux server under your per-user systemd manager so it survives.
  See [Surviving logout & reboot](#surviving-logout--reboot-remote-hosts).
- **Boot service starts but no agents appear, or `claude: not found`.** The systemd
  user manager has a minimal `PATH`. Ensure `claude` is on the unit's `PATH` or set
  `FLEET_CLAUDE_BIN` in `~/.config/systemd/user/fleet.service`.
- **Members don't pick their work back up after `fleet up`.** A resumed session
  idles at its prompt; `fleet up` nudges it (`carry on` by default). If you set
  `FLEET_RESUME_NUDGE=""` (or `resume_nudge = ""`) that's expected — nudge them
  yourself with `fleet send <id> "carry on"`.
- **Claude says `/usage-credits` or "request more usage from your admin".** That
  is hard Claude usage/credits exhaustion, not a transient rate limit. `fleet`
  reports it as provider-exhausted and the API watchdog will not keep typing
  `try again`. Request more Claude usage from the admin, or move the repo to
  Codex with `fleet handoff <id> --stop-source` (or `fleet pair <id>` first, if
  no Codex companion is already running).
- **`fleet up` says "another 'fleet up' is in progress — skipping".** A boot service
  and a manual run raced; the per-workspace lock is doing its job. It's already up,
  or will be once the first run finishes.

## Project layout

```
bin/fleet              the CLI (the only entrypoint)
bin/codex-review       run Codex read-only as a different-model adversarial reviewer
bin/codex-scan         recurring Codex full-pass audit (security/usability/sovereignty)
lib/                   common, manifest parser, registry, tmux, restart, provider
                       (claude|codex), comms (mailboxes, ask/send), responder, run-child
hooks/                 self-reporting hooks: session-start, prompt-submit, post-edit,
                       on-stop, session-end; plus auto-approve (PreToolUse: auto-confirms
                       routine prompts + the firmware/key escalation gate)
skill/SUPERVISOR.md    role prompt for the supervising session
commands/fleet.md      the /fleet slash command (installed into .claude/commands/)
templates/             example fleet.toml + primer.md + illustrative hooks block
tests/smoke.sh         self-contained smoke test (syntax + lifecycle vs a stub)
.github/workflows/     CI: runs the smoke test on every push / PR
```

Runtime state lives per-workspace under `<workspace>/.fleet/` (manifest, state,
run bindings, mailboxes, logs) — never in this repo.

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
