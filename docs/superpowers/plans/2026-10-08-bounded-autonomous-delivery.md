# Bounded Autonomous Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Approved
**Last updated:** 2026-10-08

**Goal:** Replace Taisa's overlapping persistent Product and Linear loops with one verified, issue-bounded delivery workflow that minimizes Baah touchpoints and never consumes active Goal turns merely to wait.

**Architecture:** Linear remains the live delivery authority and Git remains the versioned technical authority. The repository will define one bounded Goal template, deterministic fast/high-risk paths, exclusive Platform/Product/Integration slices, QA-readiness and repair-release gates, and verifier-enforced anti-churn invariants. Existing goal histories stay preserved and paused while a one-time Linear transition ledger accounts for their in-flight state.

**Tech Stack:** Markdown operating contracts, Bash workflow verifier, Git/GitHub, Linear, Codex Goals and chats.

**Spec:** `docs/superpowers/specs/2026-10-08-bounded-autonomous-delivery-design.md`

## Global Constraints

- This is process-only work; do not modify SwiftUI, React Native, backend, shared, or product UI code.
- One delivery cycle has one primary Linear issue and one accountable conductor.
- Platform, Product, and Integration are exclusive task owners inside the same conductor, not persistent Goals or permanent branches.
- Quick and ordinary Standard work uses one kickoff approval; Full or high-risk work uses separate Scope and Plan approvals.
- A Goal run terminates at a named handoff and never remains active solely to await Baah or unchanged external state.
- A physical defect observed once enters repair quarantine and cannot return to Baah until the repair-release gate passes.
- An unresolved defect remains `Unfixed; blocking; unshippable` and cannot permit QA-ready, Ship-ready, closure, or successor-work claims.
- Preserve all existing branches, worktrees, goal histories, approvals, Linear history, and user changes.
- Do not resume either retired goal, merge, delete work, or infer Ship approval.

## Review Focus

- A Quick-looking change that touches privacy must select the high-risk path and require separate Scope and Plan evidence.
- A completed Goal at `QA_READY` must not auto-restart or poll while Baah considers the result.
- A physical QA defect must produce a repair Goal on the same issue and cannot bypass the repair-release gate.
- A cross-stack task must place every task in exactly one of Platform, Product, or Integration without creating another conductor.
- A healthy long-running CI check must use event-capable waiting or record one external wait, never repeated unchanged polling turns.

---

## File map

- `docs/workflow.md` — human-readable source of truth for bounded cycles, approval paths, track ownership, QA, waiting, closeout, and shipping.
- `.claude/skills/taisa-workflow/SKILL.md` — operational routing instructions agents execute at runtime.
- `.claude/skills/taisa-workflow/templates/bounded-goal.md` — canonical reusable objective template for Build, repair, and Ship Goal runs.
- `AGENTS.md` — concise mandatory entry contract for all agents.
- `CLAUDE.md` — project-context summary pointing agents to the bounded workflow.
- `scripts/verify-workflow.sh` — executable regression checks for repository-wide workflow invariants.
- Linear transition issue/document — live one-time ledger for the two retired goals and every in-flight item they touched; no duplicated repository status ledger.

### Task 1: Add failing verifier coverage for bounded-delivery invariants

**Files:**
- Modify: `scripts/verify-workflow.sh`
- Test: `scripts/verify-workflow.sh`

**Interfaces:**
- Consumes: repository workflow files and the future `.claude/skills/taisa-workflow/templates/bounded-goal.md`.
- Produces: shell assertions that fail when mandatory bounded-delivery language or the Goal template is absent.

- [ ] **Step 1: Add a required-file assertion for the Goal template**

Add `.claude/skills/taisa-workflow/templates/bounded-goal.md` to the verifier's required workflow paths using the script's existing failure accumulator. The diagnostic must name the missing path.

- [ ] **Step 2: Add exact invariant groups**

Add checks requiring these concepts in the named files:

