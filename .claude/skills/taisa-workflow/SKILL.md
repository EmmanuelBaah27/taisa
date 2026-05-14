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
- Platform: `5781b10c-40e9-4354-92de-ba0e41f0055d`
- Product: `88f604d4-de41-4b3e-a7ae-f512012e98d3`

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
