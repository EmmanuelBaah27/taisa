# Taisa Project Memory System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every future Taisa session a repository-native context entry point, durable decision and learning records, and a consistent closeout/promotion workflow.

**Architecture:** Add a small documentation hierarchy rather than a database or transcript store: `docs/project-memory.md` routes agents to authoritative sources, `docs/decisions/` retains consequential reasoning, and `docs/learnings.md` retains evidence-backed reusable findings. Wire those artifacts into the existing startup, Review, and Ship rules, then make the workflow verifier enforce the contract.

**Tech Stack:** Markdown, Bash, Git, ripgrep

**Spec:** `docs/superpowers/specs/2026-08-19-project-memory-system-design.md`

**Status:** Awaiting Baah plan approval

## Global Constraints

- Keep canonical technical documents authoritative for current behavior.
- Do not store chat transcripts, chain-of-thought, or unsupported historical claims.
- Do not add a database, external knowledge service, dependency, or product-code change.
- Treat learnings as advisory until promoted into a workflow rule, decision record, test, or canonical document.
- Preserve decision history: supersede records with links instead of rewriting or renumbering them.
- Require Baah approval for decisions that change product scope, architecture invariants, or breaking shared contracts.
- Keep the memory index navigational; link to sources instead of duplicating their contents.

---

### Task 1: Create the durable memory artifacts

**Files:**
- Create: `docs/project-memory.md`
- Create: `docs/decisions/README.md`
- Create: `docs/decisions/0001-use-repository-native-project-memory.md`
- Create: `docs/learnings.md`

**Interfaces:**
- Consumes: the source hierarchy and governance rules in the approved spec.
- Produces: the project-memory entry point, decision-record convention and first accepted decision, plus the append-only learning-log contract.

- [ ] **Step 1: Create the project-memory index**

Write `docs/project-memory.md` with these ordered sections: `Purpose`, `Authority order`, `Start here`, `Decisions`, `Reusable learnings`, and `Work history`. Link the operating files, canonical domain documents, `docs/decisions/README.md`, `docs/learnings.md`, `docs/features/`, and `docs/superpowers/plans/`. State explicitly that canonical domain docs describe present behavior, accepted decisions explain why, and learnings are advisory until promoted.

- [ ] **Step 2: Create the decision-record convention and template**

Write `docs/decisions/README.md` with the filename pattern `NNNN-short-kebab-title.md`, monotonic numbering, statuses `Proposed`, `Accepted`, `Superseded`, and `Rejected`, approval rules, supersession behavior, and this exact template structure:

```markdown
# NNNN: Decision title

**Status:** Proposed
**Date:** YYYY-MM-DD
**Owners:** Baah + the agent

## Context
## Decision drivers
## Considered options
## Decision
## Consequences
## Follow-ups
## References
```

- [ ] **Step 3: Record the approved repository-native memory decision**

Create `docs/decisions/0001-use-repository-native-project-memory.md` with status `Accepted`, date `2026-08-20`, and owners `Baah + the agent`. Contrast repository-native layered memory with chat-history dependence and an external knowledge service; record discoverability, reviewability, offline availability, and canonical-document authority as the drivers. Link the approved spec as evidence.

- [ ] **Step 4: Create the reusable learning log**

Write `docs/learnings.md` with the stable areas `Product`, `Platform`, `Mobile`, `Backend`, `Design System`, `AI`, `QA`, and `Workflow`; inclusion/exclusion guidance; correction-by-append rules; and an empty table:

```markdown
| Date | Area | Learning | Evidence | Promoted to |
|---|---|---|---|---|
```

Do not invent or backfill historical learnings.

- [ ] **Step 5: Verify the artifact structure**

Run:

```bash
test -f docs/project-memory.md
test -f docs/decisions/README.md
test -f docs/decisions/0001-use-repository-native-project-memory.md
test -f docs/learnings.md
rg -n '^\*\*Status:\*\* Accepted$' docs/decisions/0001-use-repository-native-project-memory.md
git diff --check
```

Expected: every command exits 0; the accepted status appears once; no whitespace errors are reported.

- [ ] **Step 6: Commit the memory artifacts**

```bash
git add docs/project-memory.md docs/decisions/README.md docs/decisions/0001-use-repository-native-project-memory.md docs/learnings.md
git commit -m "docs: establish durable project memory"
```

---

### Task 2: Integrate memory into session startup and feature closeout

