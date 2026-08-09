# Taisa Workflow System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full Taisa workflow system — docs, skills, and Linear setup — so Claude operates autonomously across all feature stages with Baah approving at gates only.

**Architecture:** Seven self-contained tasks executed in order. Tasks 1–5 are file writes/updates. Task 6 creates Linear labels via MCP. Task 7 updates the Linear project description. No app code is changed — this is pure workflow infrastructure.

**Tech Stack:** Markdown, YAML frontmatter, Linear MCP (`save_issue`, `create_issue_label`, `save_project`), git.

**Spec:** `docs/superpowers/specs/2026-05-14-taisa-workflow-design.md`

---

### Task 1: Create docs/backlog.md

**Files:**
- Create: `docs/backlog.md`

- [ ] **Step 1: Create the file**

```markdown
# Taisa Backlog

Ideas captured here by Claude during sessions. Nothing in this file is active work.
To promote an idea to the pipeline, tell Claude "let's scope [idea]."

Claude-maintained — do not edit manually. Sync to Linear with "sync the backlog."

---

| Date | Idea | Context |
|---|---|---|
| *(Claude adds rows here as ideas are mentioned)* | | |
```

- [ ] **Step 2: Commit**

```bash
git add docs/backlog.md
git commit -m "docs: add backlog capture file"
```

---

### Task 2: Update docs/workflow.md

**Files:**
- Modify: `docs/workflow.md`

Replace the entire file with the content below. Every section has been updated to reflect
the approved spec: feature tiers, DS foundation layer, three design paths, active work table,
backlog rule, rollback, skeleton pattern, and gate definitions.

- [ ] **Step 1: Replace docs/workflow.md with updated content**

```markdown
# Taisa Build Workflow

How work moves from idea to shipped. Read this at the start of every feature session.
Claude maintains the Active Work table — Baah never needs to update it.

---

## Active work

| Feature | Track | Stage | Branch | Blocked on |
|---|---|---|---|---|
| *(empty — Claude updates this at every stage transition)* | | | | |

---

## Feature tiers

Not every feature needs the full workflow. Claude assesses tier at task start and states it.

| Tier | Signal | Process |
|---|---|---|
| **Quick** (< 1h) | Single change, no new DS components, no Platform work | No scope doc. No Linear issue. Claude states intent, builds, Baah QAs. Done in one session. |
| **Standard** (half day) | New screen or significant component, existing DS only | Scope + plan in one message. One approval gate. Linear issue created. |
| **Full** (multi-day / multi-track) | New Platform work, new DS components, or complex Product | Full workflow — all stages, all gates, all Linear tracking. |

Baah can override: "treat this as Quick" or "go Full on this."

---

## The Two Tracks

**Platform** — AI, backend, infrastructure. Runs one phase ahead of Product.
**Product** — UI, screens, components. Cannot enter BUILD until its Platform dependency is in BUILD.

**Design System** is not a separate track. It is a mandatory foundation layer inside every
Product BUILD — confirmed at PLAN, built first during BUILD, ships in the same PR.

```
Platform  →  SCOPE → PLAN → BUILD → REVIEW
Product   →  SCOPE → DESIGN → PLAN → BUILD (DS layer → screens) → REVIEW
```

---

## The Five Stages

```
SCOPE → DESIGN → PLAN → BUILD → REVIEW + QA
```

### 1. Scope
**Who:** Baah (product decisions) + Claude (`scope-writer` skill)
**Output:** Scope doc in `docs/features/<name>.md` (Full tier) or inline note (Standard)
**Auto-chain:** After scope agreed → Platform: `writing-plans` fires. Product: Claude prompts for design.

Scope doc format:
- What is it?
- Why now?
- Acceptance criteria (checkboxes — observable behaviour, not implementation)
- Platform dependencies (Product features only)
- Out of scope

A feature is not ready to plan until its scope is written and agreed.

### 2. Design
**Who:** Baah (provides design) + Claude (`design-handoff` skill)
**Applies to:** Product track only.
**Auto-chain:** When Baah shares any design reference → `design-handoff` fires → brief produced → `writing-plans` fires automatically after brief confirmed.

Three design paths — same `design-handoff` process, same brief output:

| Path | Trigger | Implementation latitude |
|---|---|---|
| Figma / screenshots | Baah shares Figma URL or exported image | Highest precision |
| Sketch | Baah shares sketch photo or scan | Directional — DS tokens fill gaps |
| Visual Companion | Brainstorming session ends with agreed mockups | Most directional — device QA is real sign-off |

Minimum design handoff (all paths):
- Layout intent for all screens in the flow (happy path + key error/empty states)
- Component states (default, active, disabled, empty) — even just described in words
- Which DS tokens apply (or note that tokens are TBD)
- Interactions that affect build decisions (gestures, animations)

### 3. Plan
**Who:** Claude (`writing-plans` skill) + Baah (approves summary)
**Output:** Implementation plan in `docs/superpowers/plans/<name>.md`
**Auto-chain:** After Baah approves plan summary → BUILD starts.

Every Product plan includes a DS components section (sourced from the design-handoff brief):
- Existing DS components (reuse, no build needed)
- New DS components (confirmed by Baah at plan approval)

**Platform dependency check:** Before writing a Product plan, Claude verifies Platform
dependency stage. If not yet in BUILD:
- **Wait** → feature stays in SCOPE
- **Skeleton** → plan written for shell-only build (DS + layout + mock data). Blocked tasks
  marked `[BLOCKED: needs <Platform feature>]`. Follow-up plan written when Platform ships.

### 4. Build
**Who:** Claude (`executing-plans` skill, `dispatching-parallel-agents` if multi-track)
**Input:** Approved plan + design reference
**Output:** Working code, committed to `feature/<name>`

**DS build order (strict — never deviate):**
1. DS layer → `mobile/src/components/ui/` (NativeWind, typed props, no business logic)
2. Screen layer → imports only from `mobile/src/components/ui/`, no inline primitive styles

**Token check before BUILD:**
- Tokens defined → proceed normally
- Tokens partial → proceed, mark gaps `// TOKEN-TBD: needs <value>`, refine at REVIEW
- No tokens at all → flag to Baah, get explicit go-ahead before building

