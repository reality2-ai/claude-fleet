# Gate 18 — D4 and X1 cannot report a fault at all

**Status:** 🟠 OPEN — decides whether the next multi-board run has any forensics
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g18 and gates/g20"*

## What was found

While verifying something unrelated, core flagged two staged artifacts as carrying an old
fault handler. Checking every staged XIAO and sensor image on the bench host: **all of them
do**, about forty artifacts. The fix that gives D5 its fault forensics exists **only in the
D5 line.**

It is worse than "an older handler". Those images have **no capture instrument at all** —
the persistent fault-capture symbol is absent from every one of them. And their handler
makes a **windowed call into flash from exception context**, which is precisely the
mechanism proven earlier this campaign to re-fault and destroy the capture.

**Combined effect: total fault blindness plus a re-fault loop, with recovery only by
watchdog.** Not a brick — the boards run fine until they fault. But if D4 or X1 faults
during a multi-board run, **we learn nothing**, and would not know a fault had happened
beyond a reboot.

## Why this is a decision and not just a task

Rebuilding is build-and-stage activity, which is gated, and it costs bench time that is
currently going into the D5 origin question. The trade is real:

- **Rebuild before the next multi-board run** — D4 and X1 gain the same fault capture and
  clean self-reset D5 has demonstrated across 240+ faults. Costs a build cycle and a flash
  grant per board.
- **Defer** — accept that only D5 can report a fault. Fine while the work is D5-only, which
  it is right now. Becomes a real cost the moment a run involves the other boards, because
  a fault there is silent and unattributable.

## Already in force regardless of your ruling

**Grant eligibility now has two legs, tested in order:** (1) the capture instrument must be
present in the artifact, then (2) the fault handler must be free of calls within its true
extent. Fail either and no flash grant is written. Every current sibling artifact fails leg
one. They are marked do-not-flash, and hive has recorded the rule so a future build order is
checked against writing rather than memory.

## Supervisor lean

**Rebuild before any run that involves D4 or X1; do not rebuild speculatively now.** The
whole point of this campaign was removing fault blindness, and shipping it on one board of
three while the other two are blind is the same half-applied shape we have been closing all
week. But there is no multi-board run scheduled, so it does not need to happen today.

## Ruling syntax

"gate 18: rebuild now" / "gate 18: rebuild before the next multi-board run" / "gate 18: defer"
