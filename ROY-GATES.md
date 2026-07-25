# Decisions waiting on Roy

One current list. Supervisor adds a gate when it opens, removes it when you rule;
history lives in DECISIONS.md. Empty file = nothing waiting on you.

**To interrogate a gate with AI help:** `cd ~/Development/R2/claude-fleet && claude`
then: *"read gates/g3 and argue both sides with me"* — a fresh Claude with the brief,
the ledger, and the repo. Or open the brief's GitHub link from any browser and paste
it into claude.ai.

**To rule:** tmux window 0 (supervisor), type e.g. `gate 3: regenerate`. Ruling
syntax is at the bottom of every brief.

---

## g8 — WiFi AP client isolation blocks the phone↔tuxedo UDP path (small, physical/network)
The phone UDP metal test is DONE except the last hop: phone sends the probe correctly,
tuxedo's echo server works, but the datagram never arrives — your WiFi AP has
client isolation on (wireless client ↔ wireless client blocked; ICMP 100% loss both
ways). Fix is any ONE of: disable AP client isolation · put tuxedo on ethernet ·
use a non-isolating SSID. Then composer re-runs (2 min). Not urgent — cell stays
annotated transport-only either way.

GitHub: https://github.com/reality2-ai/claude-fleet/tree/gate-heredoc-2026-07-20/gates

## g12 — one sudo command unblocks the D5 crash forensics (tiny, Alfred)
D5 is sitting in its idle-hang state with the crash registers intact, and composer has
openocd ready to read them over the board's built-in USB-JTAG — no reset, read-only.
The only blocker is USB permissions (libusb EACCES; the board was never touched).
**CORRECTED COMMAND (07-25 13:xx):** the original `cp 60-openocd.rules` was run at
12:41 but cannot work here — those rules grant `GROUP="plugdev"` (a Debian group that
doesn't exist on Manjaro; nodes stay root:root) plus `uaccess` (local seat only;
composer works over ssh). This one actually fixes it, on **Alfred**:
```
sudo sh -c 'printf "SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"303a\", MODE=\"0666\"\n" > /etc/udev/rules.d/61-espressif-jtag.rules; udevadm control --reload; udevadm trigger'
```
(Espressif VID only, bench machine — composer verifies node perms and attaches
automatically once it lands.)
**Update:** the v8.4 flash (with the watchdog) went ahead overnight, so the held window
was consumed. The capture is still worth having: once you run the sudo, composer can
pre-arm a JTAG breakpoint at the fault handler and catch the next hang *before* the
watchdog resets it. Same one command, same value — just no longer time-critical.
**Update 07-25:** value went UP. The v8.5 cycle proved the ~4min double-fault hang is
now THE blocker for OTA (it pre-empts every OTA window; the radio-mask fixes all work).
This sudo gives the fastest root-cause read — JTAG catches the fault registers live.
The firmware-side alternative (v8.6 exception hook) is being designed in parallel.
**Update 07-25 (midday) — time-boxed bonus:** D5 is right now sitting in a NEW failure
state the firmware instrument can't see: its radio RX silently wedged (TX fine, peers
alive, no crash — plausibly the same memory corruption landing somewhere non-fatal).
The board is alive, so JTAG can inspect the wedged state read-only, no reset. Window:
until the v8.7.1 flash goes out (~2h). Run the sudo above and composer attaches before
the flash; after that the state is gone. Same command, still valuable afterwards too.

## Not waiting on you
- Blerole D4 reflash (iter 2, L3 fix) + D5 sensor flash — pre-granted, in flight.
- Multi-hive / multi-TG scale-out — gated on the below-TG substrate lock (the table
  is the gate-keeper, not a ruling).
- Waveform-as-sentant implementation — core owns it under your layer ruling.

## Closed — record of decisions past

| # | Gate | Ruling | Ref | Brief |
|---|------|--------|-----|-------|
| 1 | Key-10 liveness window | both axes compose: transport floor × observed cadence; lifecycle + mobility folds | #d015 | [g1](gates/g1-key10-liveness-window.md) |
| 2 | Persistent 0x25 | dev bearer-ping + beacon-level awareness; heartbeat ≠ transport test; pump dead | #d018 | [g2](gates/g2-persistent-pump.md) |
| 3 | composer manifest.json | regenerate — EXECUTED ab62a0e (was chip-split staleness, not corruption) | #d016 | [g3](gates/g3-composer-manifest.md) |
| 4 | SEN0676 radar | set aside; D5 = bench test tool; radar later on a XIAO | #d017 | [g4](gates/g4-sen0676-radar.md) |
| 7 | TG contact hops | relax to two-hop (one go-between; TTL=2); canon landed HEARTBEAT v0.24 §7 | #d019 | [g7](gates/g7-tg-contact-hops.md) |
| 6 | Baked member roster | adopt as dev seed of runtime member-set; canon D-13/-14; merge + wiring dispatched | #d020 | [g6](gates/g6-baked-roster.md) |
| 5 | Alfred rig fork | defer until phone-pair merge proven on metal; stays two hives + relay; reopens automatically | #d021 | [g5](gates/g5-alfred-rig-fork.md) |
| 9 | D5 USB replug | replugged 07-24 06:2x; "sleeping tuxedo" = wrong-host artifact (dead node `tuxedo` vs live `tuxedo-os`); suspend/powersave asks withdrawn | #d026 | — |
| 10 | v8 OTA radio quiesce | blessed as shaped 07-24 (relay-island dark + collectors-astray accepted); v8 build GO | #d026 | — |
| 11 | D5 replug / bench USB | closed 07-24 22:5x — tuxedo uplink cable bad (data lines); boards moved to Alfred, all 3 stable; v8.3 cycle firing | #d026 | — |
