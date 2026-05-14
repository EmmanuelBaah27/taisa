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
