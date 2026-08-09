# Rename Project to Taisa Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align GitHub, Git, tracked project references, and the primary local checkout on the single project identity `Taisa`/`taisa`.

**Architecture:** Update tracked identity references and the workflow drift check before moving the checkout. Then move the actual Git repository out of its obsolete wrapper into `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa`, repair the externally owned linked worktree, and ship through the standard PR/squash/cleanup transaction.

**Tech Stack:** Git, GitHub CLI, Bash workflow verification, npm workspaces, Jest, TypeScript, Expo

## Global Constraints

- Final repository URL: `https://github.com/EmmanuelBaah27/taisa.git`.
- Final primary path: `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa`.
- Do not create a nested `Taisa/taisa` structure.
- Preserve `@taisa/backend`, `@taisa/shared`, TypeScript `@taisa/*` imports, and `com.taisa.app` unchanged.
- Never modify, reset, clean, rename, or delete the external `design-system` worktree.
- Preserve the obsolete wrapper recoverably until the moved repository and linked worktree pass verification.
- Do not edit `.git` internals directly; use `git remote set-url` and `git worktree repair`.
- Former names may remain only in this migration spec and plan as historical evidence.
- Do not merge or clean the work branch until all checks pass.

---

### Task 1: Add rename drift detection and update active project references

**Files:**
- Modify: `scripts/verify-workflow.sh`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/superpowers/specs/2026-04-15-taisa-documentation-design.md`
- Modify: `docs/superpowers/plans/2026-04-15-taisa-documentation.md`
- Modify: `docs/superpowers/specs/2026-05-23-navii-avatar-design.md`
- Modify: `docs/superpowers/plans/2026-05-23-navii-avatar.md`
- Modify: `docs/superpowers/plans/2026-05-14-taisa-workflow-system.md`
- Modify: `docs/superpowers/plans/2026-08-09-codex-git-workflow-consolidation.md`

**Interfaces:**
- Consumes: canonical `taisa` repository identity
- Produces: executable docs and a check that rejects stale repository/path identities

- [ ] **Step 1: Extend the failing workflow check**

Add assertions to `scripts/verify-workflow.sh` that:

```bash
test "$(git remote get-url origin)" = "https://github.com/EmmanuelBaah27/taisa.git" || fail "origin does not use the canonical Taisa URL"
```

and scan tracked text files other than the current migration spec/plan:

```bash
stale_refs="$({ git grep -n -I -e 'taisa-os' -e 'Taisa-OS' -e 'EmmanuelBaah27/taisa-os' -- . \
  ':!docs/superpowers/specs/2026-08-09-rename-project-taisa-design.md' \
  ':!docs/superpowers/plans/2026-08-09-rename-project-taisa.md' || true; })"
