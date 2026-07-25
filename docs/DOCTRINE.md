# Operating doctrine

`fleet` carries a working *doctrine*, not just mechanics. Two short, generic,
project-agnostic docs hold it (project-specific context lives in a private
`primer.md`, never here):

- **[`FLEET-WORKING-PRINCIPLES.md`](FLEET-WORKING-PRINCIPLES.md)** —
  spec-first; secure-over-calm; **GitHub as the failsafe** (checkpoint to git so
  risky changes are *recoverable* rather than *blocked* — small named commits,
  never `git add -A`, a pre-push secret-scan, commit + push each verified unit);
  the permission / auto-approve + firmware-gate model; public-code /
  private-context; and roles (a coordinating **supervisor** that monitors but
  writes only its own infra repos; per-component **experts** do the hands-on work).
- **[`THURISAZ-WORKING-MODE.md`](THURISAZ-WORKING-MODE.md)** — the
  self-improving loop: honest conjecture → **cross-agent refutation (ideally by a
  different model)** → reputation → memory → reproducible re-audit. A non-trivial
  design isn't "fit" until a *peer* has tried to kill it; the human steers
  *direction*, the refutation loop runs itself within the failsafe.

Two principles worth stating outright:

- **Verify-then-record.** Confidence is what *survives* a genuine attempt to break
  it, not what looks right. Label work honestly; absence of counter-evidence is not
  evidence. The Codex tools and cross-agent refutation are how it's enforced.
- **Improve the tools alongside the work.** The fleet is the apparatus that builds
  the product, so a better apparatus compounds — `fleet` is meant to be sharpened
  *while* it runs, held to the same bar (refutation, a different-model perspective,
  annealing convergence, verify-then-record). The firmware-gate and the Codex tools
  are themselves examples.

> **Editing a *running* fleet is hot-wiring a live circuit** — the supervisor runs
> *on* the thing it's editing, so a bad change to the message bus / registry /
> hooks can take down the supervisor and every worker at once. The rule: prefer
> **additive** changes (new files/tools/toggles nothing depends on) over altering
> the live critical path; **test offline** on a stub workspace first; keep every
> change **one toggle from off** (hooks are read per-invocation, so a bad one is
> instantly disable-able); do invasive surgery (bus changes) only in a **calm,
> paused** window, never mid-flight.

## Codex as an adversarial helper

Beyond running members, the fleet can launch a read-only **opposite-provider**
reviewer with `fleet refute <target> [claim]`. This is the operational form of
cross-model adversarial work: a Claude-backed target gets a Codex reviewer by
default; a Codex-backed target gets a Claude reviewer by default. The reviewer is
seeded with the target's current task, claimed files, git context, and transcript
excerpt, then told to refute from live ground truth.

The fleet also ships two standalone tools that use **Codex as an independent,
_different-model_ adversary** — read-only, so it critiques but never edits,
flashes, or commits. The premise (from
[`THURISAZ-WORKING-MODE.md`](THURISAZ-WORKING-MODE.md), §TH-DISCOURSE):
a significant design or fix isn't trustworthy until a *different* mind has
genuinely tried to break it — and a different model/architecture catches what
same-model self-review structurally can't.

- **`bin/codex-review`** — point Codex at a finding, a design, or a git diff and
  have it try to refute it:
  ```sh
  codex-review notes.md            # review a finding/design in a file
  codex-review --diff HEAD~1       # adversarially review a diff
  echo "<claim>" | codex-review -  # review piped text
  ```
- **`bin/codex-scan`** — a full-pass audit of a repo by Codex across
  `security | usability | sovereignty | both`, supplied your project's **mission +
  values** so it audits *against what you're building for*, not generic
  best-practice:
  ```sh
  codex-scan ./core both
  ```

Run them **selectively** — Codex is quota-limited, so reserve them for high-stakes
checks. Recurring scans are an **annealing** process: scan → harden → re-scan
*converges* (each pass is also a closure-check on the last — did the fixes hold?),
and the point of a *different* adversary is to shake the system out of a
comfortable "all-green" local minimum that same-model verification settled into.
`codex-scan` can be pointed at **claude-fleet itself** — the tool gets the same
treatment as the code it builds.

## The working process, as reusable prompts

The adversarial/annealing discipline above is one piece of a larger working
process: conjecture/refutation, verify-then-record, the confirmation-bias and
anti-sycophancy guards, edge-first testing, and the git habits that make results
durable and auditable.
[`REFUTATION-WORKING-PROCESS.md`](REFUTATION-WORKING-PROCESS.md) distills
the whole thing into copy-pasteable prompts — **Layer 1** standing mindset ·
**Layer 2** the adversary · **Layer 3** the orchestrator's process loops ·
**Layer 4** git — that drop into any project's agents. It's project-agnostic, the
prompt-text companion to
[`FLEET-WORKING-PRINCIPLES.md`](FLEET-WORKING-PRINCIPLES.md).

