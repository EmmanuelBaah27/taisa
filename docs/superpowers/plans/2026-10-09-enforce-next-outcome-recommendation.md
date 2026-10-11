# Enforce Next-Outcome Recommendation Implementation Plan

**Status:** Implemented
**Last updated:** 2026-10-09

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Ship closeout publish exactly one evidence-based next-outcome recommendation, or an explicit no-recommendation result, without starting successor work before Baah approval.

**Architecture:** Strengthen the same invariant across the human workflow, executable orchestrator, and bounded Goal template. Extend the offline workflow verifier so removal of the required output shape, evidence inputs, or approval boundary fails CI.

**Tech Stack:** Markdown process contracts, Bash verifier, ripgrep assertions.

**Spec:** `docs/superpowers/specs/2026-10-08-bounded-autonomous-delivery-design.md`

## Global Constraints

- Linear remains the sole live authority for priority, blockers, dependencies, approval readiness, and gate evidence.
- Exactly one recommendation is emitted at Ship closeout.
- When no safe candidate exists, emit `No next outcome recommended` and the blocking reason.
- A recommendation never authorizes reopening, starting, advancing, branching, creating a Goal for, or otherwise executing successor work.
- Baah must explicitly approve the successor kickoff.
- No product UI or application code changes.

## Review Focus

- Multiple high-priority candidates: choose exactly one from current evidence, not a list.
- No safely actionable candidate: use the explicit no-recommendation form.
- Candidate has blockers or lacks approval readiness: disclose that state and name the next Baah gate.
- Recommendation text is mistaken for authorization: preserve the explicit no-auto-start boundary.
- One contract file regresses independently: verifier must require the invariant in all three workflow surfaces.

---

### Task 1: Enforce the Ship closeout recommendation contract

**Files:**
- Modify: `scripts/verify-workflow.sh`
- Modify: `docs/workflow.md`
- Modify: `.agents/skills/taisa-workflow/SKILL.md`
- Modify: `.agents/skills/taisa-workflow/templates/bounded-goal.md`

**Interfaces:**
- Consumes: Linear priority, blocker, dependency, and approval-readiness state at Ship closeout.
- Produces: exactly one `Recommended next outcome` or `No next outcome recommended`, its evidence-based reason, and the required next Baah gate; no successor mutation.

- [x] **Step 1: Add failing verifier assertions**

Require all workflow surfaces to contain the recommendation output, evidence inputs, no-candidate form, and explicit kickoff boundary.

- [x] **Step 2: Run the verifier and confirm RED**

Run: `npm run verify:workflow`

Expected: FAIL because the strengthened recommendation contract is absent.

- [x] **Step 3: Implement the minimal workflow contract**

Add the approved rules to the human workflow, orchestrator, and Goal template without changing unrelated process behavior.

- [x] **Step 4: Run focused and full verification and confirm GREEN**

Run: `npm run verify:workflow`

Expected: `Workflow verification passed.`

Run: `bash scripts/verify-doc-freshness.sh docs/superpowers/plans/2026-10-09-enforce-next-outcome-recommendation.md`

Expected: exit 0.

- [x] **Step 5: Commit**

```bash
git add docs/workflow.md .agents/skills/taisa-workflow/SKILL.md .agents/skills/taisa-workflow/templates/bounded-goal.md scripts/verify-workflow.sh docs/superpowers/plans/2026-10-09-enforce-next-outcome-recommendation.md
git commit -m "docs: enforce next outcome recommendations"
```
