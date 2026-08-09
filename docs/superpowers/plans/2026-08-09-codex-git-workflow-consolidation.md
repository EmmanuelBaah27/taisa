# Codex + Git Workflow Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `main` the single canonical Taisa branch and install one Codex-loaded Taisa/Superpowers workflow for branch, build, test, review, merge, and cleanup operations.

**Architecture:** A root `AGENTS.md` acts as Codex's automatic entry point, delegates stage orchestration to `.claude/skills/taisa-workflow/SKILL.md`, and treats `docs/workflow.md` as the human-readable process source. Repository repair is performed only after the workflow changes and current transcription work pass verification; every branch is classified against canonical `main` before remote deletion.

**Tech Stack:** Git, GitHub CLI, Codex `AGENTS.md`, Markdown workflow documentation, npm workspaces, Jest, TypeScript, Expo/React Native

## Global Constraints

- `main` is the only permanent branch and the GitHub default.
- Future work uses `<type>/<short-kebab-case-description>` with `feature`, `fix`, `chore`, `docs`, `refactor`, `test`, or `spike`.
- Squash merge is the default future integration strategy.
- Clear Ship approval authorizes PR merge and safe local/remote branch cleanup as one transaction.
- Never delete an unmerged branch or a branch with unaccounted-for unique work.
- Never force-push or rewrite shared history without separate, target-specific approval.
- Preserve the separate `design-system` worktree unless its branch is independently proven disposable and is not checked out.
- Taisa's approval gates remain authoritative; Superpowers skills provide the execution method and cannot bypass a gate.
- Do not claim success without fresh verification output.

---

### Task 1: Establish a reproducible preflight and branch inventory

**Files:**
- Create: `scripts/verify-workflow.sh`
- Modify: `package.json`

**Interfaces:**
- Consumes: repository files, Git refs, and the workflow rules introduced in Tasks 2–4
- Produces: `npm run verify:workflow`, a read-only consistency check used before commits and at final verification

- [ ] **Step 1: Create the failing workflow check**

Create `scripts/verify-workflow.sh` as an executable Bash script with `set -euo pipefail`. It must fail with a clear message unless all of these assertions pass:

```bash
test -f AGENTS.md
test -f docs/workflow.md
test -f .claude/skills/taisa-workflow/SKILL.md
rg -q 'main.*only permanent branch|only permanent branch.*main' docs/workflow.md
rg -q '<type>/<short-kebab-case-description>' docs/workflow.md
rg -q 'squash merge' docs/workflow.md
rg -q 'Ship approval|Ship gate' docs/workflow.md
rg -q 'superpowers:brainstorming' .claude/skills/taisa-workflow/SKILL.md
rg -q 'superpowers:verification-before-completion' .claude/skills/taisa-workflow/SKILL.md
rg -q '\.claude/skills/taisa-workflow/SKILL\.md' AGENTS.md
rg -q 'docs/workflow\.md' AGENTS.md
```

It must also reject competing legacy wording with a final grouped check:

```bash
if rg -n 'One branch per feature: `feature/<name>`' CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md; then
  echo 'Legacy feature-only branch rule remains' >&2
  exit 1
fi
```

End the script with `echo 'Workflow verification passed.'`.

- [ ] **Step 2: Add the verification command**

Add this root script to `package.json` without changing the existing workspace or run scripts:

```json
"verify:workflow": "bash scripts/verify-workflow.sh"
```

- [ ] **Step 3: Run the check and confirm the expected failure**

Run: `npm run verify:workflow`

Expected: FAIL because `AGENTS.md` and the consolidated workflow rules do not exist yet.

- [ ] **Step 4: Capture the Git safety inventory**

Run these read-only commands and retain their output for the migration report:

```bash
git status --short --branch
git worktree list --porcelain
git branch -avv
git log --oneline --decorate --graph --all -30
git for-each-ref --format='%(refname:short) %(objectname)' refs/heads refs/remotes/origin
gh repo view EmmanuelBaah27/taisa-os --json defaultBranchRef,nameWithOwner
```

Expected: clean `feature/transcription-unification`; a separate `design-system` worktree; GitHub default `claude/add-fluid-component-bRluX`.

- [ ] **Step 5: Commit the preflight check**

```bash
git add scripts/verify-workflow.sh package.json
git commit -m "test: add workflow consistency verification"
```

### Task 2: Install the Codex repository hook

**Files:**
- Create: `AGENTS.md`

**Interfaces:**
- Consumes: `docs/workflow.md`, `.claude/skills/taisa-workflow/SKILL.md`, repository Git state
- Produces: automatic repository-level instructions for every Codex task

- [ ] **Step 1: Create `AGENTS.md` with a narrow entry-point contract**