## What it does NOT do (by design)

- **Conflict prevention is detection-only.** It warns when two live sessions claim
  the same file; it does not block edits.
- **Reboot recovery resumes conversations, not in-flight tool runs.** A build
  interrupted by a crash is not auto-resumed — the member returns to where its
  transcript ended.
- **Messages become a turn in the peer's session.** `ask`/`send` deliver into the
  peer's live thread; hybrid delivery holds mail until the peer is at its prompt, so
  it won't corrupt a mid-task turn — but it does add a turn the peer must handle. That's
  by design (it's visible to you); just know inter-agent chatter consumes peer turns.

## Direction (roadmap, not shipped)

Honest about where this is heading, not what's done:

- **Self-regulation.** The fleet should sense its own **health and load** and
  degrade *gracefully*. Today the message bus can degrade *silently*, and
  concurrent members can collectively hit provider **rate limits**. The direction
  is a fleet that detects both — backs off / re-routes / surfaces rather than
  failing quietly — and **never goes silently blind** (the supervisor's view should
  derive from ground truth — tmux, transcripts, git — that can't silently empty
  out). Spreading load across providers (Claude *and* Codex) is part of this.
- **Off the hand-rolled bus.** The tmux + file-mailbox + watchdog transport is
  pragmatic but fragile; the longer arc moves delivery + liveness onto native
  primitives (background sessions / agent-teams / a managed-agents API) behind the
  same `fleet` surface — a seam-swap, not a rewrite.

## Method earned in the field (2026-07-26, the join-relay arc)

Five rules, each from a specific incident rather than from theory. Kept here and not in
protocol canon: canon says what implementations must do, never how we should argue — mixing
them is how a spec stops being checkable.

### 1. The capability test — ask what a party CANNOT do before arguing what it SHOULD

Three separate rulings in one day were decided by the same move, and each time it beat the
argument it replaced:

- **A relay cannot AUTHORISE a join** — the frame carries its own signing key, so anyone can
  mint one, and the sender is by definition not yet a member. This decided the gate.
- **Forwarding cannot COMPLETE the exchange** — a reply needs a target and a retrace plan,
  and an origin-less join has neither. This decided the mechanism.
- **An originator cannot ENFORCE a hop limit** — and a sender-asserted hop claim would be
  attacker-chosen anyway. This decided where enforcement lives.

It outperformed the proximity and metering arguments because it depends only on **what
information a party structurally holds** — not on threat model, intent, or deployment. Reach
for it first; a genuine impossibility ends a debate that a consequence argument only weighs.

### 2. A lane that stops and asks is reporting a defect, not requesting permission

Three lanes each declined to act on something under-specified rather than guessing — one on
an enumeration, one on a security-critical boundary, one on a key it had been told not to
infer. **All three refusals surfaced a real gap.** It works because an implementer hitting
under-specification is standing exactly where the spec stopped being decidable. **Treat the
stop as the finding.** Reward it; never treat it as slowness.

### 3. Publishing ahead of an open ruling: INVARIANCE is the criterion, not mildness

When a hazard is known but the decision that governs it is still open, the question is
whether saying anything prejudges the ruling. The checkable test: **is the content invariant
across every outcome the decision could have?** If no possible ruling changes it, publishing
does not prejudge — and the form must be a *warning*, never a MUST, because an ordering rule
arriving ahead of its ruling reads as settled.

Mildness would not justify publishing; invariance does. And verify the form **mechanically** —
grep the note for MUST / SHALL / REQUIRED — rather than trusting that you wrote a warning.

### 4. Match the search to the ENCODING, not the topic

A ruling created a second valid frame shape; a constraint elsewhere still pinned the old one
as a **hex constant**. The post-ruling sweep searched *origin language* and structurally could
not see it. A lane hardening on that constant would have looked responsible and silently
broken provisioning.

**If a ruling creates a new shape, state or value, re-read every place the old one is written
as a LITERAL.** A property expressed as a constant, ordinal or bitmask needs a search over
constants — a grep of its name returns clean and means nothing.

The failure here was not the blind spot. It was **using the known-blind method to check for
the thing it is blind to** — the blind spot had been recorded that same morning.

### 5. A search returning nothing is evidence only if it COULD have returned something

Run a positive control against something you *know* is present before reporting a clean
sweep. Two failures in one day, both mine: a matcher that saw only table rows reported that
three gates "had never been written" when they were in the prose above it; and a terminal
snapshot of a mutable file was read as proof a value "never occurs, ever" when the file is
rewritten on every retry.

Corollaries: **a state check is not a history check** — freezing mutable state preserves one
instant, not a history. And **a verified fact does not license an unverified inference**: "only
this platform's source contains the instrument" was true; "so the other artifacts come from a
different platform" was never checked, and was wrong.
