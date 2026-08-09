# Rename Project to Taisa — Design Spec

**Date:** 2026-08-09

**Status:** Shipped

## Problem

GitHub now identifies the repository as `EmmanuelBaah27/taisa`, while the local checkout, Git remote, and several documentation examples still use `taisa-os`. The checkout is also nested inside an obsolete `Taisa-OS` wrapper directory that contains unrelated npm files and legacy Claude settings.

## Decision

Use **Taisa** as the single project identity and consolidate the actual Git repository into one local folder:

```text
/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa
```

The final Git remote is:

```text
https://github.com/EmmanuelBaah27/taisa.git
```

There will be no nested `Taisa/taisa` or retained `Taisa-OS/taisa-os` structure.

## Naming boundaries

Rename literal repository and filesystem identities:

- `taisa-os` → `taisa`
- `Taisa-OS` → `Taisa`
- `EmmanuelBaah27/taisa-os` → `EmmanuelBaah27/taisa`

Keep identifiers that already express the correct product identity:

- npm workspace packages `@taisa/backend` and `@taisa/shared`
- TypeScript imports under `@taisa/*`
- iOS bundle identifier and Android package `com.taisa.app`
- app/product display name `Taisa`

These identifiers are stable package/application namespaces, not stale repository names.

## Repository content changes

Update `taisa-os` references in tracked project files where they describe the repository name, a working-directory command, a tree diagram, or a GitHub repository target. This includes active documentation and historical plan/spec examples because copied commands should still work.

Do not edit Git internals by search-and-replace. Update `origin` using Git commands and repair linked-worktree metadata using `git worktree repair` after the primary checkout moves.

Add the new canonical repository slug and local-folder expectation to the workflow consistency check so future drift is detected.

## Local filesystem migration

The outer `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa-OS` folder is not a Git repository. Its unique contents are obsolete:

- wrapper `package.json`, `package-lock.json`, and `node_modules`
- `.DS_Store`
- `.claude/launch.json` referencing an old `beats-os` checkout
- `.claude/settings.local.json` containing historical local command permissions

Move the actual inner repository directly to `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa`. Preserve the obsolete wrapper in a recoverable temporary archive until the moved repository, its linked worktree, and all checks pass. Remove that archive only after verification.

## Linked worktree handling

The `design-system` branch is checked out at:

```text
/Users/emmanuelbaah/.superconductor/worktrees/taisa-os/sc-paired-fluxon-f3db
```

It contains uncommitted package changes and must not be modified, reset, deleted, or renamed as part of this migration. After moving the primary repository, run Git's worktree repair mechanism so the linked worktree points to the new common Git directory. Verify its branch and dirty status are identical before and after repair.

The external worktree path may retain `taisa-os` because it is owned by Superconductor; that filesystem label is not the project checkout or repository identity.

## Git workflow

Implementation occurs on `chore/rename-project-taisa`, created from current `main`.

Before Ship:

1. Change tracked project references and workflow verification.
2. Update `origin` to the renamed GitHub URL and verify fetch/push endpoints.
3. Move and consolidate the primary checkout.
4. Repair and verify linked-worktree metadata.
5. Run all applicable verification from the new path.
6. Push the work branch, create a PR targeting `main`, and squash-merge after the already-established Ship gate.
7. Synchronize local `main`, delete the merged local/remote work branch, and prune refs.

## Verification

- `npm run verify:workflow`
- `npm test --workspace=backend -- --runInBand`
- `npm run build --workspace=backend`
- `cd mobile && npx tsc --noEmit`
- `git diff --check`
- a tracked-file scan finds no stale repository/path references outside this migration spec and its implementation plan, which retain the former names as historical evidence
- `git remote -v` reports only `https://github.com/EmmanuelBaah27/taisa.git`
- GitHub reports `EmmanuelBaah27/taisa` with default branch `main`
- primary checkout path is `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa`
- local `main` equals `origin/main` after Ship
- the external `design-system` worktree remains registered, on the same SHA, with the same dirty files
- the obsolete wrapper archive is removed only after all prior checks pass

## Failure handling

- If the target folder already exists, stop before moving anything.
- If the wrapper contains unexpected unique files, preserve and report them.
- If worktree repair fails, keep the wrapper/archive and repository data intact; do not delete anything.
- If tests or type-checking fail, do not open or merge the PR.
- If GitHub resolves to an unexpected repository or default branch, stop before pushing.
- Never edit, reset, clean, or delete the dirty `design-system` worktree.

## Acceptance criteria

- [ ] GitHub, Git remote, active project references, and the primary local folder consistently use `taisa`/`Taisa`; only the migration spec/plan may retain former names as historical evidence.
- [ ] The primary repository exists at one level: `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa`.
- [ ] No obsolete wrapper or nested repository remains after successful verification.
- [ ] Existing `@taisa/*` and `com.taisa.app` identifiers remain unchanged.
- [ ] Workflow verification prevents the old repository slug from returning.
- [ ] Backend tests/build and mobile TypeScript checks pass.
- [ ] The dirty external `design-system` worktree remains intact and functional.
- [ ] The change ships through PR, squash merge, synchronization, and safe branch cleanup.