Write the following sections and requirements:

```markdown
# Taisa Codex Operating Instructions

## Mandatory startup

For every scoped build, fix, plan, review, or ship task:
1. Read `docs/workflow.md` and `.claude/skills/taisa-workflow/SKILL.md` completely.
2. Inspect branch, status, worktrees, remote tracking, Active Work, scope docs, and plans.
3. Reconcile contradictions before modifying product code.
4. State tier, stage, branch, and next Baah approval gate.
5. Invoke the Superpowers process skill required by the orchestrator.

Read-only questions require orientation but do not create branches or artifacts.

## Authority and gates

`docs/workflow.md` is the human-readable process source. The Taisa orchestrator applies it. Baah approves Scope, Plan, and Ship. Codex owns routine status, Git, GitHub, verification, documentation, and Linear housekeeping within those approvals.

Clear Ship approval authorizes the verified PR merge and safe deletion of the merged local and remote work branch. It does not authorize force-pushes, history rewrites, deletion of unmerged work, or removal of unrelated worktrees.

## Safety

Preserve user changes. Never develop directly on `main`. Never delete a branch until its commits are accounted for in canonical `main`. Stop and report dirty worktrees, unique commits, failed checks, conflicts, unexpected PR bases, or unverifiable remote state.
```

Add a final `## Project constraints` section that points to `CLAUDE.md` for architecture constraints rather than duplicating them.

- [ ] **Step 2: Run the partial workflow check**

Run: `npm run verify:workflow`

Expected: FAIL on missing consolidated rules in `docs/workflow.md` or the orchestrator, not on missing `AGENTS.md`.

- [ ] **Step 3: Commit the Codex entry point**

```bash
git add AGENTS.md
git commit -m "chore: add Codex workflow entry point"
```

### Task 3: Consolidate the human-readable Git and verification workflow

**Files:**
- Modify: `docs/workflow.md`

**Interfaces:**
- Consumes: approved design spec
- Produces: canonical human-readable branch, verification, PR, Ship, and cleanup policy

- [ ] **Step 1: Replace the current `Git conventions` section**

Replace the feature-only bullets with these subsections:

- **Canonical branch:** `main` is the only permanent branch; Platform and Product are workflow tracks, not Git branches.
- **Branch names:** `<type>/<short-kebab-case-description>` and the exact seven-prefix table from the approved spec.
- **Creation:** clean state → fetch/prune → fast-forward `main` → branch from `main` → update Active Work for Standard/Full work.
- **Commits:** `feat`, `feat(ds)`, `fix`, `fix(ds)`, `test`, `docs`, `refactor`, and `chore`.
- **Pull requests:** target `main`, link artifacts and acceptance criteria, include verification evidence.
- **Merge:** squash merge by default; no direct feature pushes to `main`; exceptions require a stated reason.
- **Cleanup:** delete merged local and remote work branches after SHA verification; preserve unique or dirty work.

- [ ] **Step 2: Add the verification matrix**

Immediately before Review + QA or within it, add the exact matrix from the approved spec:

```text
Backend       → backend Jest + backend TypeScript build
Shared types  → shared type-check/build + affected backend tests
Mobile logic  → mobile TypeScript + relevant available tests
Mobile UI     → mobile TypeScript + DS compliance + relevant Storybook checks + device QA
Cross-stack   → backend tests/build + shared checks + mobile TypeScript
Docs/workflow → path/link consistency + workflow verification + clean diff
```

State explicitly that missing test infrastructure is a reported gap, not a passing test.

- [ ] **Step 3: Add the Ship transaction**

Add the ordered 15-step Ship transaction from the approved spec. State that clear Ship approval covers the GitHub merge and normal local/remote branch cleanup without repeated prompts, but does not cover force operations or deletion of unmerged work.

- [ ] **Step 4: Reconcile Active Work**

Replace stale completed rows with a single entry for this Full Platform workflow migration while it is in Build:

```markdown
| Codex + Git workflow consolidation | Platform | Build | feature/transcription-unification | — |
```

Do not alter product roadmap priorities in this task.

- [ ] **Step 5: Run focused documentation checks**

Run:

```bash
rg -n 'only permanent branch|<type>/<short-kebab-case-description>|squash merge|Ship approval|device QA' docs/workflow.md
git diff --check
```

Expected: every policy appears and `git diff --check` exits 0.

- [ ] **Step 6: Commit the workflow policy**

```bash
git add docs/workflow.md
git commit -m "docs: standardize branch merge and verification workflow"
```

### Task 4: Make the Taisa orchestrator drive Superpowers and Git automation

