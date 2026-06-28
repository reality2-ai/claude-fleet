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

---

## Bench verdict (2026-06-29) + decision

Ran the bench on throwaway Claude bg agents. Findings:

- **Q1 — PASS.** `claude attach <id>` inside a tmux window renders the **full live session TUI** (verified: the
  pane showed the real conversation, prompt box, status bar, footer). `claude logs <id>` streams it,
  `claude stop <id>` ends it cleanly, `claude agents --json` lists bg agents natively (name, sessionId, state).
  ⇒ **The unified tmux-window view is achievable**, and attach/logs/stop/agents-json map 1:1 onto the faculty
  `attach`/`stream`/`unmount`/`liveness` verbs.
- **Q2 — single-controller.** A *live* `--bg` agent **cannot** be injected into via `-p --resume` — it errors
  `Session … is currently running as a background agent (bg)`. Programmatic delivery is therefore NOT
  "inject into a running bg agent"; it is **drive the durable session turn-by-turn** with
  `claude -p --resume <sid> --output-format stream-json "<msg>"` (no keystrokes → the unsubmitted-Enter bug is
  gone), viewing via `claude --resume`/`attach` in a tmux window when idle.

**This yields two models:**
- **Model A (live bg + attach):** continuous `claude --bg` workers, unified view via attach, native
  liveness/logs/stop — but peer-message delivery stays keystroke-based (attach+type), so it does NOT fix the
  core delivery bug. Easy observability win only.
- **Model B (fleet-driven turns):** worker = a durable resumable session the fleet drives turn-by-turn via
  `-p --resume stream-json`. Delivery becomes fully programmatic (**fixes the bug**); human views via
  `claude --resume`/attach in a tmux window on demand. Cost: the fleet runs a controller loop per worker.

**DECISION (Roy, carry-on 2026-06-29): Model B, prototype-first.** Build a minimal Model-B controller path for
ONE throwaway worker (programmatic turn delivery + resumable session + attach-in-tmux view), prove it live, then
wire it behind `FLEET_FACULTY_ADAPTER=claude-bg` with `cli-tmux` as default/fallback. Model B is the only path
that delivers BOTH the unified view (attach-in-tmux) AND the delivery fix (programmatic turns). The controller
loop is the fleet-side cost, and it aligns with the entity/faculty model (the durable session is the entity; the
fleet drives the faculty per message).

## Landed so far (2026-06-29)

- **`lib/faculty-bg.sh`** — the proven delivery primitive `fleet_bg_deliver_turn <sid> <cwd> <text>`
  (`claude -p --resume … --output-format json`, keystroke-free) + `fleet_bg_drain <to>` (at-least-once inbox
  drain via turns). `faculty_deliver` gains a `claude-bg` branch → `fleet_bg_drain`. Sourced in bin/fleet,
  **default-off** (FLEET_FACULTY_ADAPTER=cli-tmux unchanged) → zero live-fleet impact.
- Tests: hermetic `tests/faculty.sh` (40/0) + `tests/live-bench-bg.sh` (live, non-CI: proves programmatic
  delivery + cross-turn persistence through the shipped primitive — returned 42). config/liveness/smoke green.

**Still to build (next):** the worker LIFECYCLE under claude-bg — start workers as durable sessions, the
controller loop driving autonomous turns, and `faculty_mount`/`attach` mapping a worker to a tmux window running
`claude attach <id>` (the unified-view render). Then pilot one real worker behind the flag.