**Mid-build DS discovery:** Component found that should be in DS but wasn't in the plan:
- No existing usage affected → move to DS immediately, note in commit message
- Moving it affects already-built screens → finish inline, flag at REVIEW for extraction

### 5. Review + QA
**Who:** Claude (`requesting-code-review` + `verification-before-completion`) + Baah (device QA)

**DS compliance check (blocks PR if any fail):**
- [ ] All visual primitives in screens import from `mobile/src/components/ui/`
- [ ] No `StyleSheet.create()` in new or changed files
- [ ] New DS components: typed + exported props, documented in `docs/design-system.md`
- [ ] No business logic inside DS components

**If build fails QA:**
1. Baah notes specific failures in chat
2. Claude creates `docs/features/<name>-qa-notes.md`
3. Active Work table reverts to In Build
4. Claude fixes, re-runs `verification-before-completion`, re-raises for QA

A feature is not merged until both checks pass.

---

## DS update rules

**Feedback routing — where changes land:**
```
Feedback touches a DS component or token?
  YES → update mobile/src/components/ui/<Component>.tsx + docs/design-system.md
        change propagates to every screen that uses it
  NO  → update the screen directly (layout, positioning, screen-specific logic)
```

**DS update threshold:**
| Change type | Action |
|---|---|
| New variant / backwards-compatible prop | Autonomous — add it, document it |
| Behaviour change affecting all usages | Surface to Baah: "This changes [X] everywhere — confirm?" |
| Breaking change (removed prop, renamed export) | Always ask — show all usages and impact |

---

## Idea backlog

Before a feature enters the workflow, it must be captured.

**Trigger:** Baah mentions a new idea, improvement, or "we should…" in any session.
**Claude's response:** One line added to `docs/backlog.md`. Confirmed in chat. Nothing else.

