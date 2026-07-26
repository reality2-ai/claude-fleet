# RESUME — claude-fleet (supervisor)

**Updated 2026-07-26, late.** Takeover snapshot, rewritten whole. Every figure below was
re-derived from the repo and the fleet at write time — the version it replaces said
*"nothing is executing"*, named five open gates that are no longer the open set, and
described a live grant that has since been spent. A snapshot is only useful if it is
current.

## Objective right now

**Roy's overnight sequence, given before he slept, with X1 plugged into USB:**

1. **Core R2 hive with OTA** — first, everything else after.
2. Then **the memories** — one for encrypted material (ATECC608), one as the buffer for
   **sensor data before it is sent** (FRAM, so a queue with delivery semantics).
3. Then **the sensor** — read every 5–10 s on the bench, ~15 min in the field, **emulated
   while USB is attached** because USB attach cuts the 5 V rail.
4. Then **the battery**.

**All of these as ENSEMBLES.** Plus BLE and LoRa beacons present, and a dev-board LED
pattern. Two standing instructions: **"don't hang on a decision — order a commit and push
and move past it"**, and **"always check with Specs / canon."**

**OTA is not just first, it is the delivery mechanism for the rest** — one USB write all
night, then every later capability arrives over the air.

## Repo state — ground truth

- Branch `gate-heredoc-2026-07-20`. **Pushed, ahead=0.** Tree clean at write time.
- Ledger tail: **D-20260726-37**.
- Remote `master` still deliberately lags this branch; the merge is a separate Roy step.

## What is proven, and what is still a conjecture

**PROVEN tonight — the first rung.** X1 enters ROM download mode **and returns to the
running app, button-free**, which matters because the BOOT/RESET buttons are physically
under the LoRa piggyback. Both boards are native USB-Serial-JTAG, so the D5→X1 inference is
same-class rather than a leap. Exit was established by an **inverted test**: a no-reset
connect *failed* on `0x41` (app console data, not a ROM sync frame), and a board stuck in
download mode **would have connected**.

**PROVEN — both images.** Two relay-floor images (A/B, differing only by baked BUILD_ID)
built, attested, two-leg eligibility PASS on both with **positive and negative controls**.
`mark-valid` is **health-gated**, deferred 8 s, PendingVerify-only, with an Invalid+revert
fail branch — so bootloader rollback protection is intact and recovery does not need the
buried buttons.

**STATIC ONLY — the beacons.** Both BLE and LoRa emitters are reached and not gated in the
shipping feature set. Hive refused to claim on-air from static analysis, which is the right
line. **On-air is a metal check that has not happened.**

**NAMED RISK, not yet met.** `main.rs:1208` records `advertise()` hanging on the coex build,
and the **tri-radio WiFi+BLE+LoRa combination is metal-unverified**, against a standing
~4 min hang already recorded as an OTA blocker. Hive has been asked for a **pre-registered
prediction before the run**. HANG_CAP is in the image for exactly this.

**OPEN.** X1's persona and its dev-TG membership are **unread**. A 0-line console read was
correctly refused as evidence — a null with no positive control.

## The one thing blocking the flash, and it is structural

**The image-A grant is deliberately not written, because the artifact does not exist.**
Creds-baked images have a different sha256, and a grant naming an uncomputed sha is a
decorative field. **So credentials are the critical path, ahead of the flash.**

Two paths race:

- **Preferred** — if **Alfred can host an AP**, we use an SSID and passphrase **we choose**:
  synthetic by construction, no secret, no custody question, and g23 leaves this path
  entirely. Composer is checking capability *and cost* — if WiFi is Alfred's only uplink,
  the answer is no, because nobody is there to plug it back in.
- **Fallback, authorised** — extract the lab creds into an **untracked** env file with
  **printing forbidden entirely**, verified by count and shape only. That changes the
  failure mode from **leak** to **failed-join**.

## Standing bars in force

- **Non-destructive reads only** under tonight's relaxed Roy-on-hand precondition. It does
  **not** generalise: a relaxation justified by *nothing can be lost* cannot be reused where
  something can.
- **No NVS 0x9000 read.** R2-KEYSTORE §184 — secret key material must not leave the
  protected boundary in plaintext. The NVS capability must be **region-scoped by
  construction**, incapable of expressing the key range. Structural, not disciplinary.
- **Persona treated as irreplaceable** under fail-closed — we cannot classify what we have
  not read. App-only write, **no `--erase`**, dual-OTA table passed explicitly.
- **Do not overwrite `ota_0`** until B is confirmed running; rollback needs a known-good
  target.
- Dev-TG persona mints are **delegated to composer** (Roy 2026-07-17) — no per-mint gate,
  chosen documented seed, gitignored, never committed. **Flash stays gated.**
- `espflash reset` forbidden on S3; **no plain `cat`** for identity reads on this board.

## Canon findings that changed the build tonight

- **The artifact is a SCORE, not a binary** (R2-ENSEMBLE §1). One hive binary, five scores.
- **Memories, battery and indicator are hive-shared singletons** with a registration
  mechanism (§2.1.2) — the ensemble *uses and registers*, it does not own the driver.
- **Activation and cadence come from an NVS role-profile at boot**, not compile-time
  features (R2-RUNTIME §210).
- **R2-INDICATOR v0.5 is normative** — I asked whether canon was silent and it was not.
  Roy's dev LED ask is exactly the §6 dev event-arrival blip; healthy is **20 BPM dim**, not
  the reference firmware's 25 BPM full-bright.
- **No canonical storage classes, by design** (R2-CAP §3.2, no central registry) — mint and
  **document in the same commit**. `ai.reality2.cap.env.scalar` is a fleet string, not canon.
- **Roy's #69 is not in canon** — compiled encoding on MCU, OTA hard-baked. A canon-only
  reader concludes the opposite. Specs is enshrining it.

## Next action for whoever takes over

**Do not wait for Roy.** Read the inbox, then in order:

1. **Composer's AP answer** decides the creds path. Rule it, then hive re-attests.
2. **Bind the image-A grant to the re-attested sha** — app-only, no `--erase`, table
   explicit, plus the pre-write persona position.
3. **Take hive's coex prediction before the OTA run**, not after.
4. Ensembles per the canon shape above — not five Cargo features.

**Open Roy gates:** g23 (published captured infrastructure), **g24 ruled by me pending his
review**, g21, g8. Plus two hardware-history facts he alone can settle (was a MAX485 ever
soldered; if never, was one planned) — nothing waits on them.