**Files:**
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/workflow.md`
- Modify: `.claude/skills/taisa-workflow/SKILL.md`

**Interfaces:**
- Consumes: `docs/project-memory.md`, `docs/decisions/`, and `docs/learnings.md` from Task 1.
- Produces: aligned startup, promotion, Review, and Ship rules for all future scoped work.

- [ ] **Step 1: Add the deterministic startup route**

Update `AGENTS.md`, `CLAUDE.md`, `docs/workflow.md`, and the orchestrator so scoped work reads `docs/project-memory.md` after the existing operating instructions, then checks only the relevant accepted decisions and learnings. Preserve the existing Git/worktree reconciliation and approval-gate rules.

- [ ] **Step 2: Add the memory-promotion rule**

Document the same classification in `docs/workflow.md` and the orchestrator:

```text
Feature-specific context -> scope, plan, QA note, or PR
Reusable evidence -> docs/learnings.md
Accepted cross-cutting choice -> docs/decisions/
Current-behavior change -> canonical domain document
```

State that conversational BTS can be skipped while the Review/Ship promotion check remains mandatory.

- [ ] **Step 3: Add Standard and Full closeout requirements**

Require a `Closeout` section during Review with `Actual outcome`, `Plan deviations`, `Learnings and decisions`, `Remaining debt`, `Canonical docs updated`, and `PR and merge evidence`. State that Quick work records material closeout in its PR or final commit and that closeout adds no approval gate.

- [ ] **Step 4: Extend document conventions and ownership**

Add the memory index, decision records, learning log, and closeout ownership to `docs/workflow.md`. State that the agent maintains links and promotion housekeeping within existing Scope, Plan, and Ship approvals.

- [ ] **Step 5: Check the four instruction surfaces for agreement**

Run:

```bash
rg -n 'docs/project-memory\.md' AGENTS.md CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md
rg -n 'Closeout|memory-promotion|promotion check' docs/workflow.md .claude/skills/taisa-workflow/SKILL.md
git diff --check
```

Expected: all four startup surfaces reference the index; both workflow surfaces contain promotion and closeout rules; no whitespace errors are reported.

- [ ] **Step 6: Commit the workflow integration**

```bash
git add AGENTS.md CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md
git commit -m "docs: integrate memory into Taisa workflow"
```

---

### Task 3: Enforce and verify the memory contract

**Files:**
- Modify: `scripts/verify-workflow.sh`
- Modify: `docs/superpowers/plans/2026-08-20-project-memory-system.md`
- Modify: `docs/workflow.md`

**Interfaces:**
- Consumes: the artifacts and workflow rules from Tasks 1 and 2.
- Produces: automated structural checks, Review-ready status, and closeout evidence for this feature.

- [ ] **Step 1: Add structural assertions to the workflow verifier**

Extend `scripts/verify-workflow.sh` to fail when any memory artifact is missing, the startup surfaces omit `docs/project-memory.md`, decision `0001` is not accepted, the learning table header is absent, or workflow/orchestrator closeout rules disappear. Use `test -f` and `rg -q`; do not add dependencies.

- [ ] **Step 2: Add a Markdown link verifier**

Add a Bash function to `scripts/verify-workflow.sh` that scans local Markdown links in the new memory artifacts, ignores `http://`, `https://`, and anchor-only targets, strips anchors from repository-relative targets, and fails with the source and unresolved target when the resolved path does not exist.

- [ ] **Step 3: Run the focused verifier and contradiction search**

Run:

```bash
bash scripts/verify-workflow.sh
rg -n 'chat transcript|external knowledge|second project-status|second status tracker' AGENTS.md CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md docs/project-memory.md docs/decisions docs/learnings.md
git diff --check
```

Expected: the verifier and diff check exit 0. Search hits, if any, describe explicit non-goals rather than contradictory requirements.

- [ ] **Step 4: Prove the diff is documentation/workflow-only**

Run:

```bash
git diff --name-only main...HEAD
git status --short
```

Expected: only `AGENTS.md`, `CLAUDE.md`, `.claude/skills/taisa-workflow/SKILL.md`, `docs/**`, and `scripts/verify-workflow.sh` appear; no product code, package manifest, lockfile, generated output, or unrelated user file appears.

- [ ] **Step 5: Complete Review closeout and stage the Ship gate**

Set this plan status to `Review — awaiting Ship approval`. Add its `Closeout` section with the actual outcome, deviations, learning/decision links, remaining debt, canonical documents updated, and placeholders limited to `PR URL: pending Ship` and `Merge SHA: pending Ship`. Update the Active Work row to `Review + QA` blocked on `Baah document review and Ship approval`.

- [ ] **Step 6: Commit verification and closeout**

```bash
git add scripts/verify-workflow.sh docs/workflow.md docs/superpowers/plans/2026-08-20-project-memory-system.md
git commit -m "test: verify project memory workflow"
```