Linear issues are created only when a Backlog item enters active scoping.
To promote: "let's scope [idea]" → Claude checks Linear for existing Backlog issue first.
To batch sync: "sync the backlog" → Claude creates Linear issues for all unsynced rows.

---

## Parked features

Feature deprioritised mid-pipeline:
- Active Work table → remove row
- Linear → Canceled, comment with reason
- Branch preserved (do not delete)
- Scope doc + plan remain in place

---

## Document conventions

| Document | Location | Written by |
|---|---|---|
| Roadmap | `docs/roadmap.md` | Both — kept current |
| Backlog | `docs/backlog.md` | Claude (auto-maintained) |
| Scope docs | `docs/features/<name>.md` | Claude + Baah |
| Implementation plans | `docs/superpowers/plans/<name>.md` | Claude |
| Design system | `docs/design-system.md` | Baah + Claude (DS components) |
| API reference | `docs/api.md` | Claude (updated on every route change) |
| Workflow | `docs/workflow.md` | Claude (Active Work table) + Baah |
| QA notes | `docs/features/<name>-qa-notes.md` | Claude (on QA failure) |

**Skills invoked per stage:**
| Stage | Skill |
|---|---|
| Scoping | `scope-writer` |
| Design handoff | `design-handoff` |
| Planning | `writing-plans` |
| Building | `executing-plans` / `dispatching-parallel-agents` |
| Review | `requesting-code-review` + `verification-before-completion` |
| All of the above | `taisa-workflow` (master orchestrator — read at session start) |

---

## Gate definitions

| Gate | Artifact | Baah signal |
|---|---|---|
| Scope agreed | `docs/features/<name>.md` exists | Any approval intent |
| Plan approved | `docs/superpowers/plans/<name>.md` exists | Any approval intent |
| Ship | Code review + verification passed | Baah confirms device QA in chat |

Claude reads intent, not keywords. Ambiguous → one yes/no question.

---

## Git conventions

- One branch per feature: `feature/<name>`
- Commits: `feat:`, `feat(ds):`, `fix:`, `fix(ds):`, `test:`, `docs:`
- PR created when build + local QA pass — not before
- PR description links to scope doc and lists ACs met
- Merge to `main` only after Review + QA sign-off

---

## Roadmap hygiene

- Roadmap updated when a feature changes phase
- Active Work table in this file updated at every stage transition (Claude owns this)
- Scope docs for the next phase written while current phase is in Build
- If a dependency slips, the blocked feature stays in its current phase
```

- [ ] **Step 2: Verify the file looks correct**

```bash
wc -l docs/workflow.md
# Expected: ~170 lines
```

- [ ] **Step 3: Commit**

```bash
git add docs/workflow.md
git commit -m "docs: rewrite workflow with DS foundation layer, tiers, and skill chain"
```

---

### Task 3: Update docs/roadmap.md

**Files:**
- Modify: `docs/roadmap.md`

Add the Active Work table immediately after the header block (after the `---` separator
following the design direction and two tracks lines).

- [ ] **Step 1: Add Active Work table to roadmap.md**

Insert this block after line 6 (after the `---` separator):

```markdown
## Active work

| Feature | Track | Stage | Branch | Blocked on |
|---|---|---|---|---|
| *(empty — Claude updates at every stage transition)* | | | | |

---
```

- [ ] **Step 2: Verify position**

```bash
head -20 docs/roadmap.md
# Expected: header → Active work table → How to read this → phases
```

- [ ] **Step 3: Commit**

```bash
git add docs/roadmap.md
git commit -m "docs: add Active Work table to roadmap"
```

---

### Task 4: Create .claude/skills/taisa-workflow/SKILL.md

**Files:**
- Create: `.claude/skills/taisa-workflow/SKILL.md`

This is the master orchestrator skill. Claude reads it at the start of every feature
session. It contains all 22 items from the spec. Write the complete content below.

- [ ] **Step 1: Create the directory and file**

```bash
mkdir -p .claude/skills/taisa-workflow
```

- [ ] **Step 2: Write the skill**

```markdown
---
name: taisa-workflow
description: >
  Use at the start of every Taisa feature session — before scoping, planning,
  building, or reviewing any work. Determines current workflow stage, fires the
  right skill automatically, updates Linear at each gate, and defines what Claude
  handles autonomously vs. what Baah must approve.
