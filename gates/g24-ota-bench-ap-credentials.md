# g24 — which WiFi does the OTA proof join?

> ## RULED 2026-07-26 (supervisor, overnight, pending Roy): **SYNTHETIC AP — option A.**
>
> **This reverses my own ruling made ninety minutes earlier**, and the reason belongs on the
> record: I first ruled **real creds via env**, because I believed a synthetic AP **required a
> human awake to stand one up.** That premise is refuted. <rig-host> carries `phy2` — a **spare,
> idle, route-free, AP-capable 2.4 GHz USB radio** — and hosts an AP natively through nmcli
> with no package install. **The ruling followed from the premise; the premise was wrong; the
> ruling changes.** That is not a preference reversal, and I would rather show the sequence
> than quietly present the second answer as the first.
>
> **What the reversal deletes:** the entire credential-custody branch. Chosen SSID and
> passphrase are **synthetic by construction** — no secret, no custody question, no commit
> edge, and **g23 leaves this path completely.** The no-print extraction I had authorised as a
> fallback is **withdrawn unused.**
>
> **Hard bound, and the lane refused it before I said so:** `wlp3s0` is <rig-host>'s **sole
> uplink** (ethernet is unplugged). It is AP-capable and it is **not to be touched.** If the
> `phy2` bring-up fails, stop — do **not** fall back to the uplink radio. Nobody is there to
> plug in ethernet.
>
> **One honest gap the lane raised against its own proposal:** `iw` reports the rtw88 dongle
> AP-capable, but capability is not function — that is the presence-is-not-reachability shape.
> A bring-up test on the idle spare radio comes **first**, confirming the driver *sustains* an
> AP and that X1 actually associates.
>
> Roy can overturn this in one line. The text below is the original brief, kept intact.

**Opened 2026-07-26 by supervisor. Small gate, but it blocks a build that is otherwise
ready to run.**

## The situation

The OTA round-trip on X1 needs the board to join a WiFi network — `ota_task` opens a
socket on the WiFi netif (`main.rs:1056`, port 21043) and the push comes from the host.
Both images are **built, attested and eligible**; the only thing standing between them
and a flash build is *which network's credentials get baked in*.

The lab network's SSID and passphrase are **the captured home-network infrastructure that
is the live half of g23**.

## What is NOT the question

The lane that raised this called the creds "held under Roy's ruling". **They are not.**
No ruling has been issued; g23 is open, and what is held there is *scrubbing published
captured infrastructure* — not *using* it. **Building from an environment variable is not
publication.** That correction has been banked and the lane has fixed its own snapshot so
it does not become folklore.

The real constraint is narrower and stricter, and it applies either way:

> **R2-SECRETS §3.1** — a real value must never appear as a **literal in any tracked file
> of any repo.** So `build.rs` reads env, never a literal, and the creds appear in no
> commit, recipe, attestation, sha-provenance note, or fleet message.

## The options

**A — synthetic bench AP (supervisor recommendation).** A phone hotspot or spare router
with a certified-synthetic SSID/PSK. Exercises the *identical* code path, proves the
*identical* round-trip, and puts **zero captured infrastructure into any build**. It
decouples the OTA proof from g23 entirely — g23 stays purely a publication question and
stops sitting on the critical path.

**B — real lab creds via env.** Permitted under canon provided they stay out of every
tracked file and message. But it puts the home network into the build path **for no proof
benefit**, and it means every future re-attest carries that exposure surface.

There is no third option where the creds are baked *and* recorded — §3.1 forbids it.

## Consequence either way

Baking creds changes the binary, so the attested hashes move. Hive has already committed
to **re-attesting both images, both eligibility legs, with controls, at flash-build time** —
its empty-creds attestation deliberately covers only what is creds-independent (structure,
instrument, BUILD_ID, eligibility). That was its own call and it is the right one.

## Ruling syntax

`gate 24: synthetic` — provision a synthetic bench AP; hive builds against it.
`gate 24: real creds` — bake the lab creds via env, never into a tracked file.
