# Taisa Workflow System — Design Spec

**Date:** 2026-05-14
**Status:** Approved — ready to plan

---

## What we're building and why

The current workflow (`docs/workflow.md`) documents how work moves but doesn't enforce it.
Claude has no reliable way to know what stage a feature is in at session start, no integration
with Linear for tracking, and no Design System track. This spec closes all three gaps.

**Outcome:** Claude reads one skill at every task start, knows exactly what stage a feature is
in, uses the right superpowers skill for that stage, updates Linear automatically at each gate,
and builds DS components as the mandatory foundation layer of every Product feature — never
inline, always in `mobile/src/components/ui/`, always confirmed by Baah at the plan gate.

---

## Idea backlog rule

Before a feature can enter the workflow, it must be captured. The rule prevents
building ad-hoc by giving ideas a home that isn't the active pipeline.

**Trigger:** Baah mentions a new feature idea, improvement, or "we should…" — in any session.

**Claude's response:**
1. Add it to `docs/backlog.md` — one line: date, idea, any context Baah gave
2. Confirm in chat: "Noted in backlog: [idea]"
3. Do NOT create a Linear issue yet, do NOT start scoping, planning, or building

Linear issues are created only when a backlog item enters active scoping. `docs/backlog.md`
is the lightweight capture layer — fast, zero overhead, always in the repo.

**Backlog → Linear:** Claude creates the Linear issue when Baah says "let's scope this."
Claude also batches all unsynced backlog items to Linear when Baah says "sync the backlog"
or at the start of a dedicated backlog review session.

**What lives in Backlog vs. active pipeline:**

| State | Linear status | Meaning |
|---|---|---|
| Raw idea | `Backlog` | Captured, not yet scoped. Nothing blocks on this. |
| Scope agreed | `Todo` | Scope doc written, ready to plan — entered the workflow |
| In plan | `Todo` | Plan being written |
| In build | `In Progress` | Active development |
| In review | `In Progress` | Under review |
| Done | `Done` | Shipped |
| Parked | `Canceled` | Was in pipeline, deprioritised |

Claude never moves a Backlog item forward without Baah explicitly initiating the scope stage.
The backlog is Baah's queue — Claude's job is to keep it tidy (capture ideas, never lose them,
never act on them prematurely).

**Backlog → pipeline transition:** When Baah initiates scoping on an idea, Claude checks
Linear for an existing Backlog issue before creating anything new. If found, that issue
is updated (status → `Todo`) rather than a duplicate being created. Claude confirms:
"Found existing backlog issue — [title]. Scoping from there."

---

## Three-track model

```
Platform      →  SCOPE → PLAN → BUILD → REVIEW
Product       →  SCOPE → DESIGN → PLAN [DS confirmed] → BUILD (DS layer → screens) → REVIEW
```

- **Platform** runs one phase ahead of Product. Product cannot enter BUILD until its Platform
  dependency is in BUILD.
- **Design System** is not a separate track. It is a mandatory foundation layer inside every
  Product BUILD. DS components are confirmed at the PLAN gate, built first during BUILD, and
  ship in the same branch and PR as the feature screens that use them.
- There are no `ds/` branches, no separate DS PRs, no extraction phase.

---

## Feature tiers — process scales to size

Not every feature needs the full workflow. Claude assesses tier at the start of every task.

| Tier | Signal | Process |
|---|---|---|
| **Quick** (< 1h) | Single change, no new DS components, no Platform work | No scope doc. No Linear issue. Claude states intent in one line, builds, Baah QAs. Done in one session. |
| **Standard** (half day) | New screen or significant component, existing DS components only | Lightweight scope note (not full doc). Scope + plan presented together in one message. One approval gate. Linear issue created. |
| **Full** (multi-day / multi-track) | New Platform work, new DS components, or complex Product build | Full workflow — scope doc, design handoff, plan, all gates, Linear tracking. |

