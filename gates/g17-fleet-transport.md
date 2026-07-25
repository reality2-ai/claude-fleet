# Gate 17 — may I patch the fleet's live message transport?

**Status:** 🟠 OPEN — a real defect, deliberately left unpatched while you were away
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g17 and lib/comms.sh"*

## The defect

`fleet_input_busy()` in `lib/comms.sh` matches a **fixed string** for one provider's prompt
glyph. A pane using the other glyph never matches. That single miss causes three separate
failures, and I verified each in the code:

1. **Acknowledgement never registers.** The submit path takes its "never landed" branch and
   **requeues a message that actually went through**, five times, then dead-letters it. This
   is the source of the duplicate advisories that have been arriving all campaign — the
   transport retrying, not a lane repeating itself.
2. **State and metrics are overloaded.** A dead-lettered message is written as
   `delivered=true` *and* `dead=true`. So dead-letter reads as receipt. Meanwhile the failure
   counter accumulates **attempts, not messages**, and the health report presents that
   accumulator as a message-failure count.
3. **The anti-garble guard is disabled.** The same function is the defer gate, whose stated
   job is refusing to paste onto an input box that already holds real content — a human
   mid-typing, or a previous message still unsubmitted. On a non-matching glyph it reports
   "not busy", so **it never defers** and a paste can land on top of existing input.

## What is and is not established

**Measured:** content arrives. Every message reached the lane. The failure is
acknowledgement, state and head-of-line delay — **not** non-delivery. Whoever fixes this
must not spend the effort chasing delivery.

**Not established:** delivery *integrity*. Because the anti-garble guard has been off,
content may have arrived concatenated or corrupted, and nothing has tested that. A lane's
reply proves something was seen — not its path, completeness, ordering, or timeliness.

## The decision

The fix itself is small and well understood: make the prompt matching provider-aware, and
separate the four states. I have **not** made it, and that was deliberate.

**Why I stopped:** this is the live transport for every lane. A bad edit costs the ability
to talk to *any* lane — including to tell you I had broken it — with you off-bench and
nobody to recover. Waiting costs duplicate messages. A bad patch costs fleet comms entirely.
The asymmetry pointed at waiting.

- **Authorise me to patch it** — with the controls below proven before it is considered done.
- **You patch it** — it is your repo and your call.
- **Defer** — it is annoying, not blocking; everything still arrives.

## Acceptance controls, whoever does it

Prove for **both** glyphs: busy-detect fires; a successful submit is acknowledged; **no
duplicate** is produced; and a following message flows behind it. Plus: one message retried
N times must report **messages = 1, attempts = N**; dead-letter must **not** mean receipt;
and dead, attempted, submitted and acknowledged modelled as **separate** states.

## Supervisor lean

**Authorise me, now that you are back.** The reason I held off was that you were away; that
reason has expired. It is a contained change to one function plus the state writes, and the
controls above are concrete enough to prove it rather than hope.

## Ruling syntax

"gate 17: you patch it" / "gate 17: I'll patch it" / "gate 17: defer"
