# Operations — running a fleet day-to-day

Onboarding repositories, the `RESUME.md` handoff discipline, the supervisor,
the `/fleet` slash command, surviving logout & reboot, remote control, and
troubleshooting. For install and quick start, see the [README](../README.md).

## Onboard a fleet repository

After adding a `[[child]]` to `fleet.toml`, run:

```sh
fleet init-repo <id>   # omit id to onboard every manifest member
```

The command creates only missing files; it never overwrites repository content:

- `AGENTS.md` — a short shared fleet contract plus the repo-specific map: role,
  canonical authority, upstream dependencies, downstream consumers, ownership,
  invariants, and verification commands.
- `DECISIONS.md` — append-only decisions and later appropriateness reviews, including
  real decision-maker, authority basis, rationale, alternatives, outcomes, and evidence.
- `RESUME.md` — one current takeover snapshot.

It also installs the fleet Git hooks: the pre-push publish guard and commit-attribution
hook, preserving and chaining pre-existing hooks.
The shared launch prompt tells every managed agent to consult `AGENTS.md` and
`DECISIONS.md` before edits. `fleet doctor` reports missing files and unresolved
`TODO(fleet-onboarding)` map fields; those fields are a hold on cross-repo and behavioural
work so an agent cannot guess dependency direction or authority.

Once `DECISIONS.md` exists, each newly published non-merge commit must either update the
ledger or carry `Decision-Log: D-YYYYMMDD-NN`; routine work uses the explicit,
reviewable `Decision-Log: none`. Enforcement is at push rather than commit so local safety
checkpoints are never blocked. The wizard runs `init-repo` automatically.

## Repo-local handoff state — `RESUME.md`

Every implementation worker is expected to maintain `<repo>/RESUME.md` as the
durable takeover record. The file should be updated after each meaningful turn
and before the worker goes idle. Keep one concise authoritative current state,
not an ever-growing diary or multiple competing "current" sections. The generated
decision ledger outranks RESUME prose for operational choices. Include:

- current objective
- last verified state, with commands/results
- next concrete actions
- changed files / claims
- blockers, risks, and open decisions
- branch/commit and any "do not assume" notes
- applicable decision IDs and GitHub upstream/push state

Use `fleet init-resume [id]` to scaffold the file for one member, or
`fleet init-resume` for every manifest child. `fleet handoff` includes this file
ahead of transcript excerpts, and `fleet doctor` reports managed non-adversary
workers whose `RESUME.md` is missing, empty, still full of `TODO` placeholders,
stale, or over 64 KiB. It also reports GitHub-backed branches with no upstream or
local commits ahead of upstream. Tune with `FLEET_RESUME_FILE`,
`FLEET_RESUME_CHECK=off`, `FLEET_RESUME_TODO_CHECK=off`,
`FLEET_RESUME_STALE_SECS`, `FLEET_RESUME_MAX_BYTES`, and
`FLEET_GITHUB_SYNC_CHECK=off`.

## The supervisor

`fleet up` starts a dedicated **supervisor** window — an agent session primed with
the role in `skill/SUPERVISOR.md` — alongside the members. One active coordinating
lane is the default; add an opposite-provider warm standby only when its resilience
benefit justifies another agent. Start or jump to it directly with:

```sh
fleet supervise            # start it (or tell you it's already up)
fleet supervise --pair     # optionally add a silent opposite-provider standby
fleet attach supervisor    # drop into it
```

It's a first-class member (id `supervisor`): it self-reports, can be messaged
(`fleet send supervisor "..."`), and resumes on the next `fleet up`. It is the
**single workspace-root session** — oversight and cross-cutting coordination;
per-repo work belongs to the member experts, so there's no separate "root"
worker. Just talk to it: *"status?"*, *"anything conflicting?"*, *"restart api"*,
*"bring the suite back up"*. Use `fleet up --no-supervisor` to skip it.

## The `/fleet` slash command

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

## Workspace identity & isolation