Claude states the tier at the start: "This is a Standard build — here's the scope and plan."
Baah can override: "treat this as Quick" or "this is bigger, go Full."

## Stage → skill + gate + Linear action

| Stage | Skill invoked | Auto-trigger | Baah gate | Linear action |
|---|---|---|---|---|
| SCOPE | `brainstorming` → `scope-writer` | Baah initiates scoping | Agree scope doc | Create issue: `Todo`, label=track |
| DESIGN | `design-handoff` | Baah shares design OR brainstorm ends (Visual Companion path) | Confirm handoff brief | Comment: "Design reference confirmed" |
| PLAN | `writing-plans` | design-handoff brief confirmed | Approve plan summary | Comment: plan path + DS list |
| BUILD | `executing-plans` + `dispatching-parallel-agents` | Plan approved | — | Status → `In Progress` |
| REVIEW | `requesting-code-review` + `verification-before-completion` | Build complete | QA on device + ship | Status → `Done`, comment: merge SHA |
| PARKED | — | — | — | Status → `Canceled`, comment: reason |

**Autonomy chain:**
```
Baah initiates scoping
  → scope-writer fires (reads roadmap, drafts scope doc, flags ACs)
  → Baah agrees scope doc
  → [Platform track] writing-plans fires directly
  → [Product track] Claude prompts: "Ready for design — share Figma or run brainstorm"
      → Baah shares Figma / visual companion output
      → design-handoff fires (maps components, checks tokens, flags backend gaps)
      → Baah confirms brief (or Claude resolves open questions)
      → writing-plans fires automatically
  → Baah approves plan summary
  → BUILD starts
```

Claude never waits for Baah to name the next skill. Each stage end triggers the next
stage start automatically. Baah's only job is gate approval and providing input when asked.

DS components are confirmed at PLAN — the design-handoff component inventory (Reuse /
Modify / New) IS the DS section of the plan. No separate DS list needed.

### DESIGN stage — two paths

All three paths feed into `design-handoff`, which produces the structured brief that
`writing-plans` consumes. The source of the design changes — the handoff process does not.
DS tokens carry the precision any source lacks.

**Path A — Figma or screenshots:**
Baah shares a Figma link or exported screens. Claude reads via Figma MCP. Highest
precision. `design-handoff` fires automatically → brief → `writing-plans`.

**Path B — Sketches:**
Baah shares a photo or scan of a hand-drawn sketch. Claude reads the image, interprets
layout intent and component shapes. Treated as directional — implementation latitude
applies for exact spacing. DS tokens fill the gaps. Same handoff process, brief notes
the sketch source.

**Path C — Visual Companion (no external design):**
SCOPE and DESIGN collapse into one brainstorming session. `design-handoff` fires on the
agreed mockups when the session ends. Most directional — device QA is the real sign-off.

**In both paths:** design-handoff's Component inventory (Reuse / Modify / New) IS the
DS layer plan for BUILD. No separate DS component list is produced — the handoff brief
carries it. writing-plans reads the brief and builds the DS section of the plan from it.

---

## Gate definitions

Gates require two things: the artifact exists in the right place, and Baah has confirmed
in the current session. Artifact existence is verifiable from disk. Confirmation is
verifiable from the conversation. Neither alone is sufficient.

| Gate | Artifact check | Baah confirmation |
|---|---|---|
| Scope agreed | `docs/features/<name>.md` exists | Baah says any variant of "looks good", "agreed", "ready to plan" |
| Plan approved | `docs/superpowers/plans/<name>.md` exists | Baah says any variant of "approved", "build it", "go ahead" |
| DS components confirmed | Confirmed as part of plan approval — same gate, no separate step | — |
| Ship | `requesting-code-review` passed, `verification-before-completion` passed | Baah confirms device QA passes in chat |

No specific phrase required — Claude reads intent, not keywords. When intent is genuinely
ambiguous, Claude asks a single yes/no question rather than assuming.

