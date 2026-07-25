# Gate 20 — open a new flash grant for the origin hunt?

**Status:** 🟢 OPEN — the next real step on D5; nothing authorised until you rule
**Interrogate:** `cd ~/Development/R2/claude-fleet && claude` → *"read gates/g20 and r2-core/DECISIONS.md D-20260726-01"*

## Where the D5 work stands

The fault-capture campaign closed. What it bought:

- **The fix works, at scale.** 240+ faults after the baseline, **every one** a clean
  self-recovery. Zero anomalous resets in 150,000 log lines. The silent-wedge failure that
  started this is gone, demonstrated rather than argued.
- **The family is ruled and ratified.** Primary faults, established through the image's own
  section layout with no remaining assumptions, landing in the vendored radio and
  coexistence stack. 74 distinct crash sites, none in the RAM exception region.
- **Three mechanisms, not one** (re-ruled this morning at scale): the main class, a
  null-dereference class, and a **wild-jump class** — one fault type mapping *exactly* onto a
  garbage address, 18 for 18.
- **Origin is open, with a lever.** 13 of the 18 wild jumps originate in a **timer-arm call
  site**. Two originate in **our own SPI/LoRa driver** — outside the vendored stack — from
  two different points inside one routine.

## The decision

The origin question — *what corrupts the control flow* — needs either a capture taken before
the fault lands, or a debugger attached live on a first fault. **Both are device operations
and need a grant.** The grant is retired; nothing is authorised.

- **Open the grant** — the hunt starts from a class with 18 scorable instances and a named
  dominant context, rather than the single parked datum it would have started from last
  night. Every extra hour of faulting adds evidence at ~3.5 minute intervals.
- **Hold** — the board keeps running and keeps accumulating. Nothing degrades. The corpus
  only gets better.

## What runs first, and it needs no device at all

One falsifier is owed and is pure source work: whether the faulting functions are reachable
inside a cache-suspend window. That would move the leading mechanism from *leading* to
*established* **before** any hardware is touched. **I would run that first regardless of how
you rule here** — it may sharpen what the grant should even ask for.

## Two rules carried into any hunt, learned the hard way

- **Resolve every symbol from the image matching the flashed build.** An address is
  per-artifact; the property is not. One symbol moved between builds and then held steady,
  which is the pattern that trains you to trust it.
- **The lock symbol is a pointer, not the object.** Read the pointer, then dereference. A
  previous reading that ignored this produced a conclusion we later had to retract.

## Supervisor lean

**Run the source falsifier first; open the grant after it reports.** Not caution for its own
sake — it costs nothing, needs no hardware, and may change what the hunt should look at. If
it confirms, the grant gets written against a much sharper question.

## Ruling syntax

"gate 20: open the grant" / "gate 20: falsifier first" / "gate 20: hold"

---

## RULING (Roy, 2026-07-26): *"yes, open the new flash grant"*

## FALSIFIER RESULT — CLEAN NEGATIVE. The leading hypothesis is OUT.

I said the source falsifier should run first because it might change what the hunt asks
for. **It did, and it eliminated my own conjecture.**

Core ran it at the binary level on the sha-verified deployed image. Three legs:

1. **`Cache_Suspend_ICache`, `Cache_Freeze` and the disable-cache symbols are ABSENT from
   the image.** The only cache symbols present are `Cache_Suspend/Resume_DCache` — **data**
   cache. The instruction cache is never suspended, so a cache-off instruction fetch
   **cannot occur**.
2. `Cache_Suspend_DCache` has exactly **one** caller: boot-time cache-mode configuration.
   One-time, DCache-only, cannot cause an instruction-fetch fault.
3. **`phy_enter_critical` contains no cache operation at all** — it disassembles to an
   interrupt-level raise, a spinlock and a memory barrier. The cache stays **on**, so even a
   function faulting inside a phy critical window fetches normally.

**Cache-suspend does not go from leading to established. It is eliminated.** It was *my*
conjecture, I argued it was stronger than the alternative, and core weighted it leading on
my framing. The binary says no.

**Residual, stated honestly by core:** opaque blobs performing direct cache-register writes
with no linked symbol cannot be excluded by symbols alone. Unsupported, and phy is
demonstrably cache-on — but not zero.

## What the grant must now ask

The hunt re-points to **data/pointer corruption** — of the coex `osi_funcs` and timer
callback pointers, or of return/call targets. That is **the a0-versus-static-target seam**:
the saved caller says the faulting function was entered from a direct call whose target is
statically fixed, yet the fault landed elsewhere.

**Not a fetch failure. A wrong-target-execution question.** The grant asks about pointer
and target integrity, not cache windows — which is a different instrument and a different
capture.

## Standing rules carried into the hunt

- Resolve every symbol from the image matching the flashed build; an address is
  per-artifact, the property is not.
- The lock symbol is a pointer, not the object — read the pointer, then dereference.
- Two-leg grant eligibility: capture instrument present, then handler call-free within its
  true extent.
