# Codex + Git Workflow Consolidation Design

**Date:** 2026-08-09

**Status:** Shipped

**Scope:** Repository history repair, branch/merge governance, Codex orchestration, and one build/test/ship path

## Problem

Taisa has a thoughtful product-development workflow, but its operating instructions are split across `CLAUDE.md`, `docs/workflow.md`, and `.claude/skills/taisa-workflow/SKILL.md`. Codex has no repository-level `AGENTS.md` entry point. Git state has also drifted:

- GitHub's default branch points to an unrelated Next.js scaffold branch.
- Local `main` contains the completed persistent-input work and is ahead of `origin/main`.
- `feature/transcription-unification` contains the latest seven commits.
- Completed and obsolete branches have not been reconciled or cleaned up.

The result should be one understandable workflow that Codex applies automatically, with Baah approving product gates while Codex owns routine Git and project housekeeping.

## Goals

1. Establish `main` as the sole permanent and default branch locally and on GitHub.
2. Preserve all valid Taisa work by integrating the transcription-unification branch before cleanup.
3. Remove obsolete local and remote branches only after proving their work is merged, superseded, or unrelated.
4. Make Codex automatically load and follow the Taisa workflow through a root `AGENTS.md`.
5. Use Superpowers skills as the execution machinery inside Taisa's existing stages and approval gates.
6. Define one standard path for branching, building, testing, reviewing, merging, and cleanup.
7. Make the Ship gate authorize the normal GitHub merge and post-merge branch cleanup without repeated user prompts.

## Non-goals

- Rewriting valid Taisa commit history.
- Introducing a long-lived `develop`, release, platform, or product branch.
- Changing Taisa's product stages, design-system rules, or Baah's approval authority.
- Automatically deleting unmerged work.
- Force-pushing or rebasing shared branches without separate explicit approval.
- Requiring every Quick task to create unnecessary planning artifacts.

## Sources of truth

Each workflow file has one responsibility:

| File | Responsibility |
|---|---|
| `AGENTS.md` | Automatic Codex entry point: mandatory startup checks, instruction routing, safety boundaries, and skill invocation |
| `.claude/skills/taisa-workflow/SKILL.md` | Operational orchestrator: stage detection, gates, autonomous actions, Superpowers mapping, Git lifecycle, and failure handling |
| `docs/workflow.md` | Human-readable source of truth: stages, responsibilities, branch policy, merge policy, verification matrix, and Active Work |
| `CLAUDE.md` | Product and architecture context plus a pointer to the shared workflow; no independent competing workflow rules |

Rules must not be copied in full into every file. `AGENTS.md` loads the orchestrator; the orchestrator applies `docs/workflow.md`; `CLAUDE.md` points other agents to the same system.

## Canonical Git model

### Permanent branch

`main` is the only permanent branch. It must be the GitHub default, the base for pull requests, and the branch that local workspaces return to after shipping.

There is no long-lived `develop` branch. Platform and Product remain workflow tracks, not Git branches.

### Branch naming

All work branches use lowercase kebab case:

```text
<type>/<short-kebab-case-description>
```

Allowed types:

| Prefix | Use |
|---|---|
| `feature/` | New user-facing capability |
| `fix/` | Defect correction |
| `chore/` | Tooling, dependencies, configuration, and maintenance |
| `docs/` | Documentation-only changes |
| `refactor/` | Internal restructuring with no intended behavior change |
| `test/` | Test-only work |
| `spike/` | Disposable investigation; never merged directly without promotion |

Examples: `feature/senior-self-modes`, `fix/recording-interruption`, and `chore/codex-workflow`.

Branch names must describe one deliverable. They must not use agent or person namespaces such as `claude/` or `codex/`, generic labels such as `feature/update`, issue-free nesting such as `feature/mobile/chat/input`, or multiple unrelated scopes.

### Branch creation

Before creating a branch, Codex:

1. Confirms the current working tree and worktree ownership.
2. Fetches and prunes remote references.
3. Updates local `main` using fast-forward only.
4. Creates the typed work branch from current `main`.
5. Records the branch in Active Work for Standard and Full features.

