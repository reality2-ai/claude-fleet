# Deployed hook digests

**Why this file exists.** `pre-push` and `commit-msg` are installed into each repo's
`.git/hooks/`, which is **not tracked and not cloned**. r2-core measured the consequence and
stated it exactly:

> *A hook that is untracked is not merely lost on a clone; it is **unciteable while it is
> running**.*

On 2026-08-08 `pre-push` moved **four times in one day**, twice within twelve minutes, and
**no worker tree held any record of any of them** — so "which version of the gate judged this
commit" was unanswerable from the repository the commit lives in.

**Ruling (supervisor, 2026-08-08): the fleet hooks are NOT tracked in worker repos, and this
log is the compensating record.** Tracking them would put a lane's own gate inside the tree
that lane writes to — two writers on one file, which is exactly how r2-composer's local
`pre-push` fix was silently reverted by an installer on 2026-08-08. The gate that judges a
lane must not be editable by it. What was actually missing was not version control but an
**auditable deploy record**, which is this.

**Obligations.**
- Every deploy of `hooks/git/*` appends a row here **in the same change** that ships it.
- Each lane records the digest it ran under (r2-hive and r2-standard already do; r2-standard
  prints untracked-hook digests in its own gate output, which is how it observed three of the
  four moves below **without being told**).
- A citation of a gate is **revision-scoped to its digest, not to a time** — r2-core's rule.
  A claim naming only a clock time cannot survive two deploys in the same minute.

## pre-push

| sha256 (12) | source commit | deployed | what changed |
|---|---|---|---|
| `fa53216b4d94` | `d39e3c2` | 2026-08-08 18:53 | report trailer FORM, not absence; print the offending line |
| `21f57e14a71f` | `702cf2f` | 2026-08-08 19:02 | ledger matched by basename at any depth (arm had been **inert** in `r2-impl`); undated `D-nnn` accepted |
| `c7d2c0fcdccf` | `a8e6490` | 2026-08-08 19:11 | remedy lists every accepted form; only the bullet that fired prints; exemption **counted** on every push |

Earlier same day: `51cc8c0` 09:38 widened the trailer pattern to accept `R-` and `dNNN`.
It reached **r2-composer and r2-impl only** — r2-standard and r2-android ran the older,
stricter arm until 18:53 and **neither knew**. That drift is the reason this table starts at
the first digest anyone recorded rather than at the first deploy.

## commit-msg

| sha256 (12) | deployed | note |
|---|---|---|
| `98ed78e2d499` | before 2026-08-08 | unchanged across all of 2026-08-08 |