---

# Taisa Workflow Orchestrator

Read this at the start of every feature task. It tells you what stage we're in,
what to invoke next, what to update in Linear, and where Baah must approve.

---

## 1. Session start — reconcile before doing anything

```bash
git branch --list feature/*      # confirm active branches exist
ls docs/features/                # confirm scope docs exist
ls docs/superpowers/plans/       # confirm plan docs exist
```

Cross-reference results against the Active Work table in `docs/workflow.md`.
If stale (branch or doc missing), update the table before proceeding.
Then read the table to orient for the session.

---

## 2. Feature tier — assess at the start of every task

| Tier | Signal | Process |
|---|---|---|
| **Quick** (< 1h) | Single change, no new DS components, no Platform work | State intent in one line, build, Baah QAs. No scope doc, no Linear issue. |
| **Standard** (half day) | New screen or significant component, existing DS only | Scope + plan in one message, one approval gate, Linear issue. |
| **Full** (multi-day / multi-track) | New Platform work, new DS components, or complex build | Full workflow — all stages, all gates, full Linear tracking. |

State the tier: "This is a Standard build — [what it does]."
Baah can override at any time: "treat this as Quick" or "go Full."

---

## 3. Autonomy chain — never wait for Baah to name the next skill

```
Baah initiates scoping
  → invoke scope-writer
  → Baah agrees scope doc
  → [Full/Standard] create Linear issue (Todo, track label)
  → [Platform] invoke writing-plans directly
  → [Product] prompt: "Ready for design — share Figma, sketch, or run brainstorm"
      → Baah shares design reference (any format)
      → invoke design-handoff
      → Baah confirms brief
      → comment plan path in Linear
      → invoke writing-plans automatically
  → Baah approves plan summary
  → Linear status → In Progress
  → invoke executing-plans (+ dispatching-parallel-agents if multi-track)
  → BUILD complete
  → invoke requesting-code-review + verification-before-completion
  → Baah QAs on device, confirms
  → Linear status → Done, comment merge SHA
```

---

## 4. Gate definitions

| Gate | Artifact check | Baah confirmation |
|---|---|---|
| Scope agreed | `docs/features/<name>.md` exists | Any approval intent |
| Plan approved | `docs/superpowers/plans/<name>.md` exists | Any approval intent |
| Ship | Code review + verification passed | Baah confirms device QA in chat |

Read intent, not keywords. Ambiguous → one yes/no question, never assume.

---

## 5. Design stage — three paths, same output

All paths invoke `design-handoff`. Brief produced is the DS layer of the plan.

| Path | Trigger | Latitude |
|---|---|---|
| Figma / screenshots | Baah shares Figma URL or exported image | Highest precision |
| Sketch | Baah shares sketch photo or scan | Directional — DS tokens fill gaps |
| Visual Companion | Brainstorm session ends with agreed mockups | Most directional — device QA is the real sign-off |

---

## 6. DS foundation layer rules

**Token check before any Product BUILD:**
- Defined → proceed
- Partial → proceed, mark gaps `// TOKEN-TBD: needs <value>`, refine at REVIEW
- None → flag to Baah, get explicit go-ahead

**Build order — never deviate:**
1. DS layer → `mobile/src/components/ui/` (NativeWind only, typed + exported props, no business logic, add to `docs/design-system.md`)
2. Screen layer → import only from `mobile/src/components/ui/`, no inline primitive styles

**DS vs screen decision tree:**
```
Visual primitive (colour, type, spacing, border, shadow)? → DS
Reusable pattern, 2+ uses or likely? → DS
Purely presentational, no screen state or data? → DS (flag if 1 use only)
Screen layout, scroll behaviour, data hooks, navigation? → Screen
Mix of both? → Split: presentational shell to DS, data/logic wrapper in screen
```

DS classification is Claude's call. Baah sees result at REVIEW.
Uncertain? Make the safer call (DS), note it: "Treated X as DS — check at REVIEW."

