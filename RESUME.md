# RESUME — claude-fleet (supervisor)

**Updated 2026-07-27, ~02:00.** Takeover snapshot. Rewritten whole earlier tonight, then
**updated in place after the metal result** — and re-read end to end afterwards specifically
hunting paragraphs the update had left stale. That sweep found one and it is fixed: this file
said *"waiting on a rebuild"* after the rebuild had happened and been confirmed on metal.
**Same file is not same sweep** — the rule that cost me a grant-file record tonight, applied
here on purpose.

## Where the OTA work actually stands

**The round-trip is NOT done — and the blocker has MOVED.** The stale-header-version block is
**fixed, rebuilt, and confirmed behaviourally on metal.** What remains is the **identity
write**, which is Roy-gated on two questions. So the night ended one gate further forward than
it started, with the failure now at the signer gate rather than the version gate.

**Proven on metal tonight**, each independently:

- **Button-free download-mode entry AND exit** on X1 — the BOOT/RESET buttons are buried under
  the LoRa piggyback, so this was the load-bearing unknown. Exit was proven by an *inverted*
  test: a no-reset connect **failed** on app console data, and a board stuck in download mode
  **would have connected**.
- **Image A written app-only** — no erase, table explicit, NVS at 0x9000 preserved, running
  from `ota_0`.
- **The persona state read cleanly** through a PTY monitor (a plain `cat` open silences this
  chip). Result: an **affirmative absent** — unprovisioned, no NVS persona.
- **BLE channel connect, L2CAP accept, and a signed header framed and answered.** First time
  on this hardware.
- **Fail-closed rejection, twice** — once malformed, once **well-formed but unauthorised**. Both
  times the board refused, wrote nothing, sent zero image chunks, **and did not reboot at all**.
- **The re-vendor confirmed behaviourally on metal:** the refusal moved from the **version** gate
  (`reason=1`) to the **signer** gate (`reason=4`). The v3 header parses. And composer's
  source-level refutation of my *transport-needs-no-persona* claim became an **observation**.

**Still untested:** the image-chunk stream. Every historical failure on this hardware was a
chunk-1/2 stall, and **that code was never reached tonight.** Connect and header delivery are
proven; the chunk stream is not.

## What blocked it last night — now FIXED and confirmed, kept for the sequence

The reject was **not** the signer gate and **not** a stall. It was **`BadHeader`**: the two
vendored copies of the update crate disagreed on the package version — pusher v3/137, firmware
v2/123. **So no OTA this firmware accepts could be pushed at all**, regardless of signing or
provisioning.

**Canon settled it and the board was right.** v3/137 is canonical; the firmware copy was
**seventeen spec revisions stale**; and strict single-version cutover specifies that a receiver
accepts *only* the current version, **checked before the signature** — so the rejection order
was exactly as written. **This is g22 landing on metal**: not interop lag from a deliberate
pin, a **hard functional block**.

**Fixed:** core replaced the stale copy wholesale with the canonical one (byte-identical,
after proving it a clean stale ancestor rather than a fork), on its branch. Signed-byte
coverage is **parametric over the header length**, so the new fields are covered **by
construction**.

## Immediate next action — and it is Roy's, not a lane's

**Everything a lane can do without a provisioned board is done.** The single thing standing
between here and a round-trip is **the identity write**, and it is gated on two questions that
must be answered from code and from the device:

1. **Which path does this build actually read the persona from** — NVS, or the raw offset the
   board's console names?
2. **Is that offset inside a region no partition claims?**

**They are gated because the board's own console recommends the operation that BRICKED D4** —
fourth resurfacing of that hazard, and the first time the *artifact itself* is the source. A
minted dev-TG persona is ready and unused; the mint touched no board.

**Once provisioned:** push B and the chunk stream finally gets exercised — that is where the
historical chunk-1/2 stall lives, and it has never been reached on this board. The
LoRa-on-core1 pair is pre-built for that branch, and a pass on it is **"core-0 load relief as a
class", not coex-relief.**

Read any result against **four** outcomes: B running · software-reset fault (recovers) ·
watchdog stall (**empty capture is a fault the instrument cannot record**) · **clean protocol
reject with no reset.** That fourth leg was missing from my tree until hive caught it.

**If anything panics on the board as it stands, decode the location against the running build,
not the branch tip** — comment line-shifts moved the panic-location bytes.

## Standing bars

- **No identity write until two questions are answered** from code and from the device: which
  path this build reads the persona from, and whether the offset the board *suggests* lies in
  a region no partition claims. **The board's own console recommends the operation that
  bricked D4** — fourth resurfacing of that hazard, first time the artifact itself is the
  source.
- **Provision only on an affirmative absent, or affirmative invalid with no valid identity.**
  Silence means STOP (the check fails closed *silently*). A valid persona in a different trust
  group means **stop and escalate** — never overwrite.
- **Image B is air-delivered only.** No tool writes it to any partition; A stays as the only
  known-good image.
- **No NVS dump** — secret key material must not leave the protected boundary in plaintext.
- **Any WiFi OTA must use the authenticated path.** The default wire is un-authenticated and
  #d003 names WiFi as *the* ESP32-S3 OTA path, so it would have shipped.
- The WiFi connect fix is **possible, not proven** — no station has associated on metal.

## Open Roy gates

**g25** (does the pre-release premise still hold, now that two divergent copies exist on real
hardware — a deployment judgement, not a canon read) · **g23** · **g24 ruled by me pending
review** · **g21** · **g8**. Plus: the **LED visibility check** under the piggyback (if hidden,
a discrete LED stops being optional), the **two MAX485 hardware-history facts**, and whether
to spend a build cycle on **attribution** rather than capability.

## Method earned tonight — each paid for

1. **A complete pre-registration has four parts**: the prediction, what each outcome means,
   **the instrument that will read it**, and **that instrument's blind classes.** You can
   predict correctly and still misread the result, and nobody notices because the prediction
   "held."
2. **A pre-committed decision tree needs a leg for "rejected outside the hypothesis space"**,
   or it converts a novel outcome into a familiar one — worse than no tree, because the tree
   lends it authority.
3. **Assert the rejection REASON, never merely the rejection.** We believed we were testing a
   signer gate and were hitting a version check that fires first.
4. **A permissive default is safe when DECLARED, never when INFERRED from absent data** — and
   **canon permitting a value is not canon endorsing it for your artifact**; you need the
   artifact-side fact too.
5. **Presence AND absence at symbol level** for any placement or gating claim — show the
   symbol that must be **gone**, not just the one that must be there.
6. **Subtractive isolation without a forward control** finds a *sufficient* change, not the
   cause. And **a proposed fix must be tested against the guard's purpose, not the symptom**:
   I nearly deleted a security-gate guard on an untested diagnosis.
7. **Same file is not same sweep.** Flipping a grant field silently removed the only record of
   what the prior stage wrote.
