# Taisa bounded delivery run

Fill each field before a BUILD, REPAIR, or SHIP run. `docs/workflow.md` is authoritative for
candidate freeze, Preview, repair quarantine, QA, Ship, and cleanup. This template records run
evidence without copying those rules.

- Primary Linear issue and milestone:
- Run type and terminal outcome:
- Approved product or high-risk decisions:
- Agent-owned technical Plan:
- Branch, worktree, base, and remote relation:
- Direct blockers and dependencies:
- Permitted mutations:
- Prohibited actions:
- Acceptance criteria:
- Focused verification:
- Complete applicable matrix:
- Verification readiness:
- Candidate-freeze revision and invalidators:
- Canonical Preview baseline and publication evidence:
- Browser simulator evidence or inapplicable reason:
- Product design-system inventory and audit, or inapplicable reason:
- Approved design-system gaps or exceptions:
- Repair evidence and quarantine state, or not a repair:
- Next Baah gate:

## Objective

Advance only the primary issue to the named terminal outcome. Keep one accountable conductor.
Update Linear only at a decision or stable checkpoint. Do not infer approval, start successor
work, merge, publish, or perform destructive cleanup outside the recorded authority.

## Completion report

Report the outcome, exact branch and commit, PR and CI state, Preview revision or non-device path,
checks, unresolved risk, Linear evidence, and next Baah gate. A SHIP run also records verified
merge and safe cleanup evidence before Closeout.