**Mid-build discovery:**
- New, no existing usage affected → move to DS now, note in commit
- Moving it affects already-built screens → finish inline, flag at REVIEW

**DS update threshold:**
- New variant / backwards-compatible prop → autonomous
- Behaviour change affecting all usages → "This changes [X] everywhere — confirm?"
- Breaking change (removed prop, renamed export) → always ask, show all usages + impact

**DS compliance check — runs at every REVIEW, blocks PR if any fail:**
- [ ] All visual primitives in screens import from `mobile/src/components/ui/`
- [ ] No `StyleSheet.create()` in new or changed files
- [ ] New DS components: typed + exported props, documented in `docs/design-system.md`
- [ ] No business logic inside DS components

**Feedback routing:**
- Touches DS component or token → update DS, propagates everywhere
- Screen-specific (layout, positioning, screen logic) → update screen directly
- Ambiguous → surface question with a recommendation

---

## 7. BTS learning notes

Add a `> **BTS:**` note when:
- Non-obvious architectural choice made (why this over the alternative)
- Platform feature scoped or built (what it enables for the UI)
- DS compliance flag fires (why the rule exists)
- Bug fixed (what broke at the root)
- New API endpoint built (data flow from screen tap to DB and back)
- DS breaking change flagged (concrete before/after)

Format:
```
> **BTS:** [1–3 lines. Design language. Skippable.]
```

Baah: "explain more" → go deeper. "Skip BTS" → drop for the session.
Never BTS routine actions (commits, file writes, package installs).

---

## 8. Translation rule — design language always

- Platform work → "what it enables for the UI" (never just the file or function name)
- Plan approval → present a plain-English build summary. Baah approves the summary, not the plan doc.
- Breaking DS change → before/after in visual terms, not prop names
- Examples:
  - `chatProcessor.ts` → "the coaching brain that powers the four conversation modes"
  - `contextType param on /analyze` → "tells the API which screen started the conversation"
  - `Button prop removed` → "Button currently accepts `size='sm'` — this removes it. Affected screens: [list]"

---

## 9. Backlog rule

Idea mentioned → add one line to `docs/backlog.md`:
```
| YYYY-MM-DD | [idea] | [context Baah gave] |
```
Confirm in chat: "Noted in backlog: [idea]"

Do NOT create a Linear issue. Do NOT scope, plan, or build.

**Backlog → pipeline:** Baah says "scope [idea]" → search Linear for existing Backlog issue.
If found → update to Todo. If not found → create issue, then scope.
Confirm: "Found existing backlog issue — [title]. Scoping from there." or "Creating new."

**Batch sync:** Baah says "sync the backlog" → create Linear Backlog issues for all
`docs/backlog.md` rows that don't have a corresponding Linear issue yet.

---

## 10. Linear actions

**Project:** `31b0d99c-6f74-4c9c-af2a-12e6e25aabe0` (Taisa - career guide)
**Team:** `e95356d8-17f7-4700-bdfe-222782bea546` (A Playing Field)

**Status IDs:**
- Todo: `8092f145-a7b5-4e09-812e-1d3212fc1c7d`
- In Progress: `ad545d06-1ef1-4c5d-86c7-44e1e3724409`
- Done: `b2c07c6b-bf80-40d1-8e08-9c941b04f137`
- Canceled: `e2a4cb1f-daf0-4269-8acc-9b0fed9224f5`

**Label IDs:**
- Feature: `a57ef5fa-88a5-42ae-9262-e4f1ae7f828c`
- Design System: `5ab8ecc1-169f-4d2d-b855-7ca874b6453e`
- Platform: *(created in Task 6 — update this ID after creation)*
- Product: *(created in Task 6 — update this ID after creation)*