**Session-start reconciliation:** At the start of every feature session, Claude verifies the
Active Work table in `docs/workflow.md` against actual state before trusting it:
- Check `git branch --list feature/*` to confirm branch exists
- Check `docs/features/<name>.md` exists for scope-agreed features
- Check `docs/superpowers/plans/<name>.md` exists for plan-approved features
- If table is stale, update it before doing any work

---

## Design System — foundation layer model

DS components are not extracted after the fact. They are built first, in the same branch and
PR as the feature screens that consume them. Every Product feature ships DS + screens together.

### Prerequisite gate — DS tokens must exist before any Product BUILD

Before any Product feature enters BUILD, Claude checks whether tokens are defined in
`tailwind.config.js` and `docs/design-system.md`. Three states:

- **Tokens fully defined** → BUILD proceeds normally.
- **Tokens partially defined** → BUILD proceeds. Claude uses defined tokens where available,
  flags gaps inline with `// TOKEN-TBD: needs <value>` comments. A token-refinement pass
  happens at REVIEW on device — Baah decides values, Claude updates.
- **No tokens defined at all** → Claude flags to Baah before BUILD starts. Baah either
  defines a starter token set or explicitly says "use placeholders, we'll refine."

This allows a designer-builder to iterate on tokens while building — the system adapts,
not blocks.

### DS vs screen-specific — decision rule

Claude uses this decision tree to classify every component or style choice:

```
Is it a visual primitive (colour, typography, spacing, border, shadow)?
  YES → DS. Goes in mobile/src/components/ui/. Token-driven.

Is it a reusable UI pattern used or likely to be used in 2+ places?
  YES → DS.

Is it purely presentational with no knowledge of screen state or business data?
  YES → DS candidate. If also used in 1 place only, flag for Baah to confirm.

Does it contain screen-specific layout (flex positioning relative to siblings,
screen-level scroll behaviour, data-fetching hooks, navigation logic)?
  YES → Screen. Stays in the screen file.

Does it mix presentation AND screen logic?
  → Split: extract the presentational shell to DS, keep the data/logic wrapper in the screen.
```

DS classification is Claude's call — Baah sees the result at REVIEW on device, not as a
decision burden at planning time. If Claude cannot classify confidently, it makes the
safer call (DS) and notes it: "Treated X as DS — let me know at REVIEW if it should stay
screen-level."

### PLAN stage — DS component list

Every Product plan includes a DS section. Claude identifies which components the feature needs:

```markdown
## DS components

### Existing (no build work needed)
- `Button` — mobile/src/components/ui/Button.tsx
- `Card` — mobile/src/components/ui/Card.tsx

### New (Baah confirms these before build starts)
- `StatusChip` — label + colour variant, no business logic
- `InputBar` — text input with voice CTA slot
```

Baah approves the plan → DS component list is confirmed. BUILD does not start until both
the plan and the DS list are approved.

### BUILD stage — strict layer order

Claude builds in order. No screen is written before its DS dependencies exist.

```
BUILD
  1. DS layer  →  mobile/src/components/ui/
       Build each new DS component
       NativeWind only, typed + exported props, no business logic
       Add usage example to docs/design-system.md
       Commit: "feat(ds): add StatusChip, InputBar"

  2. Screen layer  →  mobile/src/app/ or mobile/src/screens/
       Import exclusively from mobile/src/components/ui/
       No inline primitive styles — all visual decisions live in DS
       Commit: "feat: build PersistentInputBar screen"
```

### Mid-build DS discovery protocol

If Claude identifies during BUILD that a component should be in DS but wasn't in the plan:

```
Is it purely additive (new component, no existing usage affected)?
  YES → Move it to DS layer immediately, no interruption needed.
        Note it in the build commit message: "feat(ds): add Avatar [discovered mid-build]"
        Update the plan doc with the addition.

Does adding it to DS require changing how an already-built screen imports things?
  YES → Finish the current screen with the inline component, flag at REVIEW:
        "Avatar should move to DS — recommend extracting before merge"
        Baah decides: extract now or park as a follow-up.
```

