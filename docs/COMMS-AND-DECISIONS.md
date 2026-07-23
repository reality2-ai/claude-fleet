# Inter-agent communication & decisions

How fleet members consult each other without hijacking live threads, how
decisions that need a human become durable records, and how shared project
context reaches every member. Command summaries are in the
[README](../README.md).

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

**What it sounds like.** Members follow a comms doctrine (`skill/COMMS.md`):
shortest message that preserves the evidence and required action, ~600 chars
routine target, no greetings or restatement — evidence cited exactly (shas,
paths, error strings never shortened). An optional dense form prefixes each
line: `!` finding, `@` evidence, `=` required action, `?` open question, `#`
status, `~` non-binding info. A real exchange from our own fleet (a firmware
worker reporting a root cause to the supervisor, lightly redacted):

```
[fleet msg from core]
! v6 boot-hang ROOT-CAUSED = first-tick checkpoint flash-write in boot window,
  NOT hardware, NOT transient.
@ coarse_checkpoint_tick() (main.rs:1107) writes flash @0x1D000 on FIRST call —
  high-water mark starts 0, coarse_time_now() is absolute ~1.78e9 s, so the
  "now-hwm>=225" throttle is instantly true; sector erase+write suspends the
  flash cache ~1s after "BLE controller init OK" while radio init runs from
  flash (XIP) = deadlock, every boot. Survives power-cycle exactly as observed.
@ e6ff5198 (previous build) has no loop flash op; delta is v6-only.
= FIX 6eec53d5: seed high-water mark at boot -> first checkpoint defers 225s
  into proven-safe steady state. Type-checks 0 err x3 recipes.
= NEXT: hive rebuild 4 artifacts @6eec53d5; I attest + score.
# v7-ready
```

One claim per line, the falsifier and the exact evidence intact, and the
supervisor can rule on it without a follow-up question. Compare the ~2,000-char
prose version an agent writes by default — same facts, three round-trips of
clarification.

## Decision ledger — decisions waiting on you

Gates the fleet raises for you otherwise live only in the supervisor's scrollback
and get lost on scroll/compaction/reboot. The **decision ledger** is a durable,
queryable, answerable home for them, and the first concrete slice of the fleet's
knowledge layer — every decision is a provenance-bearing record.

```sh
fleet decision add "Ship simple USB pairing now, or wait for key rotation?" \
      --for specs --options "ship|wait"      # → prints an id, e.g. d001
fleet decisions                              # open decisions, oldest-first
fleet decide d001 "ship it"                  # ratify + route it back to 'specs'
fleet decisions --current --for specs        # bounded authoritative state
fleet decision challenge d001 "rotation test regressed" --evidence bench-17
# latch still says ship; reversal must be explicit:
fleet decision revoke d001 "bench-17 falsified the assumption"
# or: fleet decision add "Replacement" --supersedes d001; fleet decide d002 "..."
```

- **Storage** is durable under `<workspace>/.fleet/decisions/`: one
  `<id>.json` per decision plus an append-only `log.jsonl` recording every state
  change. Ids are short and sortable (`d001`, `d002`, …).
- **`fleet decision add`** creates an open `hold` gate. `--for <agent>` is who's
  blocked; `--scope`, `--authority`, `--evidence`, `--falsifier`, and
  `--supersedes` make applicability and provenance explicit. Prints the id.
- **`fleet decisions`** lists OPEN decisions, oldest-first, one per line
  (`#<id> · <age> · [waiting: <agent>] · <question>  (<options>)`). Add `--all`
  for history, `--current` for active ratified latches plus open gates, `--for`
  to scope the generated view, `--max` to bound it, `--json` for machine output,
  and `--watch` for a self-refreshing pane. No tmux is needed.
- **`fleet decide`** ratifies once and routes the answer. Repeating the identical
  answer is idempotent; a different answer is refused rather than overwriting history.
- **`fleet decision challenge`** appends evidence and changes only epistemic state
  to `wounded`; operational `hold|go|done` remains latched.
- **`fleet decision revoke`** is restricted to the record's named authority.
  Replacement can instead use a new immutable ID with `--supersedes`; the old
  latch is retired only when its successor is ratified. Actor identity here is
  local provenance and policy enforcement, not cryptographic authentication.

Workers must not set or claim another actor identity to defeat the authority check,
and must not mint a successor merely to escape a decision. A concrete falsifier is
recorded as a challenge and escalated to the authority. Explicit newer human
instruction and independent safety gates still apply. Decision action `done` means
"the chosen action is done"; it is not evidence that implementation, tests, review,
commit, or push have completed.

**Optional `decisions` tmux window.** Current decisions are already included in
`fleet brief` and every worker primer, so no redundant pane runs by default. Set
`FLEET_DECISIONS_WINDOW=on` to add a persistent window running
`fleet decisions --current --watch`. It is strictly non-fatal.
`FLEET_DECISIONS_WATCH_SECS` sets the refresh interval; `FLEET_DECISIONS_WINDOW_ALL=on`
makes the pane show history too.

## Shared context — `primer.md`

The tool itself is domain-agnostic. To give every member the same map of your
project — architecture, who-owns-what, conventions, collaboration rules — put it
in an optional `<workspace>/.fleet/primer.md`. If present, its contents are
appended verbatim to every member's launch primer. (Re-`up`/re-dispatch members
after editing it; the primer is applied at launch.)
