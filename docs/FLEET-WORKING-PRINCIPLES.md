# Fleet Working Principles

Generic, reusable working principles for a **claude-fleet** deployment — the methodology that pairs with the
tooling in this repo. They are project-agnostic. *Project-specific* context (architecture, tasks, decisions,
status) lives in that project's OWN private fleet-context repo, never here.

## 1. Spec-first
A canonical **specification is the single source of truth**. Every change lands in the spec FIRST, before any
coding; code implements the spec and never leads it. Where there is a cross-cutting canon plus per-component
specs, the cross-cutting canon governs and the component specs + code follow it.

## 2. Secure over calm; calm where safe
Prefer the **more secure** option over the less secure (primary tie-breaker). Prefer **calmer technology**
(peripheral / on-demand over interrupts) in UX. When the two conflict, security wins by default — surface
low-risk calm tradeoffs to the human rather than silently choosing calm.

## 3. GitHub as the failsafe
Reserve human prompts for genuine **DIRECTIONAL** decisions (a vs b vs c). For potentially-dangerous changes,
**commit + push a checkpoint to GitHub** so it can be unwound — don't block on a human, make it recoverable.
Every agent actively uses GitHub as its undo buffer (and the fleet keeps its OWN context save current and
pushed). Git best practices throughout: small focused commits, named adds (never `git add -A`), branch to
test, never force-push shared history.

## 4. The permission / auto-approve model
The fleet-wide PreToolUse hook (`hooks/auto-approve.sh`) auto-confirms what is read-only or recoverable, and
gates what is irreversible or outward. It never auto-DENIES — worst case is a needless prompt.
- **Auto-approved:** read-only commands + pipelines; `cd …&&` prefixes and `&&`/`;` chains where EVERY part is
  itself safe; read-only `gh`/MCP; inter-agent messaging; LOCAL git checkpoints (add-named / commit / fetch /
  branch / switch); `git push` (non-force); scoped build/test runners (check·build·test).
- **Still prompts:** irreversible/destructive (rm, force-push, reset --hard, clean, repo/disk delete),
  arbitrary execution (ssh, interpreters, command-substitution, redirection), outward sends, bulk staging.
- **Safety nets:** (1) a **pre-push secret-scan** git hook (`hooks/git/pre-push`) blocks any push that adds a
  token/key/.env — making auto-approved push leak-safe. (2) **auto-checkpoint before destructive ops** —
  snapshot first so the op is recoverable, then auto-approve it. Goal: only genuine decisions + a tiny
  truly-irreversible residue ever reach the human.
- Kill-switch: `FLEET_AUTOCONFIRM=off`. Bypass the secret-scan once (rare, deliberate): `FLEET_SKIP_SECRET_SCAN=1`.

## 5. Public code, private context (share the code, not the secret)
The tooling/code is shareable; secrets and project context are not. Pattern: a **PUBLIC code repo + a PRIVATE
repo alongside** for secrets/context. Never commit secrets (the pre-push scan enforces this). Before flipping
any repo public, **scrub the HISTORY** (or publish from a fresh snapshot) — removing a secret from HEAD does
not remove it from past commits.

## 6. Roles
A **supervisor** coordinates; per-component **experts** do the hands-on work. The supervisor writes only to
its own infra repos (the public tooling repo + the private context repo), **never to a worker's repo**.
Workers own their `RESUME.md` + WIP checkpoints. Route substantive technical/security questions to the
relevant expert rather than self-analysing.
