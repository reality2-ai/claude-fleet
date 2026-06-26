# R2 Fleet Control Hive

This is the intended mobile/web control shape for mixed Claude/Codex fleets.

Claude Code Remote Control is useful for Claude-backed windows, but it is not a
fleet control plane: Codex windows do not appear there, and paired repos need one
shared audit trail. The provider-neutral boundary is `fleet`.

This does not replace tmux. At a computer, tmux remains the normal fleet view:
the operator can attach to the supervisor, inspect worker panes, and use the full
terminal affordance. The R2 control hive is for mobile, tablet, ambient status,
and constrained actions where a terminal emulator is clumsy.

## Shape

Use the existing Reality2 webapp / WASM hive pattern:

- Browser hive: mobile-first UI, trust-group identity, local intent signing.
- Controller hive: runs beside the fleet host, serves the webapp, exposes `/r2`
  WebSocket events, and executes a narrow allowlist of `fleet` commands.
- `fleet`: remains the source of truth for agent state, mailboxes, logs,
  handoff packets, `RESUME.md` freshness, and provider-specific launch details.

The browser hive must not talk directly to Claude or Codex. It emits operator
commands to the controller hive; the controller turns accepted commands into
`fleet` invocations and broadcasts the resulting state.

## Minimal Event Surface

Read/status events:

- `r2.fleet.status.request`
- `r2.fleet.status.snapshot`
- `r2.fleet.brief.request`
- `r2.fleet.brief.snapshot`
- `r2.fleet.inbox.request`
- `r2.fleet.inbox.snapshot`

Operator commands:

- `r2.fleet.cmd.ask`
- `r2.fleet.cmd.send`
- `r2.fleet.cmd.pair`
- `r2.fleet.cmd.handoff`
- `r2.fleet.cmd.down`

Each command needs a `req_id`, operator identity, target member(s), command
payload, and a resulting `r2.fleet.cmd.response` with stdout/stderr summary and
exit status. Destructive commands should require a stronger trust-group role or
an explicit confirmation step in the browser hive.

## Command Allowlist

Start with read-mostly control:

```sh
fleet brief
fleet status
fleet conflicts
fleet inbox [id]
fleet remote [id]
```

Then allow bounded actions:

```sh
fleet ask <to> "<question>"
fleet send <to> "<message>"
fleet pair [id]
fleet handoff <from> [to-id]
fleet down <id>
```

Do not expose arbitrary shell. Do not expose direct provider commands. Keep
`restart`, `dispatch`, and `remote-control` behind a stronger operator role until
the trust and audit flow is proven.

## Mobile UX

The first screen should be `fleet brief`: what needs the operator, what is
working, what is idle, what is conflicted, and whether `RESUME.md` is healthy.
Each repo can then show its Claude/Codex pair, current task, inbox, claimed
files, last verification, and one-touch actions for `ask`, `send`, `pair`, and
`handoff`.

This gives the convenience of Claude mobile Remote Control without tying the
fleet to Claude as the only visible provider.
