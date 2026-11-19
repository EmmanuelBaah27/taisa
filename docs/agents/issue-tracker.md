# Issue tracker: Linear

Taisa work lives in the Linear project `Taisa`. Linear is the sole live authority for work
state. If Linear is unavailable, do not create or advance work, change blockers, or claim
approval; follow the fail-closed continuation rule in the Taisa workflow adapter.

- Project: `31b0d99c-6f74-4c9c-af2a-12e6e25aabe0`
- Team: `e95356d8-17f7-4700-bdfe-222782bea546`
- Team key: `APF`

Use the connected Linear tools for issue operations.

Before creating work, follow the intake, duplicate-search, authority, dependency, stage, and approval rules in:

- `AGENTS.md`
- `.agents/skills/taisa-workflow/SKILL.md`

When a skill says to publish, fetch, block, claim, or resolve a ticket, perform the equivalent operation in Linear. Use native parent and blocking relations where applicable.

Ordinary technical planning is agent-owned. Baah decides product intent, materially different
experiences, sensitive or difficult-to-reverse choices, physical or perceptual QA, and Ship.
Record only decisions or stable delivery checkpoints in Linear. Do not post routine command logs,
unchanged waits, or repeated evidence.

GitHub is the source and pull-request surface. It is not Taisa’s issue authority.

A Matt skill’s readiness language never overrides approved product intent, material or high-risk
decision gates, Build readiness, QA, physical-device judgment, or Ship.

## Operating rules

- Milestones represent strategic outcomes, not authorization.
- Issues represent independently valuable actionable work.
- Sub-issues represent distinct review, owner, dependency, or approval boundaries.
- Checklists/comments hold commands and small steps.
- Relations express blockers/dependencies; project updates report program health.
- Before creation, search exact and semantic matches; continue an equivalent outcome.
- Purely prospective direction stays in a milestone description until someone owns action.
- Update the issue only for material events: approval evidence; Build start; blocker change;
  stable candidate and verification; canonical preview and QA request; QA failure and verified
  replacement; Ship, merge, and Closeout. Do not narrate commands, polls, retries, or passing
  narrow tests.

Status IDs: Todo `8092f145-a7b5-4e09-812e-1d3212fc1c7d`; In Progress
`ad545d06-1ef1-4c5d-86c7-44e1e3724409`; Done
`b2c07c6b-bf80-40d1-8e08-9c941b04f137`; Canceled
`e2a4cb1f-daf0-4269-8acc-9b0fed9224f5`.

Linear failure: retry issue creation once, record the failed action, preserve local evidence,
and continue only work supported by approved product intent, recorded material or high-risk
decisions, and readable agent-owned technical evidence.

## Deferred-capability stewardship

When Baah or an approved artifact explicitly defers a capability, search Linear for exact and
semantic matches before mutation. Continue the matching issue when its intended outcome is
equivalent; otherwise create one non-duplicate Backlog issue in the relevant milestone. A
deferral is live Linear state, not a repository backlog and not authorization to scope or build.

Each deferral records origin and reason, user value and reconsideration trigger,
dependencies/unknowns, architectural guardrails, durable Git and Linear evidence, and dated
lifecycle history. Lifecycle is **Captured → Watching → Candidate → Planned → Shipped or Dropped**:

- Captured preserves the outcome without prioritizing it.
- Watching means evidence or dependencies are being monitored.
- Candidate is a recommendation only and does not authorize active work.
- Planned requires Baah's product-intent approval, any required material or high-risk decisions,
  and the agent-owned technical plan recorded in Linear.
- Shipped requires canonical `main` merge evidence and applicable acceptance.
- Dropped requires Baah's explicit decision or documented supersession evidence.

Before activating work, consult related deferrals for dependency, guardrail, and duplicate
conflicts. At Review and before Ship, reconcile any lifecycle change against actual code,
canonical preview, verification, device evidence, and `main`; never promote a deferral merely
because implementation resembles it. Linear owns live lifecycle; Git owns the durable
technical constraints and evidence that must version with code.

Deferring concurrent voice behavior must not hard-code permanent mutual exclusion between
capture and playback into current audio/session contracts. Linear holds the mutable outcome
inventory and lifecycle; Git retains only this durable architectural guardrail.

## Monthly reconciliation heartbeat

The monthly stewardship heartbeat runs on the first Monday at 09:00 Africa/Accra. It reads
the current Taisa Linear issues/milestones and relevant durable Git contracts, reports access
failure honestly, and surfaces only meaningful dependency, guardrail, evidence, or lifecycle
contradictions. It remains quiet when there is no meaningful change. It may update safe routine
evidence, but it never approves product intent, material or high-risk decisions, priority
changes, lifecycle promotion into active work, or Ship.
