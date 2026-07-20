# Key decisions — repository

Durable repo-local rulings and reviews. Read this before changing established behaviour.
This is not a task log and does not replace specifications, ADRs, or code.

## Rules

- Append key human/canonical rulings, explicit holds, and consequential agent choices.
  Routine edits, experiments, and task status stay out.
- Name the real decision-maker and authority basis. Agent judgment is delegated; never
  label it human-ratified or let it override canonical material.
- Existing records are immutable. Change a ruling with a new decision whose
  `Supersedes` names the old ID.
- Review by appending a review record. A review assesses a ruling but does not change it.
- Newer explicit authority or normative material wins a conflict; append the correction.
- IDs are `D-YYYYMMDD-NN` and `R-YYYYMMDD-NN`.

## Decision schema

- **Kind:** Decision
- **Date:** YYYY-MM-DD
- **Scope:** Affected surface
- **Outcome:** The ruling
- **Decision-maker:** Person, canonical source, or delegated agent
- **Authority basis:** Why this decision-maker may decide
- **Context:** Problem and constraints
- **Rationale:** Why this outcome fits
- **Alternatives:** Options considered and why rejected
- **Expected consequences:** Benefits, costs, and risks
- **Evidence:** User instruction, issue, test, file, commit, or other trace
- **Supersedes:** Decision ID or `None`

## Review schema

- **Kind:** Review
- **Date:** YYYY-MM-DD
- **Decision reviewed:** Decision ID
- **Reviewer:** Reviewer and authority/role
- **Observed outcomes:** What happened after the decision
- **Evidence:** Tests, incidents, metrics, feedback, or commits
- **Recommendation:** Keep, supersede, or gather evidence
- **Finding:** `appropriate`, `revise`, or `insufficient evidence`

## Records

<!-- Append records below. Do not rewrite old records. -->