Codex does not start feature development directly on `main`.

### Commit convention

Commits use Conventional Commit-style prefixes already familiar to the project:

- `feat:` and `feat(ds):`
- `fix:` and `fix(ds):`
- `test:`
- `docs:`
- `refactor:`
- `chore:`

Each commit should represent one coherent change. Work-in-progress commits are allowed on the feature branch because the standard integration strategy is squash merge.

## Taisa stages powered by Superpowers

The Taisa workflow remains the controlling product process. Superpowers supplies the method used within each stage.

| Taisa event or stage | Required behavior |
|---|---|
| Every scoped work request | Load `taisa-workflow`, reconcile Git/docs/Active Work, classify Quick/Standard/Full |
| New behavior or workflow design | `superpowers:brainstorming` |
| Approved multi-step specification | `superpowers:writing-plans` |
| Bug or unexpected behavior | `superpowers:systematic-debugging` before proposing fixes |
| Feature or bug implementation | `superpowers:test-driven-development` where executable tests are practical |
| Approved plan execution | `superpowers:executing-plans`; use subagents only when explicitly authorized and tasks are independent |
| Build completion | `superpowers:requesting-code-review` |
| Any completion or ship claim | `superpowers:verification-before-completion` |
| Ship/integration | `superpowers:finishing-a-development-branch` plus the Taisa Ship automation |

Taisa's Scope, Design, Plan, Build, Review, and QA gates remain authoritative. A Superpowers skill cannot bypass a Baah approval gate or expand the approved scope.

## Verification model

Verification is proportional during implementation and comprehensive at Ship.

### During Build

- Run the narrowest relevant test or check after each coherent change.
- Prefer tests first for behavior changes and regressions.
- Type-check the affected package before considering a plan task complete.
- Run design-system compliance checks whenever Product UI changes.

### Required before pull request or Ship

Codex derives exact commands from package scripts and the affected files, then records commands and results. The default matrix is:

| Change area | Required automated checks |
|---|---|
| Backend | Backend tests and TypeScript build |
| Shared types | Shared type-check/build plus affected backend tests |
| Mobile logic | Mobile TypeScript check plus relevant tests where present |
| Mobile UI | Mobile TypeScript check, DS compliance review, and Storybook/component checks where applicable |
| Cross-stack | Backend tests/build, shared checks, and mobile TypeScript check |
| Docs/workflow only | Link/path consistency, instruction consistency, and clean diff checks |

Mobile-facing changes also require Baah's device QA before Ship unless explicitly classified as non-visual and non-device-sensitive. Missing test infrastructure is reported as a gap; it is not silently treated as a passing test.

## Pull request and merge policy

### Standard integration

- All non-emergency work reaches `main` through a pull request.
- The PR targets `main`, links its scope/spec/plan where applicable, lists acceptance criteria, and includes verification evidence.
- Codex reviews the diff and resolves blocking findings before requesting Ship approval.
- The standard merge method is **squash merge**.
- The squash commit title follows the repository commit convention.
- Merge commits and rebase merges are exceptions requiring a stated reason.
- Direct pushes to `main`, force-pushes, and history rewrites are prohibited unless Baah separately and explicitly authorizes an emergency operation.

## Ship gate and autonomous Git housekeeping

Baah retains one explicit Ship gate. Clear approval intent such as “ship it” or “merge it” authorizes the complete normal integration transaction:

1. Confirm the feature branch and worktree are clean.
2. Fetch the remote and confirm the branch is current with `origin/main` or safely reconcile it.
3. Run the complete verification matrix.
4. Run final code review and confirm there are no blocking findings.
5. Confirm required device QA has passed.
6. Push the feature branch.
7. Create or update its pull request.
8. Squash-merge the PR into `main`.
9. Update local `main` by fast-forwarding to `origin/main`.
10. Verify local `main`, remote `main`, the PR, and the merge SHA agree.
11. Delete the merged remote feature branch.
12. Delete the merged local feature branch from a different checked-out branch/worktree.
13. Prune stale remote references and remove disposable worktrees when safe.
14. Update Active Work, roadmap/plan status, and Linear with the merge SHA.
15. Report the verification evidence and final branch state.

