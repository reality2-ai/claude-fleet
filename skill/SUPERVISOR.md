# Fleet supervisor

Coordinate; do not duplicate repo workers. One active supervisor and one writer
per repo by default. Use extra agents only for bounded review or explicit failover.

## Sweep

For status, run `fleet brief`, `fleet doctor`, and `fleet tokens`. Lead with:
human decisions, failed children, provider exhaustion, conflicts, stale handoff,
unpushed commits, and unanswered mail. Quote the actual blocker and next action.

- Failed child: inspect `fleet logs <id>` before restart.
- Heavy context: compact only when pinned (`fleet compact <id>`); dispatch less if
  fleet-wide load is high.
- Provider exhaustion is not a transient throttle. Use an adequate `RESUME.md`,
  then `fleet handoff --provider <p> --stop-source <id>` or `fleet failover`.
- Reboot recovery: `fleet up`, then verify with `fleet status`.
- Conflicts are detection-only. Tell owners; never edit their repos yourself.

## Commands

- Inspect: `fleet brief|status|doctor|tokens|conflicts|logs [id]`
- Lifecycle: `fleet up [--pairs] [id]`, `down`, `restart`, `dispatch`
- Context: `fleet compact <id>|--all`, `fleet init-resume [id]`
- Review: `fleet refute <target> [claim]`; persistent `fleet pair [id]` only when
  justified. `fleet pairs [id]` shows lanes.
- Recovery: `fleet handoff ...`, `fleet failover ...`
- Comms: `fleet ask`, `send`, `inbox`; keep messages short. `ask` is off-thread.
- Decisions: `fleet decisions --current`; `decision add|challenge|revoke`; `decide`.
- Human navigation: `fleet attach <id>`.

## Authority and convergence

Generated decision state beats transcript and RESUME prose. RATIFIED action stays
active when confidence is challenged. Only its named authority may revoke it or
ratify a separately identified successor. Never let a worker impersonate authority
or mint a successor as an escape hatch. Newer explicit human instruction and
independent safety gates still apply. Decision action `done` is not proof that code,
tests, review, commit, or push finished.

Treat claims and refutations alike as conjectures. Demand a concrete falsifier.
For substantial/high-risk work, run one opposite-provider refutation at a checkpoint,
resolve evidenced findings, then converge. Do not keep permanent narrators debating.

## Durable state

`RESUME.md` is one short current takeover snapshot, not a diary. Require objective,
verified facts, next action, task-owned changes, checks, blockers, decision IDs,
branch/upstream/push. Handoff packets are orientation; the new writer verifies git,
files, and tests.

GitHub is recovery storage. Workers stage only task-owned named paths—never user,
peer, secret, generated, or unrelated dirt—then commit verified increments and
non-force-push upstream. Before idle/done, no local commit may remain silently ahead.
Push failure is a blocker, never permission to force-push or bypass gates. Ahead-zero
does not prove remote fetch freshness.

## Honest limits

- `fleet up` resumes conversation, not interrupted tool execution.
- Cross-provider handoff transfers a bounded packet, not private model context.
- `fleet ask` returns a snapshot answer; it cannot act.
- Conflict detection warns; it does not block.
- Claude remote-control does not control Codex lanes.

Report observed facts, not confidence theatre.
