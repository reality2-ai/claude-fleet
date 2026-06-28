# Faculty-adapter contract — the interface a provider implements to be a brain

**Status:** Design spec (2026-06-29). The concrete, buildable core of
[ADR-002](ADR-002-multibrained-entity-fleet.md). Defines the single interface every AI provider must satisfy
to be **mountable as a brain** on an entity, so the fleet's provider differences collapse from binary
`claude|codex` branches into one contract with N implementations.

This is a **seam first, rewrite never**: the existing `lib/provider.sh` + `lib/transport.sh` are its first
implementation (provider = the CLI, transport = tmux). New implementations (Claude background sessions, Codex
durable sessions, a future provider) are added as further implementations of the *same* verbs; nothing above
the seam changes.

---

## Terms

- **Entity** — a sovereign fleet member (proto-sentant). Owns durable identity: `id`, repo ownership +
  file-claims, `RESUME.md` (durable memory), mailbox address, supervision/trust place. **Substrate-independent.**
- **Faculty / brain** — one provider's mind mounted on an entity. Disposable and swappable.
- **Leaf** — a concrete running instance of a faculty (a background session, an `exec` run, a subagent).
- **Body** — a *resident, durable, attachable* leaf. **Tool** — an *ephemeral* leaf a brain spawns for a
  bounded sub-task.
- **Adapter** — the per-provider implementation of this contract.

## Capability declaration

An adapter first declares what it can do, so the entity layer degrades gracefully instead of assuming parity:

```
faculty_capabilities() → {
  provider:            "claude" | "codex" | …
  durable_body:        bool      # can host a resident, reattachable body?
  attachable:          bool      # can a human attach to a live leaf?
  native_liveness:     bool      # reports liveness without screen-scraping?
  native_delivery:     bool      # accepts a message via API (not keystrokes)?
  worktree_isolation:  bool      # isolates each leaf's working tree?
  unattended_perms:    bool      # can run without per-tool human prompts?
  headless_answer:     bool      # supports a one-shot forked answer (for `ask`)?
  native_tui:          bool      # attach yields the provider's own formatted TUI?
  event_stream:        bool      # exposes a normalized event/transcript stream?
}
```

### Verified provider matrix (2026-06-29; treat unknowns as `false` — fail safe)

| capability | Claude CLI-in-tmux (baseline) | Claude background session | **Codex 0.142.3** (verified) |
|---|---|---|---|
| `durable_body` | t (tmux window) | t | **t** — named resumable/archivable/forkable sessions (`codex resume <uuid\|name>`, `archive`/`fork`; `--ephemeral` opts out) |
| `attachable` | t (tmux attach) | t (`claude attach`) | **t (experimental)** — `codex app-server daemon` + `remote-control start`, TUI attaches via `--remote ws://\|wss://\|unix://` (`app-server proxy`) |
| `native_liveness` | f (pane-scrape) | t | **t** — `codex exec --json` JSONL events; `remote-control --json`; versioned app-server protocol |
| `native_delivery` | f (keystrokes) | t | **t (experimental)** — app-server control socket |
| `headless_answer` | t | t | **t** — `codex exec [resume]`, `--output-last-message <file>`, `--output-schema <file>` |
| `worktree_isolation` | partial | t | **t** — `--sandbox read-only\|workspace-write`, `codex sandbox`, `--add-dir`, `--cd` |
| `unattended_perms` | t | t | **t** — `--dangerously-bypass-approvals-and-sandbox` |
| `native_tui` | t | t | **t** — full TUI; attach via `--remote` |
| `event_stream` | f | t | **t** — `--json` JSONL; typed app-server protocol (`generate-json-schema`) |

**Resolved:** the Codex brain CAN be a resident attachable **body**, not just an ephemeral tool — symmetric
(both Codex daemon + Claude bg-sessions are *experimental*). **MCP** both ways (`codex mcp` / `codex mcp-server`).
**Local/OSS brains:** `codex exec --oss --local-provider lmstudio|ollama` ⇒ a Codex-OSS adapter variant mounts
an on-grid local model as a faculty (basis for the local-model supervisor, ADR-002 §7a).

## The verbs

Every adapter implements these. Signatures are conceptual (the bash seam realizes them as functions taking an
`entity_id`); a future Elixir/R2 layer realizes the same verbs as messages.

### Lifecycle
- `mount(entity, role, opts) → leaf_ref` — start (or resume) a leaf for this entity. Must **rehydrate durable
  memory**: seed the leaf from `RESUME.md` + claims, not from any in-leaf history. `role ∈ {writer, reviewer,
  standby}`. `opts` carries cwd, permission posture, body-vs-tool.