The Ship approval covers steps 1–15 without additional confirmation prompts.

### Safety boundaries

Codex must stop cleanup and report the exact blocker when:

- The branch contains unique commits not represented by the PR or merged `main`.
- The working tree is dirty or files would be overwritten.
- Verification, review, or required QA fails.
- The branch is checked out in another active worktree that cannot be safely removed.
- The PR merged to an unexpected base or produced an unverifiable result.
- GitHub access or network operations fail.

Codex never automatically deletes an unmerged branch. It never force-deletes a branch merely because its name looks obsolete. Force-pushes, destructive history rewrites, and deletion of branches with unique work require a new explicit approval identifying the exact target.

`spike/` branches are either promoted into a properly named implementation branch or explicitly deleted; they are not merged directly.

## One-time repository reconciliation

The initial repair will be performed as a controlled migration:

1. Snapshot local/remote refs and working-tree/worktree state.
2. Verify `feature/transcription-unification` descends from the valid Taisa history.
3. Run the repository's applicable automated checks on that branch.
4. Integrate the seven transcription-unification commits into canonical `main` using the safest non-rewriting path for the existing local history.
5. Push canonical `main` to GitHub.
6. Change GitHub's default branch to `main` and verify it through GitHub.
7. Compare every remaining local and remote branch against canonical `main`.
8. Delete branches proven merged, superseded, or unrelated and explicitly approved for removal, including the unrelated Next.js scaffold branch.
9. Preserve any branch with unaccounted-for unique work and report it instead of deleting it.
10. Prune refs, switch the primary workspace to `main`, and verify local/GitHub consistency.

This migration may preserve detailed existing commits on `main`; squash merge is the standard for future PRs, not a reason to rewrite already-valid shared history.

## Codex startup behavior

The root `AGENTS.md` makes the workflow automatic for Codex. At the start of an in-scope task, Codex must:

1. Read `docs/workflow.md` and `.claude/skills/taisa-workflow/SKILL.md` completely.
2. Inspect the current branch, working tree, worktrees, remote tracking, scope docs, plans, and Active Work.
3. Reconcile contradictions before modifying product code.
4. State the work tier, current stage, branch, and next approval gate.
5. Invoke the required Superpowers process skill for the task type.
6. Preserve user changes and avoid unrelated edits.

Read-only questions may be answered after orientation without creating branches or workflow artifacts. New builds, fixes, and workflow changes follow the full routing above.

## Failure handling

- Git or GitHub failure: stop at the last verified safe state, do not guess, and list the exact unfinished actions.
- Test failure: remain in Build, diagnose systematically, and do not create or merge the PR.
- Device QA failure: record QA notes, return Active Work to Build, fix, and repeat verification.
- Linear failure: retry once, log the failed update, and continue only when it does not affect code or Git safety.
- Documentation disagreement: `docs/workflow.md` governs human process, while higher-priority repository/platform instructions still apply; reconcile duplicated text rather than allowing silent divergence.

## Acceptance criteria

- [ ] GitHub and local Git identify `main` as the canonical/default branch.
- [ ] Canonical `main` includes persistent-input work and transcription unification.
- [ ] The unrelated scaffold branch is removed after verification.
- [ ] Completed branches are deleted locally and remotely only after their work is accounted for.
- [ ] A root `AGENTS.md` automatically routes Codex through the Taisa orchestrator.
- [ ] Taisa stages map explicitly to the relevant Superpowers skills.
- [ ] Branch types, naming, creation, and lifecycle are documented consistently.
- [ ] “Ship” authorizes PR merge and safe local/remote branch cleanup as one transaction.
- [ ] Squash merge is the default future integration strategy.
- [ ] Build, test, review, device-QA, and merge gates form one non-contradictory path.
- [ ] `AGENTS.md`, `CLAUDE.md`, the orchestrator skill, and `docs/workflow.md` contain no competing workflow rules.
- [ ] Final verification records the canonical SHA and shows a clean primary workspace on `main`.
