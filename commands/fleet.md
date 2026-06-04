---
description: Run a claude-fleet command (brief, status, up, ask, send, remote-control, …)
argument-hint: <subcommand> [args]
allowed-tools: Bash(fleet:*)
---

Output of `fleet $ARGUMENTS`:

!`fleet $ARGUMENTS`

Report the result concisely — do not restate the whole table:

- `brief` / `status` / `conflicts`: lead with anything that needs the user or is
  waiting on them (quote the actual question a member is waiting on); skip the rest.
- actions (`up` / `down` / `restart` / `dispatch` / `order` / `remote-control`):
  confirm what happened in one line.
- `ask` / `send` / `broadcast`: confirm it was delivered or queued.
- If the command errored, say what failed and the one-line fix.
- If no subcommand was given, the output is the command list — show it and suggest
  `/fleet brief`.