```text
docs/workflow.md:
  bounded Goal run
  kickoff bundle
  high-risk predicates
  REPAIR_QUARANTINE
  Unfixed; blocking; unshippable
  Platform / Product / Integration exclusive ownership

.claude/skills/taisa-workflow/SKILL.md:
  no active Goal solely for waiting
  QA_READY
  MATERIAL_REAPPROVAL_REQUIRED
  repair-release gate
  no successor issue selection

bounded-goal.md:
  primary Linear issue
  terminal outcome
  approved kickoff or Scope/Plan evidence
  branch/worktree
  acceptance criteria
  prohibited unchanged polling
  next Baah gate
```

Use the verifier's existing literal/regex helper style rather than introducing another shell framework.

- [ ] **Step 3: Add forbidden-pattern checks**

Reject the Goal template when it contains any of these unbounded instructions:

```text
continue until the complete product ships
select the next highest-priority issue and continue
poll again until complete
silence counts as approval
```

The failure message must identify the file and forbidden phrase.

- [ ] **Step 4: Run the verifier and confirm RED**

Run:

```bash
bash scripts/verify-workflow.sh
```

Expected: non-zero exit because the Goal template and new bounded-delivery invariants do not yet exist.

- [ ] **Step 5: Check shell syntax**

Run:

```bash
bash -n scripts/verify-workflow.sh
```

Expected: exit 0.

- [ ] **Step 6: Commit the failing contract tests**

```bash
git add scripts/verify-workflow.sh
git commit -m "test: require bounded delivery workflow"
```

### Task 2: Make the human-readable workflow bounded and fast by default

**Files:**
- Modify: `docs/workflow.md`
- Test: `scripts/verify-workflow.sh`

**Interfaces:**
- Consumes: approved design specification and Task 1 invariant names.
- Produces: canonical human-readable definitions used by `AGENTS.md`, `CLAUDE.md`, and the orchestrator.

- [ ] **Step 1: Replace global session orientation with cycle-start plus incremental orientation**

Preserve full reconciliation at cycle entry. Add a stable-cycle rule that rechecks only changed issue, branch/worktree, approval, dependency, preview, PR, CI, or remote state. Explicitly prohibit rereading all milestones, worktrees, and chats when relevant revision markers are unchanged.

- [ ] **Step 2: Replace tier approval behavior with a deterministic table**

Encode:

```text
Quick/Standard + no high-risk predicate → one kickoff bundle approves Scope and Plan
Full → separate Scope and Plan
Any tier + high-risk predicate → separate Scope and Plan
Explicit Baah request → separate Scope and Plan
```

Copy the complete high-risk predicate list from the specification. Define material-change reapproval: amended kickoff when still eligible; otherwise separate revised Scope and Plan.

- [ ] **Step 3: Preserve Platform/Product/Integration as exclusive internal slices**

Rewrite the tracks section so every task has exactly one owner. State that cross-cutting quality concerns are acceptance constraints, Integration owns wiring/proof rather than duplicate implementation, and no slice creates another persistent Goal.

- [ ] **Step 4: Add the bounded Goal lifecycle**

Define Build, repair, and Ship Goal runs and their terminal outcomes:

```text
QA_READY
UNRESOLVED_ESCALATION
MATERIAL_REAPPROVAL_REQUIRED
NON_DEVICE_SHIP_READY
EXTERNAL_WAIT_RECORDED
```

State that human-gate waiting happens after Goal completion, not inside an active loop.

- [ ] **Step 5: Add initial QA-readiness and repair-release gates**

Copy the evidence requirements from the specification. Preserve canonical-preview authority. Add the one-observation quarantine rule, authoritative repair transition sequence, device-coverage rules, and two-outcome notification contract.

- [ ] **Step 6: Limit Linear and progress updates to material events**

Replace "after every material step" ambiguity with the approved event list: approval, Build start, blocker change, stable candidate, preview/QA request, QA defect/replacement, Ship/merge/closeout. Prohibit command-, poll-, retry-, and passing-narrow-test narration.

