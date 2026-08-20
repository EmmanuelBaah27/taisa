# Taisa Codex Operating Instructions

## Mandatory startup

For every scoped build, fix, plan, review, or ship task:

1. Read `docs/workflow.md` and `.claude/skills/taisa-workflow/SKILL.md` completely.
2. Read `docs/project-memory.md`, then inspect only the accepted decisions, reusable learnings, and canonical domain documents relevant to the task.
3. Inspect the current branch, working tree, worktrees, remote tracking, Active Work, scope docs, and plans.
4. Reconcile contradictions before modifying product code.
5. State the work tier, current stage, branch, and next Baah approval gate.
6. Invoke the Superpowers process skill required by the Taisa orchestrator.

Read-only questions require orientation but do not create branches or workflow artifacts.

## Authority and gates

`docs/workflow.md` is the human-readable process source. The Taisa orchestrator applies it. Baah approves Scope, Plan, and Ship. Codex owns routine status, Git, GitHub, verification, documentation, and Linear housekeeping within those approvals.

Clear Ship approval authorizes the verified pull-request merge and safe deletion of the merged local and remote work branch. It does not authorize force-pushes, history rewrites, deletion of unmerged work, or removal of unrelated worktrees.

## Safety

Preserve user changes. Never develop directly on `main`. Never delete a branch until its commits are accounted for in canonical `main`. Stop and report dirty worktrees, unique commits, failed checks, conflicts, unexpected pull-request bases, or unverifiable remote state.

## Project constraints

Read `CLAUDE.md` for Taisa product context, architecture constraints, and package commands. Do not duplicate or override those constraints here.
