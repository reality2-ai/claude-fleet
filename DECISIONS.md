# Key decisions — claude-fleet

Durable index of key repo-local rulings. Read it before changing established behaviour.
It is not a task log and does not replace specifications, ADRs, or code.

## Rules

- Append key human/canonical rulings, explicit holds, and consequential agent
  implementation choices. Routine edits, experiments, and task status stay out.
- Name the actual decision-maker and authority basis. An agent choice is delegated
  judgment; never label it human-ratified or let it override canon.
- A decision records context, rationale, alternatives, expected consequences, and
  evidence. Existing records are immutable.
- Review a decision by appending an `R-...` record naming the decision, reviewer/date,
  observed outcomes, evidence, recommendation, and one finding: `appropriate`, `revise`,
  or `insufficient evidence`. A review does not itself change the ruling.
- Change a ruling only through a new decision that names the old ID in `Supersedes`.
  Current means the latest applicable decision not superseded by a later one.
- Newer explicit authority or normative material wins a conflict; append the correction.
- IDs are `D-YYYYMMDD-NN` for decisions and `R-YYYYMMDD-NN` for reviews.

## Records

### D-20260721-01 — Repository decision log

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** Repository process
- **Outcome:** Keep a terse repo-local log of key decisions and later reviews.
- **Decision-maker:** Roy
- **Authority basis:** Explicit user ruling
- **Context:** Key rulings were dispersed across transcripts, handoffs, and design files.
- **Rationale:** A uniform durable record makes reasoning and later appropriateness
  analysis discoverable without treating temporary agent prose as authority.
- **Alternatives:** Transcript/RESUME-only history was rejected as transient; ADR-only
  history was rejected because not every important ruling is architectural.
- **Expected consequences:** Easier audits and fewer re-litigated decisions, at the cost
  of one concise record when a key ruling is made.
- **Evidence:** Roy's 2026-07-21 request; [AGENTS.md](AGENTS.md).
- **Supersedes:** None

### D-20260721-02 — Fleet member onboarding and decision accountability

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** New fleet repositories and managed-agent workflow
- **Outcome:** Onboard a repository with a non-overwriting two-layer template: a terse
  shared contract and an explicit repo map covering authority, dependency direction,
  ownership, invariants, and verification. Managed agents consult the decision log before
  edits; publishing requires each new commit to update it or explicitly acknowledge the
  applicable decision or absence of one.
- **Decision-maker:** Roy for the required behaviour; Codex for the delegated mechanism
  choice.
- **Authority basis:** Roy's explicit 2026-07-21 instructions; implementation delegation
  within the fleet control-plane task.
- **Context:** Per-repo instructions share substantial policy but differ in authority and
  upstream/downstream relationships. A passive log can be forgotten, while duplicated
  prose grows context and invites contradictory interpretations.
- **Rationale:** One scaffold removes repetition, unresolved repo-map markers prevent
  agents from guessing, a central launch rule guarantees recurring visibility, and the
  existing pre-push boundary makes omissions reviewable without blocking local safety
  commits.
- **Alternatives:** Free-form per-repo instructions were rejected as drift-prone;
  overwriting existing files was rejected as destructive; commit-time rejection was
  rejected because it can prevent a recovery checkpoint.
- **Expected consequences:** Faster, consistent onboarding and auditable choices with a
  small trailer cost on routine commits. Repositories must complete their unique map
  before cross-repo or behavioural work.
- **Evidence:** Roy's requests for a new-repo template, shared/unique agent information,
  dependency mapping, and a log agents cannot forget; `templates/repo/`, `bin/fleet`,
  `hooks/git/pre-push`, `tests/smoke.sh`.
- **Supersedes:** None

### D-20260721-03 — Install every shipped repository hook

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** Git-hook deployment and drift detection
- **Outcome:** `fleet install-git-hooks`, `fleet init-repo`, and `fleet doctor` manage both
  shipped repository hooks: pre-push publishing safety and commit attribution. Preserve
  and chain foreign hooks.