- [ ] **Step 7: Add next-outcome recommendation and stop behavior**

Copy the six-rank priority order and tie-breakers. Require a recommendation at closeout but prohibit automatic Scope, Build, or successor Goal creation.

- [ ] **Step 8: Run targeted textual checks**

Run:

```bash
rg -n "kickoff bundle|high-risk predicates|QA_READY|REPAIR_QUARANTINE|Unfixed; blocking; unshippable|next-outcome" docs/workflow.md
```

Expected: every concept is present in an operative section, not only a changelog.

- [ ] **Step 9: Commit the workflow contract**

```bash
git add docs/workflow.md
git commit -m "docs: define bounded autonomous delivery"
```

### Task 3: Create the bounded Goal template and runtime orchestrator

**Files:**
- Create: `.claude/skills/taisa-workflow/templates/bounded-goal.md`
- Modify: `.claude/skills/taisa-workflow/SKILL.md`
- Test: `scripts/verify-workflow.sh`

**Interfaces:**
- Consumes: `docs/workflow.md` definitions and one approved Linear issue.
- Produces: a fillable Goal objective with mandatory evidence fields and operational routing that terminates at named handoffs.

- [ ] **Step 1: Create the Goal template with mandatory front matter**

Use this exact field structure:

```markdown
# Taisa bounded delivery Goal

- Primary Linear issue: `<APF-ID and URL>`
- Milestone context: `<name and URL>`
- Run type: `<BUILD | REPAIR | SHIP>`
- Entry state and evidence: `<state plus approval/comment URL>`
- Terminal outcome: `<one allowed terminal outcome>`
- Approved kickoff or Scope/Plan evidence: `<URLs>`
- Work slices: `<Platform | Product | Integration task ownership>`
- Branch/worktree: `<branch and absolute path>`
- Canonical preview baseline: `<SHA or not-device-facing>`
- Acceptance criteria: `<issue checklist>`
- Verification matrix: `<named commands/checks>`
- Permitted mutations: `<bounded list>`
- Prohibited actions: `<bounded list>`
- Next Baah gate: `<one gate>`
```

- [ ] **Step 2: Add execution rules to the template**

Require one issue, incremental orientation, material-only Linear updates, evidence-producing repair attempts, canonical-preview publication for device work, no successor issue, no inferred approval, and no unchanged-state polling.

- [ ] **Step 3: Add run-specific completion blocks**

Define:

```text
BUILD → QA_READY | UNRESOLVED_ESCALATION | MATERIAL_REAPPROVAL_REQUIRED | NON_DEVICE_SHIP_READY | EXTERNAL_WAIT_RECORDED
REPAIR → QA_READY | UNRESOLVED_ESCALATION | MATERIAL_REAPPROVAL_REQUIRED | EXTERNAL_WAIT_RECORDED
SHIP → verified merge/cleanup/closeout/next-outcome recommendation
```

Every completion report must include exact commit, checks, preview/PR state, unresolved risk, Linear update, terminal outcome, and next Baah gate.

- [ ] **Step 4: Rewrite orchestrator routing around bounded runs**

In `SKILL.md`, make ordinary intake prepare a kickoff bundle without starting a Goal. After approval, instantiate the template for one run. Route repair observations into a REPAIR run on the same issue. Finish Goals at gates instead of polling or choosing adjacent work.

- [ ] **Step 5: Encode silent external waiting**

Prefer event-capable waits. When unavailable, record `EXTERNAL_WAIT_RECORDED`, complete the Goal, and use one scheduled or user-triggered continuation near the normal completion window. Unchanged state creates no Linear or Baah update.

- [ ] **Step 6: Run the verifier**

Run:

```bash
bash scripts/verify-workflow.sh
```

Expected: Task 1 Goal-template and orchestrator assertions pass; entrypoint assertions may still fail until Task 4.