| Event | Linear action |
|---|---|
| Scope agreed (Full/Standard) | Create issue: Todo, Feature label + Platform or Product label |
| Design handoff confirmed | Comment: "Design reference confirmed — [path/source]" |
| Plan approved | Comment: plan path + DS component list |
| BUILD starts | Status → In Progress |
| Ship | Status → Done, comment: "Merged [SHA]" |
| Parked | Status → Canceled, comment: reason |
| Standalone DS feedback | Create issue: Design System label |
| Backlog idea | Create issue: Backlog status (no Todo), Feature label |

**Error handling:** MCP call fails → log "Linear update failed — [action]. Continuing."
Build proceeds. List all failures at end of session. Retry issue creation once before logging.

---

## 11. Rollback protocol

BUILD fails QA:
1. Baah notes specific failures in chat
2. Claude creates `docs/features/<name>-qa-notes.md` with exact failures
3. Active Work table → back to "In Build"
4. Fix issues, re-run `verification-before-completion`
5. Re-raise for QA only after verification passes

---

## 12. Parked state

Feature deprioritised mid-pipeline:
- Remove from Active Work table
- Linear → Canceled, comment reason
- Branch preserved (do not delete)
- Scope doc + plan remain in `docs/features/` and `docs/superpowers/plans/`

---

## 13. Skeleton pattern

Platform dependency not yet in BUILD when Product is ready to plan:
- Flag to Baah: "Platform dependency [X] is in [current stage] — not in BUILD yet"
- Baah decides:
  - **Wait** → feature stays in SCOPE, nothing written
  - **Skeleton** → write plan for shell-only: DS components + screen layout + mock data
    Mark blocked tasks: `[BLOCKED: needs <Platform feature> in BUILD]`
    When Platform ships → write follow-up plan for wiring tasks only

---

## 14. Claude owns all housekeeping

Baah never updates these — Claude does:
- `docs/workflow.md` Active Work table → updated at every stage transition
- `docs/backlog.md` → updated when ideas are mentioned
- Linear issue status + comments → updated at every gate
- Plan doc `**Status:**` field → updated when approved
- Session re-orientation → Claude reads current state, tells Baah where we are
```

- [ ] **Step 3: Verify file created**

```bash
ls .claude/skills/taisa-workflow/
# Expected: SKILL.md
wc -l .claude/skills/taisa-workflow/SKILL.md
# Expected: ~200 lines
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/taisa-workflow/SKILL.md
git commit -m "feat: add taisa-workflow orchestrator skill"
```

---

### Task 5: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

Two changes: (1) add a Workflow section before the Backend Pattern section, (2) add a row
to the "Where to Look" table.

- [ ] **Step 1: Add Workflow section**

Insert this block immediately before the `## Backend Pattern` section:

```markdown
## Workflow

Invoke the `taisa-workflow` skill at the start of every scope, plan, build, or review
task. This is not optional.

The workflow in `docs/workflow.md` is the source of truth for how work moves.
Baah approves at gates: scope doc, plan summary, ship. Claude handles everything else
autonomously — Active Work table, Linear updates, DS classification, session orientation.
```

- [ ] **Step 2: Add row to Where to Look table**

Add this row to the existing table:

```markdown
| Follow the build workflow | `docs/workflow.md` + `taisa-workflow` skill |
```

- [ ] **Step 3: Verify CLAUDE.md looks correct**

```bash
grep -n "taisa-workflow" CLAUDE.md
# Expected: 2 matches — one in Workflow section, one in Where to Look table
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add workflow enforcement to CLAUDE.md"
```

---

### Task 6: Create Linear labels

**Tools:** `mcp__claude_ai_Linear__create_issue_label`

Create two new labels in the A Playing Field workspace for track identification.
After creating each, note the returned ID — update the Linear actions table in
`.claude/skills/taisa-workflow/SKILL.md` with the real IDs.

- [ ] **Step 1: Load the create_issue_label schema**

```
ToolSearch: select:mcp__claude_ai_Linear__create_issue_label
```

- [ ] **Step 2: Create Platform label**

Call `mcp__claude_ai_Linear__create_issue_label` with:
```json
{
  "name": "Platform",
  "color": "#4EA7FC",
  "team": "A Playing Field"
}
```

Note the returned `id`. Expected result: label named "Platform", blue.

- [ ] **Step 3: Create Product label**

