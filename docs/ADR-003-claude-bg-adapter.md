# ADR-003 — The `claude-bg` adapter: programmatic delivery without losing the unified tmux view

**Status:** Design pass (2026-06-29). Task 3 of the faculty migration. Depends on the faculty seam +
call-site adoption (landed) — see [ADR-002](ADR-002-multibrained-entity-fleet.md) and
[the contract](FACULTY-ADAPTER-CONTRACT.md). **No code yet; this records the design + the open questions a
bench must settle before implementing.**

---

## Where we are (honest status)

We are **not yet using native subagents/sessions.** Every worker — Claude *and* Codex — is still an
**individually-running CLI process in a tmux window** (the `cli-tmux` adapter). Everything shipped this session
is the seam + liveness hardening that makes switching *possible*; the switch itself is this adapter.

## The requirement that drives the design (Roy, 2026-06-29)

> **All workers — both Claude and Codex — must remain visible as windows in the one `fleet` tmux session, with
> uniform `fleet attach <id>`.** Do not scatter them into provider-specific views.

This is non-negotiable UX and a real strength of the current model. It constrains — and may *redirect* — the
substrate choice below.

## The problem the adapter is meant to solve

Exactly one thing tmux cannot fix (per the cli-tmux backlog in the contract): **delivery.** We deliver messages
by typing into a TUI with `send-keys`; a dropped/!submitted Enter is the recurring stuck-message bug. Native
programmatic delivery removes that bug class. *Observation/liveness/recovery are already hardened on tmux* —
so the adapter's job is narrowly **delivery (and the liveness/stream that come with a programmatic channel)**,
NOT replacing the window the human sees.

## Available substrate (verified 2026-06-29)

- **claude 2.1.195**: `--bg/--background` (start a background agent), `claude agents [--json]` (agent view +
  scriptable list), `claude -p --resume <id> --input-format stream-json --output-format stream-json`
  (programmatic streaming I/O to a session), `--fork-session`, `--agents <json>` (custom subagents).
- **codex 0.142.3**: durable sessions (`resume`), `app-server` daemon + `remote-control` + `--remote` TUI
  attach, `exec --json` / `--output-schema` / `--output-last-message`.

## The design — tmux as the DISPLAY plane, native session as the CONTROL plane

The faculty contract already separates `attach` (display) from `deliver`/`liveness` (control). Exploit that:

- **`attach` / display stays tmux.** Each worker remains one window in the `fleet` session (unified view +
  `fleet attach` unchanged, both providers). The window *shows* the session.
- **`deliver` goes programmatic.** Messages are delivered over the native channel
  (`claude -p --resume … stream-json` / codex app-server), **not** `send-keys` — killing the stuck-message bug.
- **`liveness` / `stream` go native** (`claude agents --json` / `codex --json`) instead of pane-scraping.

The whole adapter is therefore: *keep the window, change the wire.*

## The crux — open questions a bench MUST settle first (conjectures to refute)

The design above assumes a session can be **both shown in a tmux window AND driven programmatically**. That is
NOT yet proven and is the make-or-break:

- **Q1.** Can a live Claude background agent be *viewed/attached inside a tmux window* (so the unified window
  list holds), rather than only in `claude agents`?
- **Q2.** Can that same session accept **programmatic delivery** (`-p --resume stream-json`) *while* a tmux
  window is viewing it — delivered as one coherent turn — without the two I/O paths fighting?
- **Q3.** Codex equivalent: `app-server` daemon + `--remote` into a tmux window + programmatic send — same
  coherence?
- **Q4.** Do one-writer-per-repo + worktree isolation + `--dangerously-skip-permissions` still hold under the
  background/agent path?

## The honest fork the bench decides

- **If Q1+Q2 hold:** implement `claude-bg` as above (window = view, wire = stream-json). Best outcome:
  unified view preserved *and* delivery fixed.
- **If they do NOT** (a session can't be both viewed-in-tmux and API-driven): then preserving the unified
  window view (the hard requirement) means the substrate move is **not** `--bg` at all but **tmux control mode
  (`tmux -CC`)** — subscribe to tmux's own structured event protocol for native liveness/stream and use its
  programmatic input path, keeping workers as ordinary tmux windows. This would *redirect* the substrate move
  while honouring the requirement. (Recorded here so the requirement, not the technology, wins.)

## Rollout (incremental, behind a flag, harden-first)

1. **Bench Q1–Q4** on one throwaway Claude worker + one Codex worker (no fleet impact).
2. Implement the winning path as a `claude-bg` (and `codex-daemon`) branch under `FLEET_FACULTY_ADAPTER`, with
   `cli-tmux` remaining the default + fallback.
3. Pilot ONE real worker on it; compare delivery reliability vs cli-tmux; never the supervisor first.
4. Roll out per-worker only after the stuck-message class is observably gone.

**Decision trigger:** run the bench next; do not write the adapter until Q1/Q2 (or the control-mode fork) is
settled.