- `resume(entity) → leaf_ref` — reattach to / re-establish this entity's existing leaf if the adapter is
  durable; else `mount` fresh.
- `unmount(entity, reason)` — stop this entity's leaf cleanly, marked intentional (distinct from a crash).
- `liveness(entity) → live | idle | busy | dead | throttled | exhausted` — **native** where the capability
  allows; only the tmux baseline falls back to pane inspection. (Maps onto today's `fleet_liveness` +
  `fleet_pane_is_*`.)

### Work
- `deliver(entity, msg)` — hand one message to the leaf. **Native delivery** (API) where available; the tmux
  baseline is `fleet_inject` with its at-least-once / verified-submit guarantees. Returns delivered/queued.
- `headless_answer(entity, question) → text` — a one-shot **forked** answer that does **not** disturb the
  entity's live body (the `fleet ask` responder). Must run **isolated** (worktree) so a fork can never write
  the entity's live checkout — this requirement is what structurally fixes
  `fleet-ask-fork-writes-live-checkout-hazard`.
- `spawn_tool(entity, task) → result` — run a bounded sub-task as an ephemeral leaf (a subagent), returning a
  result. The brain's *tools*, one level down (research / verify / refute).
- `recall(entity, query) → text` — **lazy retrieval** from shared memory: the entity-memory head, the decision
  log delta since the brain's last-seen seq, and targeted repo greps. Pull-not-push — a brain pays tokens only
  for what it retrieves (see [ENTITY-MEMORY](ENTITY-MEMORY.md), the token-efficiency core). The durable artifact
  is provider-agnostic, so every adapter implements `recall` over the *same* files — no per-provider memory.

### Oversight & observation
- `attach(entity)` — **attach-through**: give a human the leaf's *own native TUI*, where `native_tui`. This is
  how the rich, formatted CLI is preserved at **zero rebuild cost** — you reattach to the real session
  (e.g. `claude attach`), you do not re-render it. (Today: `fleet attach`.)
- `stream(entity) → events` — a **normalized** event/transcript stream (text deltas, tool calls/results,
  started/idle/terminated, throttle/exhaust) for leaves where `event_stream` but not `native_tui` (ephemeral
  tools; cloud/API leaves). The entity layer renders these as a coarse activity view — **never as a fake
  terminal**.
- `permission_posture(entity) → unattended | gated` — workers unattended, supervisor gated
  (`fleet-skip-permissions-and-oversight`).

#### Display principle (do not violate)
Rich formatting is a property of a **leaf**, obtained by **attaching**. The **entity** view is a deliberately
coarser, structured surface (status / events / results / verdicts) over `stream()` + attach-through — it does
**not** attempt to merge N provider TUIs into one terminal. Fidelity lives at the leaf; overview lives at the
entity. A beautiful unified entity view is a **`composer` / R2 proof-surface** concern (`composer-as-user-app`),
built over the same normalized `stream()`, not a CLI responsibility.

## What the entity layer keeps (NOT in any adapter)

These are irreducibly cross-tree and stay above the contract — no provider primitive offers them:

- **The entity registry:** `entity_id → { provider → leaf_ref }` + role/state per brain.
- **The cross-provider mailbox** + hop-capping (subagents only return to a parent; no peer-to-peer).
- **Ensemble policy:** writer election, failover (promote a standby), **fitness-selection** (choose a brain by
  capability/cost/quota), **quorum refutation** (fan a claim across N brains, require a majority to survive).
- **The A9 firmware/key gate** (security).
- **Durable memory contract:** the entity guarantees `RESUME.md` is current so any brain can be mounted cold.

## How the layer uses the contract (sketch)

```
# failover entity E off an exhausted brain:
cur   = registry[E].writer                       # e.g. claude
for p in fitness_order(E, exclude=cur):          # cost/quota/capability ranked
    if adapter[p].capabilities.durable_body or task_is_short:
        adapter[p].mount(E, role=writer, opts=from_resume(E))
        adapter[cur].unmount(E, "failover→%s" % p)
        registry[E].writer = p; break

# quorum refutation of a claim by entity E:
verdicts = [ adapter[p].headless_answer(E, refute_prompt(claim))
             for p in registry[E].brains ]       # N independent minds
claim.survives = majority(verdicts, "could not refute")
```

## cli-tmux adapter — under-exploited tmux features (backlog, verified tmux 3.6b)

The `cli-tmux` adapter currently scrapes pane *text* for liveness and has no event stream. tmux itself offers
more, and using it would flip cli-tmux capability flags toward TRUE **without leaving tmux** — hardening the
floor we already run on, rather than only chasing the native adapter. Ranked by value/risk:

- **`set-hook pane-died|pane-exited`** → *mechanical floor:* event-driven crash detection/reap (instant), vs
  today's polling. Strengthens `cmd_reap` + actor-of-last-resort (ADR-002 §7c).
- **`display-message -p` formats** → `native_liveness`↑: `#{pane_dead}`/`#{pane_pid}` (exact alive/dead),
  `#{window_activity}` (last-output epoch), `#{window_activity_flag}` (silence = idle proxy). Replaces regex
  scraping. *Limit:* `#{pane_current_command}` can't distinguish idle-vs-busy (always `claude`/`codex`).
  **LANDED (opt-in, 2026-06-29):** `fleet_tmux_pane_dead` (#{pane_dead}) is wired into `fleet_liveness` +
  `cmd_reap`; `FLEET_TMUX_REMAIN_ON_EXIT=on` keeps a crashed worker's window as a visible dead pane (instead of
  vanishing → fixes "supervisor goes blind") and flips cli-tmux `native_liveness`→true. Default OFF → live-fleet
  behaviour unchanged; native dead-read defaults on but is a no-op without remain-on-exit. Covered by
  `tests/liveness.sh` (10 refutation assertions); smoke 89/0. `fleet_tmux_window_activity` helper added but
  **not** wired into liveness — deferred pending a bench on a real idle Claude pane (TUI-repaint ambiguity).
- **`pipe-pane -o`** → `event_stream`↑ + cheaper delivery-verify: append-only pane-output file (mtime =
  liveness; the substrate for `faculty_stream` on cli-tmux).
- **Control mode (`tmux -CC`)** → the strategic one: subscribe to tmux's structured event protocol
  (`%output`/`%exit`/…) for native liveness + stream + delivery signalling, no scraping/polling — makes
  cli-tmux ~as native as `claude-bg`. Cost: a persistent control client + protocol parsing.
- Minor: **`respawn-pane`** (restart in place, preserve window identity), **`@user` options** (store
  entity id/provider/role on the window), **`wait-for`** (block-on-event vs poll), **`capture-pane -e/-S -`**.

**Boundary (what tmux CANNOT fix):** idle-vs-busy judgment (inherent to a TUI always running `claude`) and
**delivery** fragility (the unsubmitted-Enter bug is `send-keys`; even control mode confirms *output*, not
*submit*). Those need the programmatic-control substrate (`claude-bg` / Codex app-server). ⇒ Split the work:
harden liveness/stream on tmux now; reserve the new adapter for the delivery fix.

## Migration mapping (seam, not rewrite)

| Contract verb | Today's implementation (the first adapter) |
|---|---|
| `mount` / `resume` | `fleet_tmux_start_child` + `fleet_agent_build_args` |
| `unmount` | `fleet_tmux_stop_child` |
| `liveness` | `fleet_liveness` + `fleet_pane_is_{idle,throttled,provider_exhausted}` |
| `deliver` | `transport_deliver` → `fleet_drain_inbox` / `fleet_inject` |
| `headless_answer` | `fleet_agent_headless_answer` + `responder.sh` |
| `spawn_tool` | (new) — native subagents |
| `attach` | `fleet attach` (native TUI via tmux today; `claude attach` under a bg adapter) |
| `stream` | (new) — provider transcript jsonl + seam events; today only the coarse `fleet logs`/event-log |
| `recall` | (new) — read `RESUME.md`/entity-memory head + log delta + repo grep ([ENTITY-MEMORY](ENTITY-MEMORY.md)) |
| capability flags | (new) — replaces ad-hoc provider `case` branches in `provider.sh` |

The first build step (ADR-002 Stage 2) is to name these verbs in `transport.sh`/`provider.sh` and route all
call-sites through them — making the seam explicit with **zero behaviour change** — then add the
background-session adapter as the second implementation.

**STATUS — seam landed (2026-06-29):** `lib/faculty.sh` implements this contract as the first adapter
(`cli-tmux`, the default and only `FLEET_FACULTY_ADAPTER` today). Every action verb delegates verbatim to the
pre-existing function, `faculty_capability`/`faculty_capabilities` encode the verified matrix (with `claude-bg`
/ `codex-daemon` recorded as ready-to-switch data), `recall` reads the durable head, and `spawn_tool`/`stream`
fail honestly until the native adapters land. Covered by `tests/faculty.sh` (34 assertions); `tests/smoke.sh`
green (89) → zero behaviour change. **Not yet adopted at call-sites** — that is the next, separately-verifiable
step, followed by the `claude-bg` adapter.