test -z "$stale_refs" || {
  printf '%s\n' "$stale_refs" >&2
  fail "stale Taisa repository references remain"
}
```

- [ ] **Step 2: Run the check and verify RED**

Run: `npm run verify:workflow`

Expected: FAIL because `origin` and tracked documentation still use the former repository identity.

- [ ] **Step 3: Replace tracked repository/path references**

In every tracked text file returned by the stale scan, replace repository/path uses of `taisa-os` with `taisa` and `Taisa-OS` with `Taisa`. Update tree diagrams, `cd` commands, GitHub CLI targets, and descriptive prose. Do not modify:

- `docs/superpowers/specs/2026-08-09-rename-project-taisa-design.md`
- `docs/superpowers/plans/2026-08-09-rename-project-taisa.md`
- `@taisa/*`
- `com.taisa.app`

- [ ] **Step 4: Update the Git remote through Git**

Run:

```bash
git remote set-url origin https://github.com/EmmanuelBaah27/taisa.git
git remote -v
git ls-remote --symref origin HEAD
```

Expected: fetch/push URLs use the canonical URL and remote HEAD is `main`.

- [ ] **Step 5: Run the workflow check and verify GREEN**

Run:

```bash
npm run verify:workflow
git diff --check
```

Expected: both exit 0 and the workflow check prints `Workflow verification passed.`

- [ ] **Step 6: Commit tracked identity changes**

```bash
git add scripts/verify-workflow.sh README.md docs
git commit -m "chore: rename repository references to Taisa"
```

### Task 2: Verify the branch before filesystem migration

**Files:**
- No tracked changes expected

**Interfaces:**
- Consumes: updated work branch at the old local path
- Produces: baseline evidence and exact linked-worktree snapshot for comparison after the move

- [ ] **Step 1: Confirm target and archive paths are unused**

Run explicit checks:

```bash
test ! -e /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa
test ! -e /private/tmp/taisa-obsolete-wrapper-2026-08-09
```

Stop if either path exists.

- [ ] **Step 2: Snapshot the primary and external worktrees**

Run:

```bash
git status --short --branch
git worktree list --porcelain
git -C /Users/emmanuelbaah/.superconductor/worktrees/taisa-os/sc-paired-fluxon-f3db rev-parse HEAD
git -C /Users/emmanuelbaah/.superconductor/worktrees/taisa-os/sc-paired-fluxon-f3db status --porcelain=v1
```

Record the external SHA and exact dirty-file list. Expected dirty files: root/backend/mobile package manifests plus a root lockfile; do not assume if output differs.

- [ ] **Step 3: Run full automated checks before moving**

```bash
npm run verify:workflow
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
(cd mobile && npx tsc --noEmit)
git diff --check
git status --short --branch
```

Expected: all checks pass and the primary branch is clean.

### Task 3: Consolidate the checkout into one Taisa folder

**Files:**
- Move directory: `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa-OS/taisa-os` → `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa`
- Archive directory: remaining `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa-OS` → `/private/tmp/taisa-obsolete-wrapper-2026-08-09`

**Interfaces:**
- Consumes: clean verified primary checkout and wrapper inventory
- Produces: one primary repository directory and a recoverable wrapper archive

- [ ] **Step 1: Reconfirm exact source and target identities**

From the repository, run:

```bash
test "$(git rev-parse --show-toplevel)" = "/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa-OS/taisa-os"
test ! -e /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa
```

- [ ] **Step 2: Move the actual repository to the canonical path**

From `/Users/emmanuelbaah/Documents/Beats/VibeCoding`, run:

```bash
mv /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa-OS/taisa-os /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa
```

Do not move individual tracked files; move the repository directory atomically.

- [ ] **Step 3: Archive the obsolete wrapper recoverably**

After confirming `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa/.git` exists, run:

```bash
mv /Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa-OS /private/tmp/taisa-obsolete-wrapper-2026-08-09
```

The archive remains until final verification completes.

- [ ] **Step 4: Repair linked-worktree metadata**

From `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa`, run:

```bash
git worktree repair /Users/emmanuelbaah/.superconductor/worktrees/taisa-os/sc-paired-fluxon-f3db
git worktree list --porcelain
```

Expected: both primary and external worktrees resolve through the moved common Git directory.

- [ ] **Step 5: Compare the external worktree snapshot**

Run the same SHA and porcelain-status commands from Task 2. They must match byte-for-byte. If they differ, stop and preserve the wrapper archive.

### Task 4: Verify and ship through the standard workflow

**Files:**
- Modify: `docs/superpowers/specs/2026-08-09-rename-project-taisa-design.md`
- Modify: `docs/superpowers/plans/2026-08-09-rename-project-taisa.md`

**Interfaces:**
- Consumes: moved verified work branch
- Produces: squash-merged canonical `main`, cleaned work branch, and shipped migration artifacts

- [ ] **Step 1: Verify from the canonical path**

From `/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa`, run:

```bash
test "$(git rev-parse --show-toplevel)" = "/Users/emmanuelbaah/Documents/Beats/VibeCoding/Taisa"
npm run verify:workflow
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
(cd mobile && npx tsc --noEmit)
git diff --check
git status --short --branch
git remote -v
gh repo view EmmanuelBaah27/taisa --json nameWithOwner,defaultBranchRef,url
```

- [ ] **Step 2: Review the complete branch diff**

Inspect `origin/main...HEAD` for unintended identifier changes. Confirm `@taisa/*`, `com.taisa.app`, and the external worktree files are unchanged.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin chore/rename-project-taisa
gh pr create --base main --head chore/rename-project-taisa \
  --title "chore: rename repository identity to Taisa" \
  --body "Aligns repository references, Git remote expectations, and the local checkout on Taisa. Verification: workflow check, 45 backend tests, backend build, mobile TypeScript."
```

- [ ] **Step 4: Squash-merge and clean the remote branch**

After final verification and Ship authorization:

```bash
gh pr merge --squash --delete-branch
git fetch --prune origin
git switch main
git pull --ff-only origin main
```

- [ ] **Step 5: Delete the squash-merged local branch safely**

Because squash merge does not make the work-branch tip an ancestor of `main`, first verify the PR is merged, its base is `main`, its head is `chore/rename-project-taisa`, its changed-file set matches the reviewed branch, and local `main` equals `origin/main`. Then run `git branch -D chore/rename-project-taisa`; this target-specific cleanup is covered by the approved Ship transaction.

- [ ] **Step 6: Mark migration artifacts shipped**

On a short `docs/complete-rename-taisa` branch, mark spec/plan status `Shipped`, record the merge SHA, push, create a documentation-only PR, squash-merge, synchronize `main`, and delete the completion branch locally/remotely. This keeps the no-direct-development-on-`main` rule intact.

- [ ] **Step 7: Remove the obsolete wrapper archive after final verification**

Confirm all final checks pass and both worktrees match their snapshots. Then remove `/private/tmp/taisa-obsolete-wrapper-2026-08-09` as obsolete wrapper data and report that it is no longer recoverable.

- [ ] **Step 8: Final evidence**

Report the canonical path, GitHub URL/default branch, final `main` SHA, test/build results, stale-reference scan, PRs/merge SHAs, cleaned branches, preserved external-worktree SHA/status, and wrapper removal.