- [ ] **Step 7: Commit the runtime contract**

```bash
git add .claude/skills/taisa-workflow/SKILL.md .claude/skills/taisa-workflow/templates/bounded-goal.md
git commit -m "docs: add bounded delivery goal template"
```

### Task 4: Align repository entry instructions

**Files:**
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Test: `scripts/verify-workflow.sh`

**Interfaces:**
- Consumes: `docs/workflow.md` and the Taisa orchestrator.
- Produces: concise startup instructions that cannot reintroduce global per-turn reconciliation or overlapping loops.

- [ ] **Step 1: Update `AGENTS.md` mandatory startup**

Require full orientation once per cycle, incremental reorientation within a stable cycle, one issue/conductor, the fast/high-risk approval split, bounded Goal completion at gates, and repair quarantine after one Baah observation.

- [ ] **Step 2: Update `CLAUDE.md` project context**

State that Platform/Product/Integration remain internal work slices, UI work still requires the design-handoff process, and ordinary work uses one kickoff plus one final acceptance/Ship interaction.

- [ ] **Step 3: Remove conflicting broad-autonomy wording**

Search:

```bash
rg -n "every iteration|continue without waiting|select the next|after every material step|separate Scope and Plan" AGENTS.md CLAUDE.md docs/workflow.md .claude/skills/taisa-workflow/SKILL.md
```

For every match, retain it only when bounded by the new issue-specific and gate-specific rules.

- [ ] **Step 4: Run the workflow verifier**

Run:

```bash
bash scripts/verify-workflow.sh
```

Expected: exit 0.

- [ ] **Step 5: Commit aligned entrypoints**

```bash
git add AGENTS.md CLAUDE.md
git commit -m "docs: align agents with bounded delivery"
```

### Task 5: Create the live transition ledger and retire the old goals

**Files:**
- Modify: Linear Taisa workflow issue/document only
- Preserve: Product-development goal thread `01a11631-c1ca-73b3-aef0-e405262a5467`
- Preserve: Linear-orchestration goal thread `01a1162e-ee0b-7b30-a570-8f6eb7b3ed81`

**Interfaces:**
- Consumes: both goal threads' final pause responses; current Linear/Git/PR/CI/preview state.
- Produces: one Linear transition ledger with exactly one disposition for every in-flight item and permanently retired old goal objectives.

- [ ] **Step 1: Read both pause responses and active-state snapshots**

Use `read_thread` for both referenced threads. Record whether commands or external mutations remain in flight and the last issue, branch/worktree, PR, CI run, preview SHA, and Baah gate each touched.

- [ ] **Step 2: Reconcile the authoritative state**

Read Linear issues named by either thread and verify their branches, worktrees, remote refs, PRs, CI, and canonical preview evidence. Do not trust thread summaries when Git or Linear differs.

- [ ] **Step 3: Create or reuse one non-duplicate workflow-transition issue**

Search Linear for an issue matching “bounded autonomous delivery transition.” Create it only if no equivalent exists. Attach one transition document/section with columns:

```text
Item | Owning Linear issue | Last goal | Branch/worktree | Exact revision | PR/CI/preview | Baah gate | Disposition | Evidence
```

Allowed dispositions are exactly `resume in first bounded cycle`, `awaiting Baah gate`, `blocked`, `preserve inactive`, and `already complete`.

- [ ] **Step 4: Assert exclusive ownership**

Every active item must have one owning Linear issue and no active autonomous goal. Record conflicts as blocked until reconciled; do not choose by timestamp alone.

- [ ] **Step 5: Permanently retire the old objectives**

Send one final message to each thread stating that its broad objective is retired, no work may resume under it, and future execution requires the bounded Goal template. Preserve and archive the threads only after confirming no work remains in flight; do not delete them.

- [ ] **Step 6: Record the efficiency baseline**

