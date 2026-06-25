# ADR-001 — Toward an R2-native fleet (`r2-fleet` as a full-stack Reality2 tool)

**Status:** Explored direction / north star (Roy, 2026-06-25) — **not a commitment to build, and
deliberately not one.** `claude-fleet` (bash/tmux) remains the working tool. The *one* concrete
near-term action this endorses is the **substrate move** (below); the full R2-native self-hosting
is an aspiration to approach only as R2 earns it, per-component, possibly never in full. This
records the reasoning so the choice stays deliberate rather than romantic.

## Context

`claude-fleet` is a bash + tmux command-line tool: `bin/fleet`, `lib/*.sh`, per-invocation
hooks, tmux panes per agent, JSONL mailboxes, a hand-rolled supervisor with restart-intensity
breakers. It **works** — it has driven real multi-repo R2 development (the security-hardening
wave, the #20 keystore build) day in, day out.

But its recurring pain points share a root. The messaging-robustness bug (a message lands in an
agent's input box but doesn't submit), the idle-detection guessing, the watchdog that has to
babysit liveness, the permission-gate false-positives — these are not random. Two patterns:

1. **We are hand-rolling Erlang/OTP in bash.** Supervision trees, restart intensity, "let it
   crash," mailboxes with at-least-once delivery — `fleet_reconcile`, the restart breaker, the
   inbox `.jsonl` files, the unstick sweep. We have reimplemented a *worse* version of what BEAM
   gives correctly and for free.
2. **The brittleness is in the substrate, not the language.** We drive agents by *injecting
   keystrokes into their TUIs over tmux*. A stuck message is a keystroke that didn't submit. No
   rewrite in any language fixes that **if it keeps injecting keystrokes.**

## What this commits to — and what it doesn't

Two ideas got bundled together when this came up; they carry very different risk, and the honest
read is that **the part that fixes our problems is not the romantic part.**

- **The near-term win — commit to this: the substrate move.** Move agent I/O off tmux
  keystroke-injection onto *programmatic agent control*. It kills the stuck-message / idle-guess /
  watchdog-babysit bug class outright, and it is **language- and R2-agnostic** — it owes nothing
  to self-hosting. This is the one concrete thing this document endorses *doing*.
- **The north star — approach, don't commit: an R2-native fleet.** Elegant and coherent, but it
  carries a bootstrapping deadlock and depends on R2 being mature, which it is not yet. An
  end-state to *earn* per-component, possibly never in full — not a plan, and explicitly not a
  near-term dependency.

The trap is letting the elegant story (self-hosting) pull us into a rewrite the boring story (the
substrate move) already solves. If we ever do the R2-native part, the substrate move leads and R2
earns each piece.

## The north star — an R2-native fleet (aspiration, risk-gated)

*If* and *as* R2 earns it, the end-state is **`r2-fleet` — a full-stack, Reality2-native fleet**,
in which the orchestration scaffolding is itself built **on R2**: the fleet that builds Reality2
becomes a Reality2 ensemble, the scaffolding folding into the thing it builds.

The mapping is direct — every hand-rolled fleet concept has a first-class R2 primitive:

| `claude-fleet` (bash) hand-rolls… | …which R2 already is |
|---|---|
| agents / workers in tmux panes | **R2 sentants** (AI-empowered) |
| inbox `.jsonl` + tmux send-keys delivery | **R2 transient networking** (events between hives — reliable delivery, the mailbox solved) |
| the supervisor + restart breaker + reconcile | **ensembles + the hive supervision model** (+ Elixir/OTP under BOS) |
| the A9 permission/firmware gate (bash string-match) | **R2 trust groups + the gate-core** (the very security model we've been hardening) |
| state docs + `fleet doctor` + the dashboard | **R2 hives + the proof-surface UX** |
| `composer` (today: dev orchestration tool) | **the user-facing kaitiaki app** (its stated trajectory) |

Language follows from the mapping, not the other way round:
- **Elixir/OTP** for orchestration, lifecycle, message-passing — because that is *exactly* what
  we are hand-rolling, and it is what **BOS (R2's backend) already is**.
- **Rust** for the typed, must-be-correct core — the permission gate, the wire/state model —
  because it is what **the hive/core already is**, and because the gate's bash false-positives
  (fixed twice in one day) are a textbook case for "make the bad state unrepresentable."

## Why this is the right direction

- **Substrate-first kills a whole bug class.** Moving from keystroke-injection to *programmatic
  agent control* (the headless SDK / Managed Agents API — already the target of our
  orchestration-migration plan) makes stuck messages, idle-guessing, and watchdog-babysitting
  simply not exist. This is the highest-leverage move and it is **language-agnostic** — it is
  worth doing first, regardless of the rewrite.
- **It is self-hosting, which is the stated vision.** `claude-fleet` is "convenience scaffolding
  toward AI-empowered R2 sentants." An R2-native fleet is not a detour off that path — it *is*
  that path: R2 orchestrating R2, the tool eating its own dog food, every fleet improvement
  becoming an R2 improvement and vice-versa.
- **It compounds with the product.** A better apparatus builds R2 better; building the apparatus
  *on* R2 means the two co-evolve on one codebase instead of two.

## The trap to avoid

**Rewriting the language without moving the substrate.** An Elixir+Rust fleet that still injects
keystrokes over tmux buys OTP supervision and keeps every injection bug — the expensive way to
preserve your current problems. If we do this, the substrate move (API-driven agents) and the
rewrite go **together**, and the substrate move leads.

## Risks / when this would be wrong / open questions

- **Bootstrapping (the chicken-and-egg).** The fleet *builds* R2. If `r2-fleet` depends on R2 to
  run, a broken R2 can't be fixed by a fleet that needs working R2. **Mitigation:** the fleet may
  depend only on a **stable, released R2 floor** — never the bleeding edge it is actively
  developing — and must keep a **non-R2 fallback** path to operate (and to recover R2) when R2
  itself is down. Self-hosting is an end-state to *earn*, not a day-one dependency.
- **Maturity gap — and it is now.** R2's transient networking, trust, and OTA are still being
  hardened (we are mid-#20). The fleet cannot depend on them until they are genuinely solid.
  Premature self-hosting couples the tool's reliability to the product's unfinished edges.
- **Loss of iteration speed.** Bash hot-fixes ship in minutes (the gate was fixed twice today
  without a build). A compiled, R2-native fleet must preserve that prototype velocity or it loses
  the very property that makes the current tool useful.
- **Loss of operational simplicity.** `bash + tmux` is trivial to operate, inspect, and recover
  by hand. An R2-native fleet adds real operational surface; that cost is only worth paying once
  the reliability gains are concrete.
- **Rewrite-for-its-own-sake.** Do not port like-for-like. Migrate a component only when its bash
  brittleness costs more than its replacement, or when self-hosting that piece is genuinely ready.

## How we get there (staged, no big-bang)

1. **Now:** keep `claude-fleet` (bash). Harden it incrementally (e.g. the scheduled
   messaging-robustness fix), and **treat every pain point as a discovered requirement** for the
   successor — the bugs are specs.
2. **First real step (language-agnostic):** move agent I/O from tmux keystroke-injection to
   **programmatic agent control**. Highest leverage, lowest coupling, validates the substrate.
3. **Incrementally R2-native:** replace hand-rolled pieces with R2 primitives where R2 is already
   solid — messaging → transient networking, supervisor/lifecycle → ensembles, the gate → trust
   groups — each behind a fallback, each earning its place.
4. **End-state:** `r2-fleet` runs as an R2 ensemble on BOS (Elixir) + the Rust core, with
   `composer` as the kaitiaki-facing surface. The scaffolding has become a sentant.

**Decision trigger:** begin stage 2 when there is a calm window; begin stage 3 per-component as
each underlying R2 subsystem reaches a stable, released floor — not before.
