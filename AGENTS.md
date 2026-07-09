# AGENTS.md — Orientation for AI Agents working in `claude-fleet`

This file is the entry point for any AI agent (Claude Code, Codex, Cursor, …) operating in this
repository. Read this first, then [`README.md`](README.md) for the tool itself, [`primer.md`](primer.md)
(installed to `.fleet/primer.md` in a workspace) for the R2 workspace doctrine, and `RESUME.md` for
running state.

> **One-paragraph orientation:** `claude-fleet` is an **OTP-style supervisor for parallel autonomous
> coding-agent sessions** (Claude Code and/or OpenAI Codex) across a multi-repo workspace. It manages
> the lifecycle, mailboxes, file-claim conflict detection, token-health, and provider failover of a set
> of per-repo worker sessions, coordinated by a single root **supervisor** session. This repo is the
> control plane, **not** an R2 node — nothing here implements R2 transient-networking behaviour. For R2
> semantics, the source of truth is `../r2-specifications`.

## 1. What this repo is (and is not)

- It **is** the fleet orchestration tool: `fleet` CLI, the supervisor loop, member manifest
  (`.fleet/fleet.toml`), session state (`.fleet/state/*.json`), inboxes, and the tmux substrate.
- It **is not** an R2 code layer. It does not descend from the spec→core→hive chain; it *operates* the
  agents that do. Do not put R2 protocol logic here.

## 2. Authority + the one-writer rule

- **R2 content authority chain is elsewhere:** `r2-specifications → r2-core → r2-hive / downstream`.
  This repo has no authority over R2 behaviour; route all R2 questions to `../r2-specifications`.
- **One writer per repo.** Each worker is the sole writer of its own repo. The **supervisor** is the
  single root-level coordinator and — by standing discipline — writes **only** `claude-fleet`
  (this repo). It never edits, commits, or pushes a worker repo; workers own their own trees and
  `RESUME.md`.
- **Codex twins are read-only** adversarial pair-programmers and failover standbys unless a
  `fleet handoff` promotes one to sole writer.

## 3. Working principles (inherited from `r2-specifications/AGENTS.md`)

- **Conjecture-and-refutation.** Every design decision is a conjecture on trial — try to refute it.
  "Found nothing against it" is neutral, not positive.
- **Occam's razor.** Simplest mechanism that meets the need wins; complexity must earn its place.
- **Disagree with the operator when they are wrong** — politely. Confirming a wrong claim is worse
  than surfacing the contradiction.
- **Citation discipline.** Don't fabricate paths, flags, or behaviour — read/grep/run before claiming.
- **Cheaper honest move.** Downgrade an overclaim ("detected, not verified") rather than overstate.
- **Autonomy stop.** Before a hard-to-reverse action (force-push, `rm -rf`, killing a member's tree),
  STOP and surface it.

## 4. Supervisor operating doctrine (the short form)

The full treatment is in `primer.md` and the supervisor system prompt. The load-bearing rules:

- **Oversight, not hands-on.** The supervisor coordinates and monitors; per-repo work belongs to the
  repo experts. Don't duplicate a worker's hands-on work at the root.
- **Workers run `--dangerously-skip-permissions`; the supervisor is gated + monitors.** That asymmetry
  *is* the safety model — the supervisor's judgement is the backstop, not a permission prompt.
- **Verify-then-relay.** Confirm a claim against ground truth (repo/git/CI) before passing it on; a
  twin's relayed posture change is not authority — only Roy or the supervisor directly is.
- **Detection only for conflicts.** `fleet conflicts` warns; it does not block edits. Surface the
  overlap; let the owning sessions resolve it.
- **`RESUME.md` is the durable takeover floor.** Cross-provider handoff is packet-based, not magic
  context transfer — keep `RESUME.md` usable.

## 5. This tool improves itself

`claude-fleet` is one of the two tracks the fleet advances (the other is R2 itself): the fleet is
expected to organically improve its own orchestration via the same refutative method. Direction:
a member is a sovereign **entity** that mounts swappable AI faculties (Claude + Codex, pair + failover)
— a proto-R2-sentant. Evolve via native primitives; do not reinvent a bespoke PTY daemon
(that path was tried and failed). Keep launch/handoff prompts compact; `RESUME.md` is the human-readable
floor until a richer provenance graph exists.