Claude never silently leaves a component inline because it was missed at PLAN.

### DS update threshold — when to ask vs. act

| Change type | Claude's action |
|---|---|
| New variant on existing component (new colour, size, state) | Autonomous — add it, document it |
| Prop addition (backwards-compatible) | Autonomous — add it, document it |
| Behaviour change that affects all usages (spacing, font weight, layout) | Surface to Baah: "This changes Button everywhere — confirm?" |
| Breaking change (removed prop, renamed export) | Always ask — grep all usages, show impact |

### REVIEW stage — DS compliance check

The code review pass (`requesting-code-review`) includes a DS compliance gate:

- [ ] Every visual primitive in screens imports from `mobile/src/components/ui/`
- [ ] No `StyleSheet.create()` anywhere in new or changed files
- [ ] New DS components have typed, exported props
- [ ] New DS components documented in `docs/design-system.md`
- [ ] No business logic inside DS components

Any violation blocks the PR — same weight as a failing test.

### DS update loop — feedback routing

When Baah reviews the UI and wants a change, Claude routes it based on what the change touches:

```
Feedback touches a DS component or token?
  YES → update mobile/src/components/ui/<Component>.tsx (+ docs/design-system.md)
        propagates automatically to every screen that uses it
        Commit: "fix(ds): update Button padding + weight"

  NO  → update the screen directly
        (screen-specific layout, positioning, screen-level logic,
         anything intentionally not in DS)
        Commit: "fix: adjust InputBar screen spacing"
```

Claude makes this routing call autonomously. If unclear whether something belongs in DS
or on the screen, Claude surfaces the question rather than guessing.

This applies whether the feedback comes during REVIEW, a future session, or a design
iteration with no active feature scope. DS components are always the source of truth
for the visual decisions they own — screens own everything else.

### Linear

DS components are a checklist within the Product feature issue (not separate issues).
The plan comment includes the confirmed DS component list. No separate DS sub-issues needed.

---

## Claude's autonomous decisions and responsibilities

### Autonomous — no need to ask
- Technical implementation within an approved plan
- DS component classification and placement
- Test strategy
- Platform API design within project constraints
- All workflow housekeeping: Active Work table, Linear updates, plan doc status,
  session re-orientation. Baah never touches these. Claude owns them fully.

### Always surfaces to Baah
- Decision is user-visible and wasn't covered in the approved plan
- Decision would change the data model
- Decision contradicts an approved plan
- Platform dependency will slip and block Product

### Translation rule — design language always
When presenting Platform work, plans, or technical decisions to Baah, Claude translates
to design-language equivalents. Engineering terms are explained by what they enable for
the UI, not by how they work internally.

Examples:
- "We're building `chatProcessor.ts`" → "We're building the coaching brain — this is
  what powers the four conversation modes (Mirror, Nudge, Challenge, Direct)"
- "Adding a `contextType` param to `/analyze`" → "We're teaching the API which screen
  the conversation started from, so Claude can tailor the coaching to that context"
- "Breaking change on Button" → "This update changes how Button looks everywhere it's
  used — not just this screen. Here's what changes: [before/after]"

Plan approval: Claude presents a plain-English build summary alongside the plan doc.
Baah approves the summary. The plan doc is the implementation reference, not the thing
Baah needs to evaluate line by line.

---

## Behind-the-scenes (BTS) learning notes

Claude adds short engineering context notes at moments where a non-obvious decision was
made. Not a lesson — just enough context to build intuition over time.

### When it fires

