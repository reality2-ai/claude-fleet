# Gate 19 — may I patch the flash-authorisation gate?

**Status:** 🔴 OPEN — a bypass that has already fired, with no detector behind it
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g19 and hooks/auto-approve.sh"*

## The defect

The authorisation hook decides whether a command touches hardware by inspecting the command
text. It looks through a known list of wrappers (`env`, `sudo`, `timeout`, shells, and so
on) to find the real program. **A bare `VAR=value` prefix is not in that list**, so a command
beginning that way makes the flasher invisible to the gate: no authorisation check, and **no
entry written to the audit log.**

**This is my defect.** My own grant wording instructed lanes to use that form. Hive escalated
a missing log line, which is the only reason it was found.

## What is and is not established

**Established:** the bypass fired. One operation ran with no audit record.

**Scope, stated precisely so it is not overread:** that operation was an **offline derive** —
its target was explicitly a no-device target. **No unlogged device operation is
established.** The mechanism *could* hide a flasher; it has not been observed doing so.

**The part that should decide priority:** the only reason we know about the one instance is
that **a lane noticed an absence**. There is no mechanism that detects an unlogged operation.
So the number of bypassed operations is **unknown, not zero** — and the audit log is a record
of *gated* operations, not of *all* operations. I claimed the latter earlier; that was wrong.

## The decision

Three related fixes, of which the first is the security one:

1. **Treat a bare `VAR=value` token as a wrapper**, so the look-through reaches the real
   program. Closes the bypass.
2. **Pin a canonical audit-log location.** Currently the hook walks up from the working
   directory to the nearest `.fleet`. A second log exists; it contributes no unique records,
   so nothing has been lost — but the mechanism could split the trail later.
3. **Atomic one-shot consumption.** A grant is never consumed today: a matching command can be
   re-run until expiry. Every "one attempt only" I wrote this campaign was **honour-system
   prose the gate does not enforce**, and the lanes were not told that.

- **Authorise me** — same posture as g17: I held off because this is a security-critical path
  and you were away.
- **You do it.**
- **Defer** — with the bypass open and undetected.

## Supervisor lean

**Authorise leg 1 now, legs 2 and 3 next.** Leg 1 closes a hole that is open right now and
whose exercise count is unknown. Leg 3 matters most for honesty: I have been writing
one-attempt limits into grants as though the gate enforced them, and it never did.

## Ruling syntax

"gate 19: you patch it" / "gate 19: leg 1 only" / "gate 19: I'll do it" / "gate 19: defer"
