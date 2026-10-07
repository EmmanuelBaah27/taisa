# Taisa Project Memory

## Purpose

This index is the entry point for durable Taisa context. It routes agents to the
narrowest authoritative source without duplicating status, technical documentation, or
work history.

## Authority order

1. [`AGENTS.md`](../AGENTS.md), [`CLAUDE.md`](../CLAUDE.md),
   [`docs/workflow.md`](workflow.md), and the
   [Taisa workflow orchestrator](../.claude/skills/taisa-workflow/SKILL.md) define how
   work is performed.
2. Canonical domain documents describe the system's present behavior.
3. [Accepted decisions](decisions/README.md) explain why consequential choices were made.
4. [Reusable learnings](learnings.md) are advisory until promoted into a workflow rule,
   decision record, test, or canonical domain document.
5. Linear owns live roadmap, Scope, Plan, stage, priority, ownership, blockers, acceptance,
   and gate evidence. Historical feature scopes, specifications, plans, and QA notes retain
   work-specific intent and history only.

When sources conflict, use the canonical domain document for present behavior, the
latest accepted decision for approved reasoning, and the Taisa Linear project for live work
status. Reconcile the contradiction before changing product code.

## Start here

- Workflow process and safety: [`docs/workflow.md`](workflow.md)
- Live product direction, milestones, work, and approval gates: Taisa Linear project
  `31b0d99c-6f74-4c9c-af2a-12e6e25aabe0`
- Historical build state and legacy behavior: [`docs/v1-status.md`](v1-status.md)
- Architecture and data ownership: [`docs/architecture.md`](architecture.md) and
  [`docs/data-model.md`](data-model.md)
- API behavior: [`docs/api.md`](api.md)
- AI behavior: [`docs/agent-persona.md`](agent-persona.md)
- Mobile UI rules: [`docs/design-system.md`](design-system.md)
- Prospective direction: relevant Linear milestone descriptions; create an issue only when
  someone takes responsibility for actionable work.

Read only the domain documents relevant to the task after completing the mandatory
workflow orientation.

## Decisions

The [decision index and template](decisions/README.md) define when to create a record,
which statuses are valid, whose approval is required, and how supersession preserves
history. Accepted records are durable constraints; proposed records are not authority.

## Reusable learnings

[`docs/learnings.md`](learnings.md) retains concise, evidence-backed findings likely to
affect another feature or future decision. It is not a task log. Corrections are appended
and linked rather than silently rewriting prior evidence.

## Work history

- Feature scopes and QA notes: [`docs/features/`](features/)
- Implementation plans: [`docs/superpowers/plans/`](superpowers/plans/)
- Design specifications: [`docs/superpowers/specs/`](superpowers/specs/)
- Repository history: Git commits and pull requests

At Review, record Closeout in Linear. Keep repository evidence only when it must version
with code; historical scopes and plans remain history rather than live authority.
