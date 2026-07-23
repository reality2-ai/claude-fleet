# Safety & permissions

The full permission model for fleet members: permission modes, the
skip-permissions rationale, the self-reporting hooks, the auto-approve hook,
and the firmware/key escalation gate. A short summary lives in the
[README](../README.md).

`fleet` members are **autonomous coding-agent sessions** running in your repos —
Claude Code by default, Codex when configured. They read, edit files, and run
shell commands on their own. Treat them with the same care as any agent you let
act unattended:

- **Mind `permission_mode`.** Each member can set `permission_mode` in `fleet.toml`
  (`default` · `acceptEdits` · `plan` · `bypassPermissions`). `bypassPermissions`
  skips Claude Code's per-action approval — handy for unattended runs, but the
  session can then edit and execute without prompting. Start at `default` /
  `acceptEdits` and only loosen it for repos you're willing to let an agent change
  on its own.
- **Run them in version control.** Members work directly in your working trees;
  commit or stash anything you don't want touched, and review their diffs like any
  other contributor's.
- **Autonomy with a failsafe, not a leash.** The intended model: managed
  **workers run unattended** by default (Claude:
  `--dangerously-skip-permissions`; Codex:
  `--dangerously-bypass-approvals-and-sandbox`; toggle
  `FLEET_SKIP_PERMISSIONS=off`) so they never stall waiting for a human, while
  the **supervisor stays prompt-gated and *monitors*** them — that oversight,
  plus the hook below, is the safety layer.
  The doctrine is to make risky changes *recoverable* (checkpoint to git) rather
  than to block them. See [Operating doctrine](DOCTRINE.md#operating-doctrine).
- **Routine prompts auto-confirmed; high-stakes ops escalated.** A `PreToolUse`
  hook auto-approves a non-destructive set (reads, in-repo edits, read-only shell)
  so members don't stall on "press-enter-for-yes" — destructive/ambiguous actions
  still prompt, and one high-stakes class (firmware-flash / firmware-sign /
  key-mint / writes to key-or-signature artifacts) is **hard-denied and escalated
  to you**, even under skip-permissions. See
  [Auto-confirming routine prompts](#auto-confirming-routine-prompts); toggles
  `FLEET_AUTOCONFIRM=off`, `FLEET_FIRMWARE_GATE=off`.
- **Remote control is opt-in and per-member.** `fleet remote-control` exposes a
  session to claude.ai/code and the mobile app (signed in as you) — enable it
  deliberately and turn it off when done.
- **State is local, not secret-scrubbed.** `<workspace>/.fleet/` holds tasks,
  mailboxes, and logs as plain JSON. The bundled `.gitignore` already excludes the
  runtime parts — keep it that way; don't commit a workspace's `.fleet/` runtime to
  a public repo.

## Self-reporting hooks

`fleet init` installs hooks into `<workspace>/.claude/settings.json` that make
every session record its id, current task, and edited files to
`<workspace>/.fleet/state/<id>.json`. Liveness is derived honestly from the
session transcript's mtime (plus a tmux window if managed), so a session that
dies uncleanly still shows as `dead`.

**Hook scope — important if you run sessions in sub-repos.** Claude Code loads
hooks from the session's *own* project, so a session started in a sub-repo does
**not** inherit the workspace-root `.claude/settings.json`. Two mechanisms close
that gap:

- **Managed members** (`fleet up` / `fleet dispatch`) launch with
  `--settings <workspace>/.fleet/managed.settings.json`, so they always
  self-report regardless of cwd. Nothing to do.
- **Hand-started sessions** in sub-repos need the user-scoped install:
  `fleet install-hooks --user`. These hooks no-op instantly outside any `.fleet`
  workspace, so a global install has no effect on your other projects.

## Auto-confirming routine prompts

Fleet members are semi-autonomous, so stopping to approve every routine action
gets in the way. A `PreToolUse` hook (`hooks/auto-approve.sh`) auto-approves a
**curated, non-destructive set** so members don't wait on the usual
press-enter-for-yes prompts — while anything risky or ambiguous still stops for
you. For most tools it never *forces* an outcome: worst case it stays silent and
the normal prompt appears. The **one deliberate exception** is the high-stakes
gate described below, which actively *denies* and escalates.

**Auto-approved:** read-only tools (`Read`, `Glob`, `Grep`, `LS`, `NotebookRead`,
`WebSearch`); file edits **inside the workspace**; safe shell reads; named
`git add`, `git commit`, non-force `git push`; and scoped build/test runners
(`cargo check|build|test`, `npm run test|build|lint|typecheck`, etc.). Safe
pipelines and `&&` chains are allowed only when every segment is itself allowed.

**Still prompts (everything else):** writes outside the repo, `rm`/`mv`/`dd`,
installs, arbitrary network (`curl`/`ssh` …), `sudo`, force-push, the genuinely
irreversible git ops (`rebase`, `clean`), publish/install runners,
redirection/substitution, and unknown tools. Genuine decision questions an agent
raises ("which approach?") aren't permission prompts, so they always wait for you.

**Auto-approved after a silent checkpoint.** The *recoverable-but-tree-changing*
git ops — `reset` (incl. `--hard`), `checkout`, `restore`, `merge`, `pull` — are
**not** blocked: the hook first snapshots your working tree to a
`refs/auto-checkpoint/*` ref (via `git stash create`, without touching the tree),
then auto-approves the op, so a wrong one is unwound with
`git stash apply <ref>` rather than gated. That is the GitHub-failsafe stance —
make risky changes *recoverable*, not *blocked* — so under skip-permissions these
run; only the un-checkpointable `rebase`/`clean` still wait for you.

**The firmware / key escalation gate (hard-deny).** Under
`--dangerously-skip-permissions` a silent fall-through would *run* a dangerous
action, so one high-stakes class is **actively denied and escalated to a human**
instead — flashing/signing firmware and minting/handling key material, where a
wrong move is irreversible. The hook denies (telling the agent to escalate with
the exact artifact/target/authority/reason) on:

- **commands** — `espflash` / `esptool` / `probe-rs download|run|erase` /
  `dfu-util` / `openocd` / `nrfjprog` … (flash); `openssl genpkey|genrsa|-sign|dgst`
  / `ssh-keygen` / `gpg --sign|--gen-key` … (key-gen / sign); `dd of=/dev/…`; and
  explicit `ota … sign|push` / `mint … cert` / `… write-persona` verbs;
- **writes** to key/signature artifacts — `*.key` `*.pem` `*.sig` `*.der` `*.p12`
  `*.seed` `tg_priv*` `*persona*.bin` `keystore*.db` `wallet*.dat` …

Source edits, builds, and reads are **unaffected** — only the dangerous
operations escalate. See the `hs_bash` / `hs_path` patterns in
`hooks/auto-approve.sh`.

It only acts inside a `.fleet` workspace, and is **on by default** for managed
members. Toggles (env): `FLEET_AUTOCONFIRM=off` disables it entirely;
`FLEET_AUTOCONFIRM_EDITS=off` keeps prompting for edits while still auto-approving
reads; `FLEET_FIRMWARE_GATE=off` disables the firmware/key gate. Tune the safe
set in `hooks/auto-approve.sh` (the `bash_safe` allowlist + the `hs_bash` /
`hs_path` gate).