**Files:**
- Modify: `.claude/skills/taisa-workflow/SKILL.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: canonical policy from `docs/workflow.md`
- Produces: stage-to-skill routing and autonomous Git/GitHub execution rules for Claude-compatible agents

- [ ] **Step 1: Expand session reconciliation**

Replace the feature-only startup command block with checks for:

```bash
git status --short --branch
git worktree list --porcelain
git branch -avv
git fetch --prune origin
ls docs/features/
ls docs/superpowers/plans/
```

Require the agent to read `docs/workflow.md`, state tier/stage/current branch/next gate, and avoid writes until contradictions or dirty state are understood.

- [ ] **Step 2: Add the complete Superpowers routing table**

Add these exact mappings:

```text
new behavior/workflow design → superpowers:brainstorming
approved multi-step spec      → superpowers:writing-plans
bug/unexpected behavior       → superpowers:systematic-debugging
feature or bug implementation → superpowers:test-driven-development where practical
approved plan execution       → superpowers:executing-plans
build complete                → superpowers:requesting-code-review
completion/ship claim         → superpowers:verification-before-completion
integration/cleanup           → superpowers:finishing-a-development-branch
```

State that subagents are used only when the user explicitly authorizes them and the tasks are independent.

- [ ] **Step 3: Replace the orchestrator's Git lifecycle**

Use the canonical typed branch rules, PR evidence, squash merge default, Ship transaction, and safety stop conditions from `docs/workflow.md`. Keep details concise by referencing the canonical section instead of maintaining a second full copy.

- [ ] **Step 4: Remove competing workflow prose from `CLAUDE.md`**

Retain product constraints and replace its workflow section with a pointer requiring agents to load:

```text
1. `docs/workflow.md` — source of truth
2. `.claude/skills/taisa-workflow/SKILL.md` — operational orchestrator
3. `AGENTS.md` — Codex automatic entry point
```

Do not duplicate branch or Ship rules in `CLAUDE.md`.

- [ ] **Step 5: Make the consistency check pass**

Run:

```bash
npm run verify:workflow
git diff --check
```

Expected: `Workflow verification passed.` and both commands exit 0.

- [ ] **Step 6: Commit the orchestration consolidation**

```bash
git add .claude/skills/taisa-workflow/SKILL.md CLAUDE.md
git commit -m "chore: orchestrate Taisa work with Superpowers"
```

### Task 5: Verify the current product branch before integration

**Files:**
- Modify only if a verification failure exposes a real defect; any fix follows systematic debugging and gets its own commit

**Interfaces:**
- Consumes: current `feature/transcription-unification` code and completed workflow configuration
- Produces: fresh automated evidence that the branch is eligible for integration

- [ ] **Step 1: Run workflow and diff verification**

```bash
npm run verify:workflow
git diff --check
git status --short --branch
```

Expected: workflow pass, no whitespace errors, clean branch.

- [ ] **Step 2: Run backend tests**

Run: `npm test --workspace=backend -- --runInBand`

Expected: all Jest suites pass. If not, invoke `superpowers:systematic-debugging`, preserve failure output, and do not proceed.

- [ ] **Step 3: Run backend TypeScript build**

Run: `npm run build --workspace=backend`

Expected: exit 0.

- [ ] **Step 4: Run mobile TypeScript verification**

Run from `mobile/`: `npx tsc --noEmit`

Expected: exit 0. If existing unrelated errors prevent a clean pass, inventory every error and resolve or obtain an explicit exception before Ship.

- [ ] **Step 5: Review the integration diff**

Run:

```bash
git diff --stat origin/main...HEAD
git diff --check origin/main...HEAD
git log --oneline origin/main..HEAD
```

Inspect changes for secrets, generated native artifacts, unintended binary changes, missing documentation, and DS violations. Resolve blocking findings before continuing.

### Task 6: Reconcile canonical `main` and GitHub default branch

**Files:**
- Git refs and GitHub repository settings only

**Interfaces:**
- Consumes: verified feature branch and existing valid local `main`
- Produces: identical canonical `main` locally and on GitHub, with GitHub default set to `main`

- [ ] **Step 1: Fetch without mutating local history**

Run: `git fetch --prune origin`

- [ ] **Step 2: Prove ancestry and expected commits**

Run:

```bash
git merge-base --is-ancestor origin/main main
git merge-base --is-ancestor main feature/transcription-unification
git log --oneline main..feature/transcription-unification
```

Expected: both ancestry checks exit 0; the final log contains the transcription commits plus this approved workflow/spec/plan work and no unrelated history.

- [ ] **Step 3: Fast-forward local `main`**

From `feature/transcription-unification`, run:

```bash
git branch -f main feature/transcription-unification
```

This is allowed only because Step 2 proves a strict fast-forward. Do not use reset or force-push.

- [ ] **Step 4: Push canonical `main` normally**

Run: `git push origin main:main`

Expected: fast-forward update; no `--force`.

- [ ] **Step 5: Set and verify the GitHub default branch**

Run:

```bash
gh repo edit EmmanuelBaah27/taisa-os --default-branch main
gh repo view EmmanuelBaah27/taisa-os --json defaultBranchRef,nameWithOwner
```

Expected: `defaultBranchRef.name` equals `main`.

- [ ] **Step 6: Switch the primary workspace to canonical `main`**

Run: `git switch main`

Expected: clean `main` tracking the pushed canonical history.

### Task 7: Classify and clean obsolete branches safely

**Files:**
- Git refs and GitHub branches only

**Interfaces:**
- Consumes: verified canonical `main`, branch inventory from Task 1, explicit Ship/cleanup approval already granted for this migration
- Produces: only canonical `main` plus any branch that cannot be safely accounted for

- [ ] **Step 1: Generate a post-migration branch classification**

For every local and remote branch other than `main`, record:

```bash
git merge-base --is-ancestor <branch> main
git log --oneline main..<branch>
git log --oneline <branch>..main | head -20
```

Classify each as `merged`, `superseded`, `unrelated-approved`, or `preserve-unique`.

- [ ] **Step 2: Handle the checked-out `design-system` worktree**

Do not delete its branch or worktree while checked out. If its commit is not in canonical Taisa history or contains unique work, classify it `preserve-unique` and report it. Removal requires a separate exact-target decision because another tool owns that worktree.

- [ ] **Step 3: Delete merged local branches safely**

Use `git branch -d <branch>` only for branches whose tips are ancestors of `main` and that are not checked out in any worktree.

Expected targets, subject to the classification check: `feature/transcription-unification` and other completed local feature branches.

- [ ] **Step 4: Delete verified obsolete remote branches**

After confirming GitHub default is `main`, use:

```bash
git push origin --delete feature/persistent-input-bar
git push origin --delete feature/light-design-system
git push origin --delete claude/add-fluid-component-bRluX
```

Run each command only if its classification is `merged`, `superseded`, or the explicitly approved `unrelated-approved` scaffold. If any branch has unaccounted-for unique Taisa work, preserve it and report the commits.

- [ ] **Step 5: Prune and verify refs**

Run:

```bash
git fetch --prune origin
git branch -avv
git remote show origin
```

Expected: `origin/HEAD -> origin/main`; no deleted remote refs remain.

### Task 8: Complete final verification and close workflow state

**Files:**
- Modify: `docs/workflow.md`
- Modify: `docs/superpowers/specs/2026-08-09-codex-git-workflow-consolidation-design.md`
- Modify: `docs/superpowers/plans/2026-08-09-codex-git-workflow-consolidation.md`

**Interfaces:**
- Consumes: completed repository migration and canonical merge SHA
- Produces: shipped documentation state and evidence-backed handoff

- [ ] **Step 1: Update artifact status**

Mark the design spec and plan `Shipped`, remove the workflow migration row from Active Work, and record the canonical `main` SHA in the plan's completion note.

- [ ] **Step 2: Commit the status update on `main`**

```bash
git add docs/workflow.md docs/superpowers/specs/2026-08-09-codex-git-workflow-consolidation-design.md docs/superpowers/plans/2026-08-09-codex-git-workflow-consolidation.md
git commit -m "docs: mark workflow consolidation shipped"
git push origin main
```

This direct documentation push is part of the already-approved one-time migration. Future workflow changes use a typed branch and PR.

- [ ] **Step 3: Re-run all final checks from canonical `main`**

```bash
npm run verify:workflow
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
(cd mobile && npx tsc --noEmit)
git diff --check
git status --short --branch
```

Expected: all commands pass and the working tree is clean.

- [ ] **Step 4: Verify local and GitHub consistency**

```bash
git fetch --prune origin
test "$(git rev-parse main)" = "$(git rev-parse origin/main)"
gh repo view EmmanuelBaah27/taisa-os --json defaultBranchRef,nameWithOwner
git remote show origin
git branch -avv
```

Expected: local `main` equals `origin/main`; GitHub and `origin/HEAD` both identify `main`; only intentionally preserved branches remain.

- [ ] **Step 5: Report completion evidence**

Report:

- canonical `main` SHA;
- GitHub default branch;
- tests/build/type-check results;
- local and remote branches deleted;
- branches preserved and why;
- whether the separate `design-system` worktree remains;
- paths to `AGENTS.md`, `docs/workflow.md`, the orchestrator, spec, and plan.