In the transition issue, record observed active conductors/issues, repeated unchanged polls, full orientation repetitions, full-suite runs, QA requests, and command-level Linear updates when evidence is available. Mark unavailable measurements as unavailable rather than zero.

- [ ] **Step 7: Commit no repository status ledger**

Run:

```bash
git status --short
```

Expected: no new repository file containing mutable transition status; Linear remains authoritative.

### Task 6: Run final verification and prepare the workflow PR

**Files:**
- Verify: `docs/workflow.md`
- Verify: `.claude/skills/taisa-workflow/SKILL.md`
- Verify: `.claude/skills/taisa-workflow/templates/bounded-goal.md`
- Verify: `AGENTS.md`
- Verify: `CLAUDE.md`
- Verify: `scripts/verify-workflow.sh`
- Verify: `docs/superpowers/specs/2026-10-08-bounded-autonomous-delivery-design.md`
- Verify: `docs/superpowers/plans/2026-10-08-bounded-autonomous-delivery.md`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: verified process-only branch and PR ready for Baah's Ship decision.

- [ ] **Step 1: Run syntax and workflow checks**

```bash
bash -n scripts/verify-workflow.sh
bash scripts/verify-workflow.sh
```

Expected: both exit 0.

- [ ] **Step 2: Run freshness checks for the approved spec and plan**

```bash
bash scripts/verify-doc-freshness.sh \
  docs/superpowers/specs/2026-10-08-bounded-autonomous-delivery-design.md \
  docs/superpowers/plans/2026-10-08-bounded-autonomous-delivery.md
```

Expected: exit 0 with valid Status and Last updated metadata. If the plan verifier requires metadata, add `Status: Approved` and `Last updated: 2026-10-08` beneath its title before rerunning.

- [ ] **Step 3: Verify no product code changed**

```bash
git diff --name-only origin/main...HEAD
```

Expected paths only under `docs/`, `.claude/`, `AGENTS.md`, `CLAUDE.md`, and `scripts/verify-workflow.sh`.

- [ ] **Step 4: Run forbidden-language audit**

```bash
rg -n "continue until the complete product ships|select the next highest-priority issue and continue|poll again until complete|silence counts as approval" \
  docs/workflow.md .claude/skills/taisa-workflow AGENTS.md CLAUDE.md
```

Expected: no matches except explicit forbidden-pattern examples inside verification documentation; the executable Goal template must contain none.

- [ ] **Step 5: Review the branch diff against the specification**

Confirm every acceptance criterion maps to an operative rule or verifier assertion. Confirm Platform/Product/Integration remain present and UI implementation remains out of scope.

- [ ] **Step 6: Commit any final verification-only corrections**

```bash
git add docs/workflow.md .claude/skills/taisa-workflow AGENTS.md CLAUDE.md scripts/verify-workflow.sh
git commit -m "test: verify bounded delivery workflow"
```

Skip the commit when no files changed.

- [ ] **Step 7: Push and create the PR**

Push `docs/bounded-autonomous-delivery`, create a PR targeting `main`, link the Linear transition issue and approved specification, and include the exact verification commands and results. Do not merge without Baah's Ship approval.

## Plan self-review

- Spec coverage: all specification sections map to Tasks 1–6, including bounded Goal runtime, fast/high-risk paths, Platform/Product/Integration, QA gates, quarantine, transition, next-outcome ranking, and efficiency evidence.
- Placeholder scan: angle-bracket values appear only in the Goal template that executors must fill with issue-specific evidence; no implementation step is deferred or unspecified.
- Interface consistency: `QA_READY`, `UNRESOLVED_ESCALATION`, `MATERIAL_REAPPROVAL_REQUIRED`, `NON_DEVICE_SHIP_READY`, and `EXTERNAL_WAIT_RECORDED` are identical across workflow, orchestrator, template, and verifier tasks.
- Review Focus coverage: Task 1 pins high-risk selection, waiting, repair, work-slice, and CI-churn invariants; Tasks 2–4 implement them; Task 6 runs the full gate.
