# Gate 3 — composer webapp/dist/manifest.json: regenerate or revert?

**Status:** OPEN · trivial · one word settles it
**Interrogate:** probably unnecessary — but `claude` in r2-composer can show you the diff

## Background

During the overnight campaign, a composer build half-regenerated
`webapp/dist/manifest.json` and left it dirty in the working tree — neither the old
committed state nor a clean new generation. It's a *generated* file (build output),
so no hand-written content is at risk either way.

## Options

- **Regenerate:** run the webapp build once, commit the clean output. The file matches
  current source. ~1 minute of composer time.
- **Revert:** `git checkout` the old version. Faster, but the committed manifest then
  lags the current source until the next build anyway.

## Supervisor lean

**Regenerate** — it's build output; the only correct state is "what the build makes
now". Revert just postpones the same regeneration.

## Ruling syntax

"gate 3: regenerate" / "gate 3: revert"