- **Decision-maker:** Codex
- **Authority basis:** Delegated control-plane implementation and optimisation within
  Roy's fleet-hardening request.
- **Context:** Review found the tested `hooks/git/commit-msg` source present but missing
  from all seven deployed repositories because the installer and doctor knew only about
  `pre-push`.
- **Rationale:** A defined but undeployed guard is a false green. One enumerated hook set
  keeps installation and drift checking aligned without another command or copy process.
- **Alternatives:** Manual copying was rejected because it recreates silent drift; a
  second installer was rejected as needless mechanism; replacing foreign hooks was
  rejected as destructive.
- **Expected consequences:** Commit attribution becomes consistently deployed and drift
  becomes visible. Existing foreign hook behaviour continues through `.local` chaining.
- **Evidence:** Seven-repository `.git/hooks/commit-msg` inspection; `lib/githooks.sh`,
  `hooks/git/commit-msg`, and the positive/negative installer tests in `tests/smoke.sh`.
- **Supersedes:** None

### D-20260721-04 — Autonomous writers and automatic refuters in the R2 fleet

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** Fleet startup, permissions, and refutation topology
- **Outcome:** The R2 workspace starts its Claude lanes with explicit autonomous
  permissions, automatically starts Codex refuters, and sends `carry on` on fresh and
  resumed starts. Codex refuters operate unattended inside a read-only sandbox with
  approval set to `never`.
- **Decision-maker:** Roy
- **Authority basis:** Explicit user correction after the simplified fleet was tested
- **Context:** The migration disabled automatic pairs, replaced the first-start action
  prompt with an idle seed, and left autonomy partly implicit. The supervisor Codex
  companion also lacked the non-interactive flags already applied to worker refuters.
- **Rationale:** Independent writers and refuters are intentional fleet capabilities;
  removing them changed behaviour rather than merely shortening instructions.
- **Alternatives:** On-demand-only refuters and prompt-gated lanes were rejected for this
  workspace. Restoring long prompts was unnecessary because permissions, topology, and
  continuation are separate compact controls.
- **Expected consequences:** `fleet up` uses more agent lanes but resumes useful work
  without permission stalls; Codex refuters can inspect freely but cannot write.
- **Evidence:** Roy's 2026-07-21 correction; `.fleet/env`; `lib/provider.sh`,
  `lib/tmux.sh`, `bin/fleet`, and `tests/smoke.sh`.
- **Supersedes:** The unrecorded 2026-07-21 local choice to make persistent refuters
  opt-in for the R2 workspace

### D-20260721-05 — Intentional stop does not create RESUME staleness debt

- **Kind:** Decision
- **Date:** 2026-07-21
- **Scope:** Doctor handoff-state validation
- **Outcome:** Continue checking stopped managed repositories for a present, bounded,
  placeholder-free `RESUME.md`, but do not compare its mtime with activity generated by
  an intentionally stopped session.
- **Decision-maker:** Codex
- **Authority basis:** Delegated implementation judgment within Roy's fleet restoration
- **Context:** A fresh seed-only start and `fleet down` updated session activity without
  producing repository work. Doctor then reported five valid handoff files as stale.
- **Rationale:** Intentional shutdown is not evidence of unfinished work. Structural
  checks remain useful; timestamp freshness is meaningful only for a non-stopped lane.
- **Alternatives:** Touching or committing five unchanged RESUME files was rejected as a
  false audit trail; disabling all RESUME checks was rejected because it hides real gaps.
- **Expected consequences:** Start/stop trials stay green while active or crashed work
  still creates visible handoff debt.
- **Evidence:** Reproduced in `/R2` after the 2026-07-21 trial start; `bin/fleet` and
  stopped-session regression in `tests/smoke.sh`.
- **Supersedes:** None
