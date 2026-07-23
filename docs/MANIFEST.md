# The manifest — `fleet.toml`

Full reference for the fleet manifest: fields and restart semantics, versioning
your config, and the Claude/Codex provider options. For install and quick start,
see the [README](../README.md).

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
Optional: `name`, `seed`, `permission_mode` (see [Safety & permissions](SAFETY.md#safety--permissions)),
`provider` (`claude` *(default)* or `codex` — see [Providers](#providers--claude-code-or-codex)),
and `resume_nudge` (below).

A resumed session reopens **idle at its prompt**, so `fleet up` nudges each
resumed member to pick its work back up — by default with `carry on`. Override
per child with `resume_nudge = "…"` in `fleet.toml`, or globally with
`FLEET_RESUME_NUDGE`; set either to `""` to leave members idle on resume.
Set `FLEET_START_NUDGE="carry on"` when fresh sessions should receive the same
nudge after their seed. `FLEET_SUPERVISOR_PERMISSION_MODE=bypassPermissions`
lets the supervisor run unattended when the workspace explicitly opts into it.

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

Codex `permission_mode = "plan"` means autonomous read-only review:
`--sandbox read-only --ask-for-approval never`. It can investigate without a
human prompt, while the sandbox remains the write boundary.

`provider` is also settable fleet-wide with `FLEET_AGENT_PROVIDER=codex`, and the
binary / model / profile / sandbox / approval via `FLEET_CODEX_BIN` ·
`FLEET_CODEX_MODEL` · `FLEET_CODEX_PROFILE` · `FLEET_CODEX_SANDBOX` ·
`FLEET_CODEX_APPROVAL`. The fleet wires its self-reporting + permission hooks into
Codex too (via Codex's `--cd`, hook-config, and sandbox flags), so a Codex member
self-reports, is messaged, and is gated just like a Claude one. Running a **mix**
is deliberate: a different model is a different *perspective* — see
[Codex as an adversarial helper](DOCTRINE.md#codex-as-an-adversarial-helper).

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
fleet pairs core                   # show the logical pair and its provider lanes
fleet pair-send core "status?"     # send one note to every lane in the pair
fleet pair-ask core "what changed?" # ask every lane off-thread
fleet failover --provider codex --all # non-AI switch-over to Codex writers
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

`fleet pair` is the standing adversarial co-work mode. It starts an
opposite-provider twin in the same repo as a member (`core` + `core-codex`, for
example). The default ownership rule is **one writer per repo**: Claude lanes are
normally the resident writers, while Codex twins are read-only pair programmers
and fail-over standbys. Their primary job is to question the writer: challenge
assumptions, look for counterexamples, attack test gaps, review security and
edge cases, and propose concrete patches or tests for the writer to apply. They
do not edit the shared working tree unless `fleet handoff` promotes them to the
sole takeover writer.

Failover stays explicit: when Claude hits a hard usage limit,
`fleet handoff core --stop-source` promotes an existing standby or starts the
opposite provider as takeover writer, and stops the source lane so both engines
are never writers in the same repo at once.

Persistent adversarial pair programming is opt-in with `fleet up --pairs` or
`FLEET_PAIR_ON_UP=on` — use it only when persistent opposite-provider read-only
standbys are worth the extra agents; on-demand `fleet refute`, `fleet pair`,
`fleet handoff`, and `fleet failover` remain available without making every
startup a debate between permanent twins. Tune it with `FLEET_PAIR_PERMISSION_MODE=plan`,
`FLEET_PAIR_RESUME_LINES`, `FLEET_PAIR_GIT_LINES`, and
`FLEET_PAIR_MAX_CLAIMS`. The companion launch prompt is deliberately compact so
large `RESUME.md` files do not hit tmux/CLI argument limits.

Longer-lived shared memory should not be shoved into launch prompts. The right
next layer is the Anthill-style directed weighted cyclic graph with provenance:
facts, claims, findings, assumptions, tests, and handoff notes become weighted
nodes/edges with source, timestamp, agent, provider, and verification status.
Companion prompts should receive only a compact frontier plus retrieval commands;
the graph supplies the rest on demand and gives both engines a shared, auditable
memory that is smaller than a transcript and richer than a flat `RESUME.md`.

The pair facade keeps the operator model simple: target the logical pair id
(`core`) while fleet routes to the concrete lanes (`core` and `core-codex`).
Use `fleet pairs` to inspect lanes, `fleet pair-send` to broadcast a short
instruction to both, and `fleet pair-ask` when you want independent off-thread
answers from both providers. `fleet pairs` shows the concrete lane role so it is
clear which lane is writer and which is read-only standby.

The scoped track-2 replacement is in
[`R2-FLEET-RUNTIME-SCOPE.md`](R2-FLEET-RUNTIME-SCOPE.md): a Rust
`r2-fleetd` runtime with a tmux-like TUI, typed agent roles, one-writer leases,
event logging, worktree isolation, and a later mobile/web hive.
