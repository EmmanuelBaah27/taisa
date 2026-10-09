# Taisa bounded delivery Goal

Fill every field before creating a Goal. Replace angle-bracket guidance with exact evidence.

- Primary Linear issue: `<APF-ID and URL>`
- Milestone context: `<name and URL>`
- Run type: `<BUILD | REPAIR | SHIP>`
- Entry state and evidence: `<state plus approval/comment URL>`
- Terminal outcome: `<one allowed outcome for this run>`
- Approved kickoff or Scope/Plan evidence: `<URLs>`
- Work slices: `<each task owned by Platform | Product | Integration>`
- Branch/worktree: `<branch and absolute path>`
- Canonical preview baseline: `<SHA or not-device-facing>`
- Acceptance criteria: `<Linear checklist>`
- Verification matrix: `<exact commands and checks>`
- Permitted mutations: `<bounded list>`
- Prohibited actions: `<bounded list>`
- Repair evidence: `<attempts and quarantine state, or not-a-repair>`
- Next Baah gate: `<one gate>`

## Objective

Advance only the primary Linear issue from the recorded entry state to the named terminal
outcome. Use incremental orientation after the initial reconciliation. Own routine Git,
GitHub, Linear, verification, documentation, canonical-preview, and repair work permitted
above without asking Baah to say “continue.”

## Runtime rules

- One primary issue, one conductor, and one active Goal run.
- Every task belongs exclusively to Platform, Product, or Integration when cross-stack.
- Update Linear only for approval, Build start, blocker change, stable candidate, preview/QA,
  defect/replacement, Ship/merge, and Closeout evidence.
- Every repair attempt must produce new evidence, a changed hypothesis or implementation,
  or a more discriminating test.
- A Baah defect observation enters `REPAIR_QUARANTINE`; do not request another test until
  the repair-release gate passes.
- Each repair-release gate item must pass or be explicitly marked inapplicable with evidence;
  an omitted item does not pass the gate.
- Device-facing QA requires the exact verified commit on canonical `preview/taisa`, confirmed
  served or installed, plus agent-owned simulator/accessibility/preview smoke checks.
- Never infer approval, start a successor issue, expand Scope, resume another chat, perform
  destructive cleanup, or merge without the named authority.
- Prohibit unchanged polling. Prefer an event-capable wait. If none exists, record
  `EXTERNAL_WAIT_RECORDED`, complete this Goal, and schedule or request one later check near
  the normal terminal window.
- Do not emit user or Linear updates for unchanged state.

## Allowed terminal outcomes

### BUILD

- `QA_READY`
- `UNRESOLVED_ESCALATION`
- `MATERIAL_REAPPROVAL_REQUIRED`
- `NON_DEVICE_SHIP_READY`
- `EXTERNAL_WAIT_RECORDED`

### REPAIR

- `QA_READY`
- `UNRESOLVED_ESCALATION`
- `MATERIAL_REAPPROVAL_REQUIRED`
- `EXTERNAL_WAIT_RECORDED`

### SHIP

- Verified merge, safe cleanup, Linear Closeout, and next-outcome recommendation completed.

## Completion report

Report the terminal outcome, exact branch and commit, PR/CI state, canonical preview revision
or non-device path, checks and results, unresolved risk, Linear evidence, and next Baah gate.
For Ship, recommend but do not start the next outcome. Complete the Goal after reporting.
Do not remain active solely for waiting on Baah or external state.