Each workspace is isolated automatically. Its canonical path produces a stable
tmux socket/session and systemd unit name, so fleets in different folders can
run concurrently even when their child ids match. Run commands inside the
desired workspace (or set `FLEET_WORKSPACE`); `fleet identity` shows the
resolved names. `.fleet/env` may still set explicit `FLEET_TMUX_SOCKET`,
`FLEET_TMUX_SESSION`, or `FLEET_SERVICE_NAME` overrides.

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
[`R2-FLEET-CONTROL-HIVE.md`](R2-FLEET-CONTROL-HIVE.md). Until that
exists, a mobile shell such as Termius still works, but it is a fallback, not the
intended mixed-provider UI.

## Context, tokens, and the agent clock

A long-lived `--resume` session re-processes its whole transcript on every turn, so
**token cost climbs with session age** — it is the dominant cost in a running fleet, and
it is invisible unless you go looking. Measured on one lane's own transcript over 29,364
turns:

| | tokens |
|---|---|
| fixed floor (system prompt, tools, primer) | 23,082 |
| **mean context re-processed per turn** | **406,780** |
| p90 | 692,191 |
| peak | 999,801 |
| **total input re-processed, that one lane** | **11.94 billion** |

Three mechanisms keep that in check. All are on by default; each can be turned off.

### `fleet tokens` — the meter

Reads each live member's **last-turn context** straight from its transcript and shows it
against the ceiling. This is the number that matters: not what a turn cost to *produce*,
but what every subsequent turn has to *re-read*.

The two providers name the same quantity differently — Claude reports
`cache_read_input_tokens` + `cache_creation_input_tokens`, Codex reports
`last_token_usage.input_tokens`. `fleet_ctx_tokens` handles both. **If you add a third
provider you must add its arm too**, with a fixture in `tests/faculty.sh`: a meter that
does not know a provider's field names reports `0`, which is also its word for *"cannot
read"*, so the blindness is silent. That exact defect shipped and hid for weeks
(D-20260807-140).

| variable | default | what it does |
|---|---|---|
| `FLEET_CTX_CEILING` | `1000000` | the context window you are measuring against |
| `FLEET_CTX_WARN_PCT` | `90` | `fleet tokens` flags a member at or above this |
| `FLEET_CTX_WARN_TOKENS` | — | absolute alternative to the percentage |
| `FLEET_CTX_TAIL_BYTES` | `300000` | how much transcript tail to scan for the figure |

### Proactive compaction

When a managed worker returns to its prompt **idle with an empty inbox** and its context
is over `FLEET_COMPACT_AT_PCT` of the ceiling, `fleet` injects `/compact`. `RESUME.md`
and the decision ledger anchor real state, so a compaction does not lose working context.

A **hard ceiling** covers the case the routine trigger cannot: a worker kept busy by a
steady stream of peer mail never *is* idle with an empty inbox, and would otherwise grow
until the provider auto-compacts at ~95% — the most expensive compaction there is, at
maximum context, unplanned, mid-task. The hard ceiling runs **before** the inbox drain
and defers it; mail waits one turn and lands against a fresh context. (Draining injects
text into the pane, and `/compact` keystroked onto a half-submitted message corrupts it.)

| variable | default | what it does |
|---|---|---|
| `FLEET_COMPACT_AT_PCT` | `70` | routine trigger, idle + empty inbox only. `0` disables |
| `FLEET_COMPACT_HARD_PCT` | `85` | fires even with mail queued; defers the drain. `0` disables |
| `FLEET_COMPACT_EVERY` | `40` | turn-count backstop, **only** when the meter reads unknown |
| `FLEET_COMPACT_SKIP` | — | space-separated member ids to exempt entirely |

> **Why the backstop is conditional.** A compaction destroys the cached prefix, so a
> turn-timer that fires at 5% of the ceiling is a pure loss. It is insurance against a
> blind meter, never a second schedule.

> **`70` is not a derived number.** Lowering it cuts per-turn cost roughly linearly
> (400k ≈ 0.60× the cost of 700k, still ~355 turns between compactions), but a
> compaction also costs re-derivation — the agent re-reads files, re-derives state,
> re-asks peers — and that side has never been measured. Change it deliberately.

### Tool-output budget

