# Taisa Codex Operating Instructions

## Mandatory startup

For every scoped build, fix, plan, review, or ship task:

1. Read `docs/workflow.md` and `.claude/skills/taisa-workflow/SKILL.md` completely.
2. Read `docs/project-memory.md`, then inspect only the accepted decisions, reusable learnings, and canonical domain documents relevant to the task.
3. Query the Taisa Linear project, milestones, active issues, dependencies, blockers, Scope/Plan evidence, and approvals.
4. Inspect the current branch, working tree, worktrees, remote tracking, relevant contracts, verification evidence, preview revision, and active Codex chats.
5. Reconcile contradictions before modifying product code.
6. State the work tier, Linear issue/milestone, current stage, branch, blocker, next action, and next Baah approval gate.
7. Invoke the Superpowers process skill required by the Taisa orchestrator.

Read-only questions require orientation but do not create branches or workflow artifacts.

Bias toward activation: when a request is ambiguous but plausibly asks for a Taisa change,
investigation, design, process improvement, or delivery action, run lightweight workflow
orientation and infer the lightest fitting tier. Missing workflow keywords never turns an
actionable request into a future-only direction. Every actionable task requires a
non-duplicate Linear issue before work; activation does not bypass approval gates.

## Authority and gates

Linear is the sole live authority. It owns roadmap, task intake, priority, ownership, stage,
dependencies, blockers, Scope, Plan, acceptance, discussion, and gate evidence.
`docs/workflow.md` and the Taisa orchestrator define how work is performed; Git owns
versioned technical truth. Baah approves Scope, Plan, physical-device judgment, and Ship.
Codex owns routine Linear, Git, GitHub, verification, and code-coupled documentation
housekeeping within those approvals.

If Linear is unavailable, continue only already-approved work supported by trusted recent
Scope/Plan context and Git evidence. Do not start or advance work, change a blocker, or claim
approval until Linear is available and reconciled.

Clear Ship approval authorizes the verified pull-request merge and safe deletion of the merged local and remote work branch. It does not authorize force-pushes, history rewrites, deletion of unmerged work, or removal of unrelated worktrees.

## Safety

Preserve user changes. Never develop directly on `main`. Never delete a branch until its commits are accounted for in canonical `main`. Stop and report dirty worktrees, unique commits, failed checks, conflicts, unexpected pull-request bases, or unverifiable remote state.

## Project constraints

Read `CLAUDE.md` for Taisa product context, architecture constraints, and package commands. Do not duplicate or override those constraints here.
