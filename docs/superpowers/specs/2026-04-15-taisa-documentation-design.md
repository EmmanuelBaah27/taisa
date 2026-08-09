# Taisa Documentation Design Spec

**Date:** 2026-04-15  
**Status:** Approved  
**Author:** Baah + Claude  
**Topic:** Developer documentation suite for the Taisa monorepo

---

## Context

The Taisa repo has five product design documents (`.docx`, artifacts #001–#005) that live in `docs/product/` and capture the "why" — product vision, agent persona, memory model, feature map, and information architecture.

What's missing is developer-facing documentation: the "what exists", "how it works", and "how to build the AI layer." The builder is working alone with zero prior knowledge of backend/AI wiring, so docs must be instructional, not just descriptive.

There is also a meaningful gap between what the product docs specify and what's currently built — this must be surfaced explicitly so neither the builder nor a future AI session conflates the two.

---

## Goals

1. Give the builder a clear, readable map of what exists in the codebase
2. Explain how the backend connects to Claude — in plain English with code pointers
3. Translate the Senior Self persona spec into actionable prompt engineering guidance
4. Surface the gap between product spec and current implementation
5. Make every doc useful to both the builder (human) and Claude (AI assistant in future sessions)

---

## What Is Not a Goal

- Recreating the product docs in markdown (they stay as `.docx`)
- Writing API docs for external consumers
- Documenting deferred features (voice capture, offline, auth)
- Being comprehensive for its own sake — every section earns its place

---

## Document Structure

### `README.md` — root level

**Purpose:** First thing anyone (or any AI session) reads. Orients without overwhelming.

**Contents:**
- What Taisa is — one paragraph drawn from product-brief-001
- The founding insight: "I wish I could shadow a senior version of myself while I work."
- Tech stack at a glance (React Native/Expo + NativeWind, Node/Express, SQLite, Claude claude-sonnet-4-6, OpenAI Whisper)
- How to run locally — fixed steps: kill port conflict, create `mobile/.env`, start backend, start mobile
- Doc map: one line per doc in `docs/`, when to open each

---

### `CLAUDE.md` — root level

**Purpose:** Loaded automatically at the start of every Claude Code session. Gives AI context to be useful immediately.

**Contents:**
- Project summary in 3 sentences
- The most important constraints an AI must not violate:
  - No auth in v1 — uses `deviceId` as `userId` via `x-user-id` header
  - SQLite only — no cloud DB, no migrations system yet
  - Mobile is Expo managed workflow — no bare React Native commands
  - `mobile/` is NOT in the root workspace — it has its own `node_modules`
- The gap warning: "Product docs describe a chat interface with four coaching modes. What's built is a voice journaling loop with async Claude analysis. Do not conflate them."
- Pointer to each doc in `docs/` with one-line descriptions

---

### `docs/architecture.md` — System overview

**Purpose:** Read this before touching any code. Explains how the three layers fit together and how Claude is wired in.

**Contents:**

**1. System layers**
How `mobile/`, `backend/`, and `shared/` relate. What lives where and why.

**2. Data flow — voice to insight**
The full path a journal entry takes:
- User records voice → `audio.ts` → POST `/transcribe` → OpenAI Whisper → transcript
- Transcript → POST `/analyze/:entryId` → `journalAgent.ts` → Claude → structured analysis → stored in DB
- Analysis surfaces in mobile via `journalStore.ts` → `entry/[id].tsx`

**3. How the backend calls Claude**
Plain English walkthrough of the code path, file by file:
- `routes/analyze.ts` receives the request and calls the agent
- `services/claude/journalAgent.ts` loads context from DB (profile, goals, recent themes, open action items) and calls the prompt builder
- `prompts/system/journalProcessor.ts` assembles the system prompt and user message
- `services/claude/client.ts` sends to Anthropic SDK and returns the parsed response
- Agent stores result back to DB via `db/connection.ts`

This section is the primary reference for understanding "how does a new AI feature get wired up."

**4. Tech decisions and why**
- SQLite: local-only, no network dependency, matches the memory model's v1 principle
- Zustand: lightweight store, no Redux overhead for a solo mobile app
- `ts-node-dev`: fast TypeScript iteration in dev without a build step
- `deviceId` as userId: MVP shortcut — no auth complexity in v1

**5. The pattern for adding a new AI feature**
Step-by-step: add a route → write an agent function → write a prompt builder → wire response to DB. With the `journalAgent` as the reference implementation.

---

### `docs/data-model.md` — Database and entities

**Purpose:** Open this when touching anything data-related. The source of truth for what's stored and how it maps to the product spec.

**Contents:**

**1. The 9 tables**
Each table: what it stores, key columns, relationships. No fluff.

```
users               — career profile, goals text, coaching prefs
journal_entries     — raw input + transcript + status (draft/processing/complete/error)
entry_analyses      — JSON blob of wins/challenges/decisions/actionItems/themes/coachNote
action_items        — denormalised from analyses, for easy querying + status tracking
goals               — active/achieved/dropped, with optional milestones
milestones          — sub-tasks per goal
performance_reviews — uploaded review text + structured feedback JSON
career_themes       — frequency counts per theme label
trajectory_snapshots — periodic Claude-generated career narrative
```

**2. Memory model mapping**
The product doc (artifact #003) defines six memory entities. Here's how they map to the actual DB:

| Product entity | DB table | Notes |
|---|---|---|
| Goal | `goals` | Direct match |
| Log Entry | `journal_entries` | Voice/text input, not just text |
| CV Moment | `action_items` (flagged) | No dedicated CV archive yet |
| Insight | `entry_analyses.coachNote` | Per-session, not aggregated |
| Pattern | `career_themes` + `trajectory_snapshots` | Partially implemented |
| Open Thread | `action_items` (open status) | Approximated, not a first-class entity |

The three memory layers (Immediate / Recent / Persistent) are not yet implemented as distinct DB structures. All data lives in the same SQLite file. This is a known gap to address in a future version.

**3. How context gets injected into Claude**
What the `journalAgent` loads before each Claude call and why each piece matters.

---

### `docs/api.md` — Backend routes

**Purpose:** Reference when adding or modifying an endpoint. Shows the pattern every route follows.

**Contents:**

**1. Route overview table**
All 9 route groups: path prefix, what it does, which Claude agent it calls (if any).

**2. Each route group**
For each group:
- Endpoints with method + path
- Request shape (body/params)
- Response shape
- Which agent/service it calls
- Any important behaviour notes

Route groups:
- `POST /api/v1/profile/init`, `GET/PUT /api/v1/profile`
- `GET/POST /api/v1/entries`, `GET/PUT /api/v1/entries/:id`
- `POST /api/v1/transcribe`
- `POST /api/v1/analyze/:entryId`, `GET /api/v1/analyze/:entryId`
- `GET/POST /api/v1/reviews`, `GET /api/v1/reviews/:id`
- `GET/POST /api/v1/goals`, `PATCH /api/v1/goals/:id`, `GET /api/v1/goals/:id/progress`
- `GET/PATCH /api/v1/action-items`, `PATCH /api/v1/action-items/:id`
- `GET /api/v1/trajectory`, `POST /api/v1/trajectory/generate`
- `POST /api/v1/notifications/checkin-message`

**3. How to add a new AI endpoint**
The exact steps following the existing pattern. References `docs/architecture.md` for the agent wiring detail.

---

### `docs/agent-persona.md` — The Senior Self: build guide

**Purpose:** The primary reference for all AI/backend work. Translates the product spec into what to actually build.

**Contents:**

**Part 1 — What the product spec says**
The four interaction modes from artifact #002-rev2, in plain terms:
- **Mirror** — receive and reflect, no guidance pushed
- **Nudge** — point toward an insight without stating it
- **Challenge** — name what needs to be named, directly
- **Direct Response** — only fires when Baah explicitly asks

The rules: one question per response, no defaulting to Challenge, no empty validation.

What the agent tracks over time: goals vs. behaviour, recurring avoidances, CV-worthy moments, patterns Baah misses.

**Part 2 — What's currently implemented**
What `journalProcessor.ts` actually does today:
- Extracts wins, challenges, decisions, action items, themes
- Generates a coach note per session
- Assesses goal progress with delta scores
- Flags CV-worthy moments

What it does NOT do:
- Does not select a mode — it always responds as if in a coaching/analysis role
- Does not have memory of prior sessions in the prompt (context is loaded but not surfaced as narrative)
- Does not support back-and-forth conversation — it's one-shot analysis, not chat
- Does not implement Mirror (it always outputs something)

**Part 3 — How to build the gap**

This section is the build guide for the AI layer. Written so the builder can work through it with Claude's help.

Step 1: **Add mode-selection logic to the system prompt**
How to instruct Claude to assess the input and choose a mode before responding. What the prompt structure looks like.

Step 2: **Inject prior session context as narrative**
How to load the Recent layer (last 2 weeks of summaries) and Persistent layer (goals, patterns, open threads) into the prompt in a way Claude can use. What format works best.

Step 3: **Implement the conversation interface**
What changes in the backend to support back-and-forth chat instead of one-shot analysis. New route shape, how session state is managed.

Step 4: **Implement the session summary**
How to trigger a summary generation on session close. What the summary should contain and where it gets stored.

Step 5: **Build the Persistent layer**
What needs to change in the DB to store goals, patterns, and open threads as first-class entities that persist across sessions and get loaded at session start.

Each step references the relevant existing files as starting points.

---

### `docs/design-system.md` — Visual language and component system

**Purpose:** The living reference for all UI work. Tells Claude exactly how to generate UI that matches the product's visual language. Tells a new team member what the design language is without opening Figma.

**Styling approach:** NativeWind (Tailwind CSS for React Native) — adopted from the start of the UI rebuild. Replaces the existing StyleSheet approach. Tokens from `theme.ts` are migrated into `tailwind.config.js` as custom values.

**Why NativeWind from day one:**
- Claude generates NativeWind UI faster and more consistently than raw StyleSheet
- Builder already thinks in Tailwind (Mande DS uses it — no mental translation)
- UI is being redesigned screen-by-screen from the start anyway — no migration debt
- Components become portable if a web surface is added later

**Build workflow:**
The design system is not designed upfront — it grows from real screens. The loop:
1. Design a screen
2. Build it with NativeWind
3. Extract reusable patterns into `mobile/src/components/ui/`
4. Update this doc with the new component

**Component structure:**
```
mobile/src/
  components/
    ui/           ← primitive components: Button, Card, Input, Text, Badge, Tag, Avatar
    layout/       ← structural: Screen, Stack, Row, Divider, Section
    features/     ← domain: EntryCard, GoalTag, CoachNote, ModeIndicator
```

Rule: if a pattern appears in two screens, it becomes a `ui/` component. Domain-specific components go in `features/`.

**Contents of the doc:**
- Color palette with usage rules (primary, accent, neutral, semantic)
- Typography scale (sizes, weights, when each is used)
- Spacing system (the scale, when to use which step)
- Component catalog: each component, what it's for, when to use it, what props it takes
- Rules for writing new components — so Claude follows the same patterns consistently
- NativeWind conventions for this project (class naming, custom values, dark mode strategy)

**On Storybook:**
Not now. The overhead of configuring it for native is too high for a solo builder. Revisit after 3–4 screens are rebuilt and a component library is taking shape — at that point, a visual catalog becomes genuinely useful, especially before bringing a team member on.

---

### `docs/v1-status.md` — What's built vs. what's spec'd

**Purpose:** Honest snapshot. Read this first when planning what to build next. Prevents building on assumptions.

**Contents:**

**1. What's fully wired and working**
The complete happy path: onboarding → voice recording → transcription → Claude analysis → stored insights → trajectory snapshot. With confidence rating per feature.

**2. What diverged from the product spec and why**
| Spec | Reality | Reason |
|---|---|---|
| Chat interface (Conversation surface) | One-shot analysis, no chat | Simpler to build first; chat is next |
| CV Archive surface | Action items list (partial approximation) | CV Moment not a first-class entity yet |
| Four-mode agent | Single coaching analysis mode | Modes require chat + session memory |
| Mirror / Nudge / Challenge / Direct | Not implemented | Depends on chat interface |
| Three memory layers | Single SQLite file, no layer distinction | V1 simplification from memory-model-003 |
| Today View (Today tab) | Home tab with stats + recent entries | Different framing, same purpose |
| Bottom nav: Today/Capture/Chat/Archive/Goals | Home/Record/Trajectory/Profile | Built before IA was finalised |

**3. Known gaps (not divergence — genuinely missing)**
- No auth
- No settings/edit profile screen
- No search or filter on entries/goals
- Tab icons are placeholder geometric shapes
- Notification times hard-coded (15:00 / 19:00)
- No offline support

**4. What to build next (priority order)**
1. Chat interface + four-mode agent (core product value, currently missing)
2. Persistent memory layer (required for modes to work well)
3. Session summary (closes the loop)
4. CV Archive as first-class surface
5. Settings/edit profile
6. Real tab icons

---

## Directory Layout After Implementation

```
taisa/
├── README.md
├── CLAUDE.md
├── SETUP.md                    (existing — keep)
├── docs/
│   ├── product/                (existing .docx artifacts — untouched)
│   ├── superpowers/specs/      (this spec)
│   ├── architecture.md
│   ├── data-model.md
│   ├── api.md
│   ├── agent-persona.md
│   ├── design-system.md
│   └── v1-status.md
├── backend/
├── mobile/
└── shared/
```

---

## Open Questions (resolved)

- Audience: humans + AI agents ✓
- Detail level: both high-level and low-level reference ✓
- AI knowledge gap: B (backend wiring) and C (Senior Self persona) — docs are instructional for both ✓
- Product docs stay as .docx: yes ✓
- Design system: included (see below) ✓
- NativeWind: adopted from day one of UI rebuild ✓
- Storybook: deferred until team grows ✓

---

## Implementation Notes

- Docs should be written in the order: `v1-status.md` first (establishes ground truth), then `architecture.md` (sets the mental model), then `data-model.md` and `api.md` (reference), then `agent-persona.md` (build guide), then `design-system.md` (visual language), then `README.md` and `CLAUDE.md` (entry points that link everything)
- `design-system.md` is a living doc — it starts minimal and grows as screens are designed and rebuilt
- NativeWind setup (`tailwind.config.js`, `mobile/.env` update, wrapper config) must happen before any UI screen is rebuilt
- Every code reference should include file path and relevant function name
- `agent-persona.md` Part 3 should be written so a future Claude session can use it as a step-by-step guide without needing this spec