| Trigger | What Claude explains |
|---|---|
| Non-obvious architectural choice in a plan | Why this approach over the obvious alternative |
| Platform feature being scoped or built | What it does in the system in plain terms |
| DS compliance flag at REVIEW | Why the rule exists, not just the violation |
| Bug being fixed | What broke at the root, not just the fix |
| New API endpoint | How data flows from screen tap to DB and back |
| DS breaking vs. additive change | What "breaking" means with a concrete before/after |

### Format — visually set apart, skippable

```
Built the voice pipeline route.

> **BTS:** The route doesn't process audio itself — it hands the file to Whisper
> (OpenAI's transcription service) and waits for the text back. Think of it like
> sending a design file to a printer and waiting for the PDF. The backend is the courier.

Next: wiring the transcript to the journal processor.
```

### Depth is Baah-controlled
- Default: one to three lines
- Baah says "explain that more" → Claude goes deeper
- Baah says "skip BTS for now" → Claude drops it for the session
- Routine actions (git commit, file write) never get BTS notes

## Enforcement mechanism

**Option C (approved):** CLAUDE.md requires invoking `taisa-workflow` skill. The skill carries all detail. CLAUDE.md stays clean.

### CLAUDE.md additions

New section:

```markdown
## Workflow

Read docs/workflow.md before any feature work. Invoke the taisa-workflow skill
at the start of every scope, plan, build, or review task. This is not optional.

Gate points where Baah must approve: scope doc, plan, DS candidates, ship.
Claude makes autonomous calls on: technical implementation, DS candidate
identification, test strategy, Platform API design.
```

New row in "Where to Look" table:

```
| Follow the build workflow | docs/workflow.md + taisa-workflow skill |
```

### `taisa-workflow` skill contents

The skill is the single source of truth for how feature work runs. It contains:
1. Session-start reconciliation — verify Active Work table against git + disk before trusting it
2. Feature tier assessment — Quick / Standard / Full at task start
3. Stage identification — how to determine current stage from verified state
4. Stage → skill map with auto-trigger rules (scope-writer, design-handoff, writing-plans fire automatically — Baah never names them)
5. DESIGN two-path model — Figma vs. Visual Companion, different handoff criteria
6. Gate definitions — artifact + confirmation, intent-reading, single yes/no fallback
7. DS token prerequisite — three-state check (defined / partial / none), placeholder protocol
8. DS/screen decision tree — Claude's call, Baah sees result at REVIEW
9. DS foundation layer protocol — PLAN list, BUILD layer order, REVIEW compliance check
10. DS mid-build discovery protocol
11. DS update threshold — autonomous vs. surface to Baah
12. DS update loop — feedback routing (DS vs. screen)
13. BTS learning notes — triggers, format, depth control
14. Translation rule — design language for all technical communication
15. Housekeeping ownership — Claude owns Active Work table, Linear, plan status
16. Backlog capture to docs/backlog.md + batch sync to Linear
17. Backlog → pipeline transition
18. Skeleton pattern — shell-only build when Platform dependency is blocked
19. Linear update actions per transition (with project/team/label IDs)
20. Linear error handling — log, continue, catch-up list
21. Rollback protocol (QA failure → QA notes → back to BUILD)
22. Parked state handling

---

## Linear integration

**Workspace:** A Playing Field (APF)
**Project:** Taisa - career guide (`31b0d99c-6f74-4c9c-af2a-12e6e25aabe0`)
**Team ID:** `e95356d8-17f7-4700-bdfe-222782bea546`

### Status IDs (existing)

| Status | ID | Used for |
|---|---|---|
| Todo | `8092f145-a7b5-4e09-812e-1d3212fc1c7d` | Scope agreed → ready to plan |
| In Progress | `ad545d06-1ef1-4c5d-86c7-44e1e3724409` | Plan approved → in build |
| Done | `b2c07c6b-bf80-40d1-8e08-9c941b04f137` | Shipped |
| Canceled | `e2a4cb1f-daf0-4269-8acc-9b0fed9224f5` | Parked |

### Label IDs (existing — reuse)

