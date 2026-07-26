# g24 — which WiFi does the OTA proof join?

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