A single fat command output is read once and then re-sent on every turn until the next
compaction. A 50KB result is ~12k tokens of permanent residency. Measured on a live lane:
results over 4KB are **4.7% of results but 45% of all tool-result bytes**.

The `PostToolUse` hook **spills rather than truncates**. The complete output is written to
`<workspace>/.fleet/spill/`, the head and tail stay verbatim inline, flagged lines
(errors, failures, verdicts) are lifted out of the elided middle, and the marker states
exactly how many bytes and lines moved and where to read them. Nothing is lost — it is
deferred, and the agent pays for the middle only if it asks.

Head and tail alone were not enough: replayed against 161 real over-budget results,
**10.6% had their only decisive line in the elided middle**, concentrated in `fleet inbox`
and `grep` output where every line is its own record and there is no verdict at the
bottom. Carrying the flagged lines drops that to 0% for 3 points of saving.

| variable | default | what it does |
|---|---|---|
| `FLEET_OUTPUT_BUDGET` | `on` | `off` disables the hook entirely |
| `FLEET_OUTPUT_BUDGET_BYTES` | `4000` | inline budget; head and tail split it |
| `FLEET_OUTPUT_HL_MAX` | `12` | flagged middle lines carried inline; the remainder is announced |
| `FLEET_OUTPUT_SPILL_KEEP` | `200` | spill files retained per workspace |

Claude members only — it replies with `updatedToolOutput`, a Claude Code hook contract
with no verified Codex equivalent. Spill files are gitignored by `fleet init`.

### The agent clock

**An agent has no running clock.** It learns the time only when something is injected into
its thread, and its system prompt dates only the session start. Two separate things give
it back:

1. **Stamps** — every injected peer message carries local time and a named zone:
   `[fleet msg from core · 2026-08-07 08:09 NZST] …`. That fixes *instants*.
2. **The clock line** — emitted each turn as `additionalContext`, this is *duration*,
   which is what "should I hurry up?" is actually made of:

```
[fleet clock] 2026-08-07 08:11 NZST · 3h 10m since your last turn · 5h 30m on this task · session 2d 4h
[fleet clock] decision d901 due 2026-08-08 17:00 — 1d 1h left
```

The deadline line appears **only when it could change what the agent does** — inside
`FLEET_CLOCK_DUE_H`, or already overdue. A clock that reports a three-week deadline every
turn trains the reader to skip the line.

Every figure is **recomputed from epochs at read time, never stored**. A stored *"2 days
left"* rots like any other unrecomputed number, and an agent has no clock with which to
notice — which is the defect the clock exists to fix.

| variable | default | what it does |
|---|---|---|
| `FLEET_CLOCK` | `on` | `off` suppresses the clock line; task recording continues |
| `FLEET_CLOCK_DUE_H` | `48` | how near a deadline must be before it is mentioned. `0` never |

Cost: ~35 tokens per turn, against a measured mean context of 406,780.

Set deadlines with `fleet decision add --due` / `fleet decide --due`, which accept what
someone actually types: `2026-08-08`, `2026-08-08 17:00`, `friday`, `+2 days`,
`tomorrow 09:00`. An unparseable deadline is **refused, not defaulted** — a deadline that
silently became *now* or *never* would be discovered by missing the date.

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
  Codex with `fleet failover --provider codex <id>` or
  `fleet handoff --provider codex --stop-source <id>` (or `fleet pair <id>`
  first, if no Codex companion is already running). Use
  `fleet failover --provider codex --all` when the Claude account is exhausted
  fleet-wide and the supervisor cannot coordinate the switch itself.
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
hooks/git/             managed pre-push publishing and commit-attribution hooks
skill/SUPERVISOR.md    role prompt for the supervising session
commands/fleet.md      the /fleet slash command (installed into .claude/commands/)
templates/             workspace examples plus non-overwriting repo onboarding files
templates/repo/        AGENTS.md + DECISIONS.md + RESUME.md for a new fleet member
tests/smoke.sh         self-contained smoke test (syntax + lifecycle vs a stub)
.github/workflows/     CI: runs the smoke test on every push / PR
```

Runtime state lives per-workspace under `<workspace>/.fleet/` (manifest, state,
run bindings, mailboxes, logs) — never in this repo.