| Label | ID | Used for |
|---|---|---|
| Feature | `a57ef5fa-88a5-42ae-9262-e4f1ae7f828c` | All Platform + Product issues |
| Design System | `5ab8ecc1-169f-4d2d-b855-7ca874b6453e` | Standalone DS update issues (feedback-driven, no feature scope) |

### Labels to create

| Label | Color | Used for |
|---|---|---|
| Platform | `#4EA7FC` | Platform track issues |
| Product | `#BB87FC` | Product track issues |

### Linear error handling

If any Linear MCP call fails during a gate transition:
1. Claude logs the failure in chat: "Linear update failed — [action]. Continuing."
2. Build proceeds — Linear state does not block code work
3. At end of session, Claude lists all failed Linear updates for manual catch-up
4. If failure was an issue creation (scope gate), Claude retries once before logging

---

## docs/workflow.md changes

The following sections need to be added or updated:

### Add: Active Work table (top of file, after header)

A lightweight table Claude reads at session start to orient itself:

```markdown
## Active work

| Feature | Track | Stage | Branch | Blocked on |
|---|---|---|---|---|
| *(empty until first feature enters pipeline)* | | | | |
```

This table is updated by Claude at every stage transition. It is the first thing Claude
reads at the start of any feature session.

### Update: Two Tracks section

Update to reflect that DS is a foundation layer inside Product BUILD, not a separate track.
Remove any language implying DS runs independently.

### Add: Rollback protocol

```markdown
### Build fails QA

1. Baah notes specific failures in chat
2. Claude creates a QA notes file: docs/features/<name>-qa-notes.md
3. Feature status reverts to In Build
4. Claude fixes and re-runs verification-before-completion before re-raising for QA
```

### Add: Parked status

Add "Parked" to status vocabulary — feature is mid-progress but deprioritised.
Roadmap entry stays, Linear → Canceled, branch preserved.

### Add: Design handoff minimum criteria

```markdown
### Design handoff (Product track only)

Build does not start until design handoff includes:
- All screens in the flow (happy path + key error states)
- Component states (default, active, disabled, empty)
- Which design system tokens apply
- Any interaction details that change build decisions (animation, gestures)
```

### Add: Platform dependency check + skeleton pattern

At PLAN stage, Claude verifies the Platform dependency status before writing a Product plan:

- Dependency in BUILD or later → plan proceeds normally
- Dependency not yet in BUILD → Claude flags the block. Baah decides:
  - **Wait** — Product plan is not written yet. Feature stays in SCOPE.
  - **Skeleton** — Product plan is written for shell-only build: DS components + screen
    layout wired to mock/static data. No real API calls. The plan notes explicitly which
    tasks are blocked until Platform ships. When Platform ships, Claude writes a follow-up
    plan for the wiring tasks only.

---

## Artifacts to create or change

| Artifact | Action |
|---|---|
| `docs/workflow.md` | Update — feature tiers, DS foundation layer, DS update loop, DESIGN two paths, Active Work table, backlog rule, rollback, parked, handoff checklist, skeleton pattern, platform dependency check |
| `docs/roadmap.md` | Update — add Active Work table at top |
| `docs/backlog.md` | Create — lightweight idea capture file (Claude-maintained) |
| `.claude/skills/taisa-workflow/SKILL.md` | Create — full orchestrator skill (all 22 items above) |
| `.claude/skills/scope-writer/SKILL.md` | Update — add tier assessment, backlog dedup check, auto-trigger chain (Platform → writing-plans, Product → design-handoff) |
| `.claude/skills/design-handoff/SKILL.md` | Update — add Visual Companion path, explicit forward-trigger to writing-plans, connection to DS foundation layer |
| `CLAUDE.md` | Update — add Workflow section + Where to Look row |
| Linear labels | Create — Platform (`#4EA7FC`), Product (`#BB87FC`) via MCP |
| Linear project description | Update — add one-line workflow summary |