Call `mcp__claude_ai_Linear__create_issue_label` with:
```json
{
  "name": "Product",
  "color": "#BB87FC",
  "team": "A Playing Field"
}
```

Note the returned `id`. Expected result: label named "Product", purple.

- [ ] **Step 4: Update taisa-workflow skill with real label IDs**

In `.claude/skills/taisa-workflow/SKILL.md`, replace the placeholder lines:
```
- Platform: *(created in Task 6 — update this ID after creation)*
- Product: *(created in Task 6 — update this ID after creation)*
```

With the actual IDs returned from the MCP calls.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/taisa-workflow/SKILL.md
git commit -m "docs: add Linear Platform and Product label IDs to workflow skill"
```

---

### Task 7: Update Linear project description

**Tools:** `mcp__claude_ai_Linear__save_project`

Add a one-line workflow summary to the Taisa project description in Linear.

- [ ] **Step 1: Load the save_project schema**

```
ToolSearch: select:mcp__claude_ai_Linear__save_project
```

- [ ] **Step 2: Update the project**

Call `mcp__claude_ai_Linear__save_project` with:
```json
{
  "id": "31b0d99c-6f74-4c9c-af2a-12e6e25aabe0",
  "description": "Taisa is a personal AI career companion. Issues here track features through the build workflow: Backlog → Todo (scoped) → In Progress (building) → Done (shipped). Workflow reference: docs/workflow.md in the taisa repo."
}
```

- [ ] **Step 3: Verify in Linear**

Open Linear and confirm the project description is updated under Taisa - career guide.

---

## Self-review

**Spec coverage check:**

| Spec requirement | Covered by |
|---|---|
| Active Work table in workflow.md | Task 2 |
| Active Work table in roadmap.md | Task 3 |
| Feature tiers (Quick/Standard/Full) | Task 2 (workflow.md) + Task 4 (skill) |
| Three-track model (DS as foundation layer) | Task 2 |
| Stage → skill autonomy chain | Task 4 (skill section 3) |
| Three design paths (Figma/sketch/visual companion) | Task 2 + Task 4 (skill section 5) |
| Gate definitions (artifact + confirmation) | Task 2 + Task 4 (skill section 4) |
| Session-start reconciliation | Task 4 (skill section 1) |
| DS token prerequisite (3 states) | Task 2 + Task 4 (skill section 6) |
| DS/screen decision tree | Task 2 + Task 4 (skill section 6) |
| DS build order (DS layer first) | Task 2 + Task 4 (skill section 6) |
| DS mid-build discovery protocol | Task 2 + Task 4 (skill section 6) |
| DS update threshold | Task 2 + Task 4 (skill section 6) |
| DS compliance check at REVIEW | Task 2 + Task 4 (skill section 6) |
| DS feedback routing | Task 2 + Task 4 (skill section 6) |
| BTS learning notes | Task 4 (skill section 7) |
| Translation rule | Task 4 (skill section 8) |
| Backlog rule (docs/backlog.md) | Task 1 + Task 4 (skill section 9) |
| Backlog → pipeline dedup | Task 4 (skill section 9) |
| Batch sync to Linear | Task 4 (skill section 9) |
| Linear actions per transition (with IDs) | Task 4 (skill section 10) |
| Linear error handling | Task 4 (skill section 10) |
| Rollback protocol | Task 2 + Task 4 (skill section 11) |
| Parked state | Task 2 + Task 4 (skill section 12) |
| Skeleton pattern | Task 2 + Task 4 (skill section 13) |
| Claude owns housekeeping | Task 4 (skill section 14) |
| CLAUDE.md enforcement | Task 5 |
| Platform label in Linear | Task 6 |
| Product label in Linear | Task 6 |
| Linear project description | Task 7 |

All 28 spec requirements covered. No gaps.

**Placeholder scan:** No TBD, TODO, or incomplete sections. Task 6 step 4 requires updating the skill with real IDs after label creation — this is intentional and will not be empty after execution.

**Type consistency:** No code types — this is documentation only. File paths used consistently throughout.
