# Taisa Developer Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the full developer documentation suite for the Taisa monorepo — 8 files that give both the solo builder and future AI sessions a complete, accurate map of what exists, how it works, and how to build the AI layer.

**Architecture:** Documentation only — no code changes. Each doc is written from source (reading actual backend/mobile files), not from memory. NativeWind setup is a separate plan; `design-system.md` starts minimal and grows as screens are rebuilt.

**Tech Stack:** Markdown, sourced from TypeScript (backend/mobile), SQLite schema, and product `.docx` artifacts #001–#005.

---

## File Map

| File | Purpose |
|---|---|
| `docs/v1-status.md` | Ground truth: what's built, what diverged, what's missing |
| `docs/architecture.md` | System overview, data flow, how Claude is wired |
| `docs/data-model.md` | DB schema, entity relationships, memory model mapping |
| `docs/api.md` | All 9 route groups, request/response shapes, how to add a new endpoint |
| `docs/agent-persona.md` | Senior Self spec → current implementation → build guide |
| `docs/design-system.md` | Visual language, tokens, component structure, NativeWind roadmap |
| `README.md` | Project entry point (root level) |
| `CLAUDE.md` | AI session context (root level) |

**Writing order:** v1-status → architecture → data-model → api → agent-persona → design-system → README → CLAUDE.md

Each doc references earlier docs but does not duplicate them. Write in order.

---

## Task 1: `docs/v1-status.md`

**Files:**
- Create: `docs/v1-status.md`
- Read: `backend/src/routes/` (all files), `mobile/app/`, `mobile/src/stores/`, `backend/src/db/schema.sql`

- [ ] **Step 1: Read source files to verify current state**

```bash
ls backend/src/routes/
ls mobile/app/
ls mobile/src/stores/
```

Expected output:
```
# routes:
actionItems.ts  analyze.ts  entries.ts  goals.ts  notifications.ts
profile.ts  reviews.ts  transcribe.ts  trajectory.ts

# app:
(tabs)/  entry/  onboarding/

# stores:
careerStore.ts  journalStore.ts  uiStore.ts
```

- [ ] **Step 2: Write `docs/v1-status.md`**

```markdown
# V1 Status — What's Built vs. What's Spec'd

> Read this before planning what to build next. Updated as features ship.
> Last updated: 2026-04-15

---

## What's Fully Wired and Working

The core loop is functional end-to-end:

| Feature | Status | Notes |
|---|---|---|
| Onboarding (3-step) | ✅ Built | Role, goals, coaching prefs → stored in `users` table |
| Voice recording | ✅ Built | `expo-av`, high quality, haptic feedback |
| Transcription | ✅ Built | OpenAI Whisper via `/api/v1/transcribe` |
| Journal entry creation | ✅ Built | POST `/api/v1/entries`, status: draft → processing → complete |
| Claude analysis | ✅ Built | `journalAgent.ts` → `journalProcessor.ts` prompt → structured JSON |
| Action item extraction | ✅ Built | Denormalised to `action_items` table, status tracking |
| Goal management | ✅ Built | Manual + AI-suggested goals, milestones, progress % |
| Trajectory snapshots | ✅ Built | POST `/api/v1/trajectory/generate`, requires 3+ entries |
| Performance review upload | ✅ Built | Text input → Claude extracts feedback + suggests goals |
| Daily notifications | ✅ Built | Personalized message from Claude, scheduled via Expo Notifications |
| Data export | ✅ Built | Share journal as JSON via native Share API |

---

## What Diverged From the Product Spec and Why

The product docs (artifacts #001–#005) describe a slightly different product than what was built. Neither is wrong — the build made pragmatic V1 decisions.

| Spec (artifacts #001–#005) | Reality (codebase) | Reason |
|---|---|---|
| Chat interface ("Conversation" surface) | One-shot voice analysis — no back-and-forth | Simpler first; chat is the next major build |
| CV Archive surface (artifact #004) | Action items list (partial approximation) | CV Moment not a first-class entity yet |
| Four-mode agent: Mirror / Nudge / Challenge / Direct | Single coaching analysis mode | Modes require chat + session memory; not yet implemented |
| Three memory layers: Immediate / Recent / Persistent | Single SQLite file, no layer distinction | V1 simplification from memory-model-003 |
| "Today View" (today's captures + open threads) | "Home" tab (stats card + recent entries) | Different framing, same intent |
| Bottom nav: Today / Capture / Chat / Archive / Goals | Home / Record / Trajectory / Profile | Built before IA (artifact #005) was finalised |
| Open Thread as first-class entity | `action_items` with `open` status | Approximated — good enough for V1 |

---

## Known Gaps (Not Divergence — Genuinely Missing)

These were never built, not re-scoped:

- **No auth** — uses `deviceId` as `userId` via `x-user-id` header. Single user only. No login/logout.
- **No settings / edit profile screen** — profile is read-only after onboarding. Updates only via API.
- **No search or filter** — entries, goals, and action items cannot be filtered by date, theme, or status in the UI.
- **Tab icons are placeholders** — geometric shapes (○ ● △ □) in `(tabs)/_layout.tsx`. No real icons installed.
- **Notification times hard-coded** — 15:00 and 19:00 in `notifications.ts`. No user preference UI.
- **No offline support** — all stores call the API directly; no local caching or queue.
- **No milestone detail UI** — milestones exist in the DB and API but are not browsable in the app.

---

## What to Build Next (Priority Order)

1. **Chat interface + four-mode agent** — the core product value described in the spec. Currently missing entirely. Requires new backend routes and a new mobile screen.
2. **Persistent memory layer** — goals, patterns, and open threads as properly structured context injected at session start. Required for the four modes to work well.
3. **Session summary** — auto-generated after closing a chat session. Closes the loop.
4. **CV Archive as a first-class surface** — CV Moment entity, dedicated screen, copy-to-clipboard.
5. **Settings / edit profile** — basic UX hygiene. Needed before sharing with anyone else.
6. **Real tab icons** — install `lucide-react-native`, replace placeholders in `(tabs)/_layout.tsx`.
7. **NativeWind migration** — prerequisite for UI rebuild. Run this plan before redesigning any screen: `docs/superpowers/plans/nativewind-setup.md` (to be written).
```

- [ ] **Step 3: Verify — check a sample of claims against actual files**

```bash
# Verify tab icon claim
grep -n "symbol\|○\|●\|△\|□\|placeholder" mobile/app/\(tabs\)/_layout.tsx | head -10

# Verify notification times claim
grep -n "15:00\|19:00" mobile/src/services/notifications.ts
```

Expected: finds the placeholder symbols and hardcoded times confirming the doc is accurate.

- [ ] **Step 4: Commit**

```bash
git add docs/v1-status.md
git commit -m "docs: add v1-status — built vs spec'd ground truth"
```

---

## Task 2: `docs/architecture.md`

**Files:**
- Create: `docs/architecture.md`
- Read: `backend/src/index.ts`, `backend/src/services/claude/client.ts`, `backend/src/services/claude/journalAgent.ts`, `backend/src/prompts/system/journalProcessor.ts`, `mobile/src/services/api.ts`

- [ ] **Step 1: Read the key source files**

```bash
cat backend/src/index.ts
cat backend/src/services/claude/client.ts
cat backend/src/services/claude/journalAgent.ts | head -80
cat mobile/src/services/api.ts
```

Read these. Note: the Claude client uses `claude-sonnet-4-6`. The agent loads profile, goals, recent themes, and open action items before calling Claude.

- [ ] **Step 2: Write `docs/architecture.md`**

```markdown
# Architecture

> Read this before touching any code. Explains how the three layers fit together and how Claude is wired in.

---

## System Layers

```
taisa/
├── mobile/          React Native app (Expo managed workflow)
│   ├── app/         Expo Router screens (file-based routing)
│   └── src/         Components, hooks, services, stores, constants
├── backend/         Node.js + Express API
│   └── src/
│       ├── routes/           9 route groups
│       ├── services/claude/  AI agents (journalAgent, performanceReviewAgent)
│       ├── prompts/system/   Prompt builders (journalProcessor, trajectoryAnalyst, performanceReviewAnalyst)
│       └── db/               SQLite connection + schema
└── shared/          TypeScript types shared between backend and mobile
    └── types/       api.ts, journal.ts, career.ts, goals.ts
```

**Important:** `mobile/` is NOT in the root npm workspace. It has its own `node_modules` and must be run separately. The root workspace covers `backend/` and `shared/` only.

---

## Data Flow — Voice to Insight

The full path a journal entry takes, from tap to stored insight:

```
1. User taps record button
   → mobile/src/hooks/useVoiceRecorder.ts
   → mobile/src/services/audio.ts (expo-av, HIGH_QUALITY preset)

2. User stops recording
   → audio file saved locally
   → mobile/src/services/transcription.ts
   → POST /api/v1/transcribe (multipart/form-data)
   → backend/src/routes/transcribe.ts
   → OpenAI Whisper API (model: whisper-1)
   → returns { transcript: string }

3. Entry created with transcript
   → POST /api/v1/entries (body: { rawTranscript, inputType: 'voice' })
   → backend/src/routes/entries.ts
   → stored in journal_entries table, status: 'draft'

4. Analysis triggered
   → POST /api/v1/analyze/:entryId
   → backend/src/routes/analyze.ts
   → calls journalAgent.analyzeEntry(entryId, userId)

5. Agent assembles context
   → backend/src/services/claude/journalAgent.ts
   → loads from DB: user profile, active goals, open action items, recent themes
   → calls buildJournalProcessorSystem() + buildJournalProcessorUser()
   → backend/src/prompts/system/journalProcessor.ts

6. Claude call
   → backend/src/services/claude/client.ts
   → Anthropic SDK, model: claude-sonnet-4-6
   → callClaudeJson() — parses JSON response with fallback

7. Results stored
   → entry_analyses table (summary, wins, challenges, coach_note, etc.)
   → action_items table (denormalised from analysis)
   → career_themes table (frequency counts updated)
   → goals table (progress_percent updated via goal_assessments)
   → journal_entries.status → 'complete'

8. Mobile displays result
   → mobile/src/stores/journalStore.ts (Zustand)
   → fetchEntries() polls or is called after analyzeEntry()
   → mobile/app/entry/[id].tsx renders the full analysis
```

---

## How the Backend Calls Claude

Every AI feature in the backend follows the same three-layer pattern. Understanding this pattern means you can add a new AI feature without guessing.

### Layer 1 — Route (`backend/src/routes/`)
Receives the HTTP request, validates it, calls the agent, returns the response. Does not contain any prompt logic.

```typescript
// Example: routes/analyze.ts
router.post('/:entryId', async (req, res) => {
  const { entryId } = req.params;
  const userId = req.headers['x-user-id'] as string;
  await journalAgent.analyzeEntry(entryId, userId);  // delegates to agent
  res.json({ success: true });
});
```

### Layer 2 — Agent (`backend/src/services/claude/`)
Loads context from the database, assembles the prompt, calls the Claude client, and persists the result. This is where the "thinking" about what to pass to Claude happens.

```typescript
// Pattern in journalAgent.ts
export async function analyzeEntry(entryId: string, userId: string) {
  // 1. Load context from DB
  const profile = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
  const goals = db.prepare('SELECT * FROM goals WHERE user_id = ? AND status = "active"').all(userId);
  const openItems = db.prepare('SELECT * FROM action_items WHERE user_id = ? AND status = "open"').all(userId);
  const themes = db.prepare('SELECT * FROM career_themes WHERE user_id = ?').all(userId);

  // 2. Build prompt
  const system = buildJournalProcessorSystem(profile, goals, openItems, themes);
  const user = buildJournalProcessorUser(entry);

  // 3. Call Claude
  const result = await callClaudeJson(system, user);

  // 4. Persist result
  db.prepare('INSERT INTO entry_analyses ...').run(result);
}
```

### Layer 3 — Prompt Builder (`backend/src/prompts/system/`)
Pure functions that take data and return prompt strings. No database calls, no Claude calls. Easy to read, test, and modify.

```typescript
// Pattern in journalProcessor.ts
export function buildJournalProcessorSystem(profile, goals, openItems, themes): string {
  return `You are a senior career coach...
  
  User profile: ${profile.current_role} at ${profile.current_company}
  Active goals: ${goals.map(g => g.title).join(', ')}
  ...`;
}
```

### The Claude client (`backend/src/services/claude/client.ts`)
Two functions you'll use:
- `callClaude(system, user)` → returns raw string response
- `callClaudeJson(system, user)` → parses JSON from response, with fallback extraction

Both use `claude-sonnet-4-6` with a 4096 token limit.

---

## How to Add a New AI Feature

Follow this pattern exactly. Use `journalAgent.ts` as your reference implementation.

1. **Add a route** in `backend/src/routes/yourFeature.ts` — receive request, call agent, return response
2. **Mount the route** in `backend/src/index.ts` — `app.use('/api/v1/yourFeature', yourFeatureRouter)`
3. **Write the agent** in `backend/src/services/claude/yourFeatureAgent.ts` — load context from DB, call prompt builder, call `callClaudeJson`, persist result
4. **Write the prompt builder** in `backend/src/prompts/system/yourFeaturePrompt.ts` — pure function, takes data, returns system + user prompt strings
5. **Add DB writes** in the agent — define what gets stored and where

See `docs/api.md` for the request/response patterns. See `docs/agent-persona.md` for the Senior Self prompt engineering guide.

---

## Tech Decisions and Why

| Decision | Why |
|---|---|
| SQLite (not Postgres/Mongo) | Local-only in v1. No network dependency. Matches memory-model-003's principle: "validate the model with real use before adding infrastructure." |
| `ts-node-dev` | Hot-reload TypeScript in dev without a build step. No compiled output needed during development. |
| `deviceId` as `userId` | MVP shortcut. Single user, no login screen. The `x-user-id` header is set automatically by `mobile/src/services/api.ts` via an Axios interceptor. |
| Zustand (not Redux) | Lightweight global state for a solo mobile app. Three stores: `journalStore`, `careerStore`, `uiStore`. |
| Expo managed workflow | Faster iteration, no native build tooling required. Trade-off: some native audio features require a dev build (not Expo Go). |
| `callClaudeJson` with fallback | Claude sometimes wraps JSON in markdown code fences. The fallback parser strips `` ```json `` wrappers before parsing. |
```

- [ ] **Step 3: Verify — confirm model name and key file references exist**

```bash
grep -r "claude-sonnet" backend/src/services/claude/client.ts
grep -n "x-user-id" mobile/src/services/api.ts
grep -n "callClaudeJson\|callClaude" backend/src/services/claude/client.ts | head -5
```

Expected: finds `claude-sonnet-4-6`, the interceptor, and both exported functions.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md
git commit -m "docs: add architecture — system layers, data flow, Claude wiring pattern"
```

---

## Task 3: `docs/data-model.md`

**Files:**
- Create: `docs/data-model.md`
- Read: `backend/src/db/schema.sql`, `shared/types/`

- [ ] **Step 1: Read shared types**

```bash
cat shared/types/journal.ts
cat shared/types/career.ts
cat shared/types/goals.ts
```

Note the TypeScript shapes that correspond to DB rows.

- [ ] **Step 2: Write `docs/data-model.md`**

```markdown
# Data Model

> Open this when touching anything data-related. Source of truth for what's stored and how it maps to the product spec.

---

## The 9 Tables

### `users`
Career profile. One row per device (v1 has no auth — `id` is the device UUID).

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | Device UUID |
| `current_role`, `current_company`, `industry` | TEXT | Career context from onboarding |
| `years_of_experience` | INTEGER | |
| `career_stage` | TEXT | `junior` / `mid` / `senior` / `lead` |
| `short_term_goal`, `long_term_goal` | TEXT | Free text from onboarding |
| `coaching_style` | TEXT | `direct` / `supportive` / `challenging` |
| `accountability_level` | TEXT | `light` / `moderate` / `high` |
| `reminder_times` | TEXT | JSON array, default `["15:00","19:00"]` |
| `dominant_themes` | TEXT | JSON array, updated by trajectory agent |
| `growth_trajectory` | TEXT | `accelerating` / `steady` / `stalling` |
| `open_action_item_count`, `total_entry_count` | INTEGER | Denormalised counters |

---

### `journal_entries`
The raw input — voice or text — before and after analysis.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `user_id` | TEXT FK → users | |
| `input_type` | TEXT | `voice` / `text` |
| `raw_transcript` | TEXT | From Whisper or direct input |
| `edited_transcript` | TEXT | User-edited version (optional) |
| `audio_duration_seconds` | REAL | |
| `status` | TEXT | `draft` → `processing` → `complete` / `error` |
| `analysis_id` | TEXT | FK → entry_analyses (set after analysis) |

---

### `entry_analyses`
The Claude output for a journal entry. Stored as JSON columns.

| Column | Type | Notes |
|---|---|---|
| `entry_id` | TEXT FK → journal_entries | |
| `summary` | TEXT | 1–2 sentence summary |
| `sentiment` | TEXT | `very_positive` / `positive` / `neutral` / `challenging` / `difficult` |
| `energy_level` | INTEGER | 1–5 |
| `momentum_signal` | TEXT | `accelerating` / `steady` / `stalling` / `recovering` |
| `wins` | TEXT | JSON array of `{ title, impact }` |
| `challenges` | TEXT | JSON array of `{ title, context }` |
| `decisions` | TEXT | JSON array of `{ title, rationale }` |
| `action_items` | TEXT | JSON array (also denormalised to `action_items` table) |
| `themes` | TEXT | JSON array of strings |
| `coach_note` | TEXT | The agent's main observation — shown prominently in UI |
| `goal_assessments` | TEXT | JSON array of `{ goalId, progressDelta, evidence }` |
| `pattern_flags` | TEXT | JSON array — recurring patterns the agent noticed |
| `accountability_callouts` | TEXT | JSON array — follow-up items from prior sessions |

---

### `action_items`
Denormalised from `entry_analyses` for efficient querying across entries.

| Column | Type | Notes |
|---|---|---|
| `source_entry_id` | TEXT FK → journal_entries | |
| `title` | TEXT | The action item text |
| `priority` | TEXT | `low` / `medium` / `high` |
| `status` | TEXT | `open` / `complete` |
| `due_context` | TEXT | Optional — "by end of sprint", "this week" |

---

### `goals`
Career goals. Created manually or suggested by Claude after a performance review.

| Column | Type | Notes |
|---|---|---|
| `source_review_id` | TEXT FK → performance_reviews | NULL if manually created |
| `suggested_by_ai` | INTEGER | 0 / 1 |
| `priority` | TEXT | `low` / `medium` / `high` |
| `status` | TEXT | `active` / `achieved` / `dropped` |
| `progress_percent` | INTEGER | 0–100, updated by journal analysis |
| `related_themes` | TEXT | JSON array of theme labels |
| `target_date` | TEXT | Optional ISO date |

---

### `milestones`
Sub-tasks for a goal. Not yet surfaced in the mobile UI.

| Column | Type | Notes |
|---|---|---|
| `goal_id` | TEXT FK → goals | |
| `status` | TEXT | `pending` / `complete` |
| `evidence_entry_ids` | TEXT | JSON array of entry IDs that count as evidence |

---

### `performance_reviews`
Uploaded review text + Claude's structured extraction.

| Column | Type | Notes |
|---|---|---|
| `reviewer_context` | TEXT | Who gave the review, what role |
| `raw_text` | TEXT | The pasted review |
| `extracted_feedback` | TEXT | JSON: `{ strengths, growthAreas, concerns }` |
| `suggested_goals` | TEXT | JSON array of goal objects with milestones |

---

### `career_themes`
Aggregate frequency of themes across all journal entries.

| Column | Type | Notes |
|---|---|---|
| `label` | TEXT | e.g. "stakeholder alignment", "design strategy" |
| `count` | INTEGER | Incremented each time theme appears in an analysis |
| `trend` | TEXT | `rising` / `stable` / `fading` |
| `UNIQUE(user_id, label)` | | One row per theme per user |

---

### `trajectory_snapshots`
Periodic Claude-generated career narrative. Requires 3+ entries.

| Column | Type | Notes |
|---|---|---|
| `period_start`, `period_end` | TEXT | ISO dates the snapshot covers |
| `narrative_summary` | TEXT | The career arc story |
| `key_themes` | TEXT | JSON array |
| `momentum_history` | TEXT | JSON array of `{ date, signal }` |
| `growth_observations` | TEXT | JSON array of specific growth signals |
| `suggested_focus_areas` | TEXT | JSON array |
| `goal_progress_summaries` | TEXT | JSON array |

---

## Memory Model Mapping

The product spec (artifact #003) defines six memory entities. Here's how they map to the actual DB:

| Product entity | DB table(s) | Status | Gap |
|---|---|---|---|
| Goal | `goals` | ✅ Direct match | — |
| Log Entry | `journal_entries` | ✅ Voice/text, not just text | Richer than spec'd |
| CV Moment | `action_items` (high priority, open) | ⚠️ Approximated | No dedicated CV archive; no draft bullet generation |
| Insight | `entry_analyses.coach_note` | ⚠️ Partial | Per-session only; not aggregated across sessions |
| Pattern | `career_themes` + `trajectory_snapshots` | ⚠️ Partial | Themes tracked, but not surfaced as named patterns |
| Open Thread | `action_items` (open status) | ⚠️ Approximated | Not a first-class entity; no explicit "thread" concept |

**The three memory layers** (Immediate / Recent / Persistent) from artifact #003 are **not implemented** as distinct DB structures. All data lives in the same SQLite file. The `journalAgent` loads a flat context object on each call — there is no rolling 2-week summary or persistent layer initialisation.

This is the primary architectural gap to close when building the chat interface. See `docs/agent-persona.md`.

---

## How Context Gets Injected Into Claude

Before every `callClaudeJson` call, `journalAgent.ts` loads:

```
profile         → user role, company, coaching style, goals text
active_goals    → all goals with status = 'active'
open_items      → all action_items with status = 'open' (max 10)
themes          → all career_themes, ordered by count DESC (max 10)
entry           → the journal_entries row being analysed
```

This context is formatted into the system prompt by `buildJournalProcessorSystem()`. The agent does not load prior session transcripts or analyses — only the aggregated artifacts (themes, goals, open items).
```

- [ ] **Step 3: Verify — check column names against schema**

```bash
grep "coach_note\|momentum_signal\|growth_trajectory" backend/src/db/schema.sql
```

Expected: finds all three column names confirming doc accuracy.

- [ ] **Step 4: Commit**

```bash
git add docs/data-model.md
git commit -m "docs: add data-model — 9 tables, memory model mapping, context injection"
```

---

## Task 4: `docs/api.md`

**Files:**
- Create: `docs/api.md`
- Read: `backend/src/routes/profile.ts`, `backend/src/routes/entries.ts`, `backend/src/routes/analyze.ts`, `backend/src/routes/goals.ts`, `backend/src/routes/trajectory.ts`

- [ ] **Step 1: Read the route files**

```bash
cat backend/src/routes/profile.ts
cat backend/src/routes/entries.ts
cat backend/src/routes/analyze.ts
cat backend/src/routes/goals.ts
cat backend/src/routes/trajectory.ts
cat backend/src/routes/reviews.ts
cat backend/src/routes/actionItems.ts
cat backend/src/routes/transcribe.ts
cat backend/src/routes/notifications.ts
```

Read carefully. Note the exact request body shapes and response shapes for each endpoint.

- [ ] **Step 2: Write `docs/api.md`**

```markdown
# API Reference

> Reference when adding or modifying an endpoint. All routes are prefixed `/api/v1`.
> Auth: pass `x-user-id` header on every request. Set automatically by `mobile/src/services/api.ts` via Axios interceptor.

---

## Route Overview

| Route group | Prefix | Claude agent |
|---|---|---|
| Profile | `/profile` | None |
| Entries | `/entries` | None |
| Transcribe | `/transcribe` | OpenAI Whisper |
| Analyze | `/analyze` | `journalAgent` |
| Reviews | `/reviews` | `performanceReviewAgent` |
| Goals | `/goals` | None (reads AI suggestions from reviews) |
| Action Items | `/action-items` | None |
| Trajectory | `/trajectory` | `trajectoryAnalyst` prompt |
| Notifications | `/notifications` | `trajectoryAnalyst` (check-in message) |

---

## `/profile`

### `POST /profile/init`
Creates a new user. Called once on first app launch.

**Body:**
```json
{
  "userId": "string (device UUID)",
  "currentRole": "string",
  "currentCompany": "string",
  "industry": "string",
  "yearsOfExperience": 3,
  "careerStage": "mid",
  "shortTermGoal": "string",
  "longTermGoal": "string",
  "currentFocusArea": "string",
  "coachingStyle": "direct",
  "accountabilityLevel": "moderate"
}
```

**Response:** `{ success: true, userId: string }`

### `GET /profile`
Returns the current user's full profile.

**Response:** Full `users` row as JSON.

### `PUT /profile`
Updates profile fields. Partial updates accepted.

**Body:** Any subset of profile fields.

**Response:** `{ success: true }`

---

## `/entries`

### `GET /entries`
Returns all journal entries for the user, most recent first.

**Response:** `{ entries: JournalEntry[] }`

### `POST /entries`
Creates a new entry.

**Body:**
```json
{
  "rawTranscript": "string",
  "inputType": "voice | text",
  "audioDurationSeconds": 45.2
}
```

**Response:** `{ entry: JournalEntry }` — status will be `draft`.

### `GET /entries/:id`
Returns a single entry with its analysis (if complete).

**Response:** `{ entry: JournalEntry, analysis: EntryAnalysis | null }`

### `PUT /entries/:id`
Updates the edited transcript.

**Body:** `{ editedTranscript: string }`

**Response:** `{ success: true }`

---

## `/transcribe`

### `POST /transcribe`
Transcribes an audio file using OpenAI Whisper.

**Body:** `multipart/form-data`, field name `audio`, audio file (m4a/wav).

**Response:** `{ transcript: string }`

---

## `/analyze`

### `POST /analyze/:entryId`
Triggers Claude analysis for an entry. Sets status to `processing`, then `complete` or `error`.

**No body required.**

**Response:** `{ success: true }`

Note: analysis is async. Poll `GET /entries/:id` or re-fetch after a delay to get results.

### `GET /analyze/:entryId`
Returns the analysis for an entry.

**Response:** `{ analysis: EntryAnalysis }` or `{ analysis: null }` if not yet complete.

---

## `/reviews`

### `POST /reviews`
Uploads a performance review for Claude to analyse.

**Body:**
```json
{
  "rawText": "string — full review text",
  "reviewerContext": "string — e.g. 'Q4 review from direct manager'"
}
```

**Response:** `{ review: PerformanceReview }` — includes `suggestedGoals` array.

### `GET /reviews`
Returns all reviews for the user.

**Response:** `{ reviews: PerformanceReview[] }`

### `GET /reviews/:id`
Returns a single review.

**Response:** `{ review: PerformanceReview }`

---

## `/goals`

### `GET /goals`
Returns all goals with their milestones.

**Response:** `{ goals: Goal[] }` — each goal includes `milestones` array.

### `POST /goals`
Creates a new goal manually.

**Body:**
```json
{
  "title": "string",
  "description": "string",
  "priority": "low | medium | high",
  "targetDate": "2026-06-30"
}
```

**Response:** `{ goal: Goal }`

### `PATCH /goals/:id`
Updates a goal's status or other fields.

**Body:** `{ status: "active | achieved | dropped" }` or any goal fields.

**Response:** `{ success: true }`

### `GET /goals/:id/progress`
Returns Claude-generated progress notes for a goal based on recent journal entries.

**Response:** `{ progress: string, relatedEntries: JournalEntry[] }`

---

## `/action-items`

### `GET /action-items`
Returns action items, optionally filtered by status.

**Query params:** `?status=open` or `?status=complete`

**Response:** `{ actionItems: ActionItem[] }`

### `PATCH /action-items/:id`
Updates an action item's status.

**Body:** `{ status: "open | complete" }`

**Response:** `{ success: true }`

---

## `/trajectory`

### `GET /trajectory`
Returns the most recent trajectory snapshot.

**Response:** `{ snapshot: TrajectorySnapshot | null }`

### `POST /trajectory/generate`
Triggers Claude to generate a new trajectory snapshot from all journal entries. Requires 3+ entries.

**No body required.**

**Response:** `{ snapshot: TrajectorySnapshot }`

---

## `/notifications`

### `POST /notifications/checkin-message`
Returns a personalised notification message from Claude based on recent activity.

**No body required.**

**Response:** `{ message: string }` — short, personal prompt to open the app and log something.

---

## How to Add a New AI Endpoint

Follow these steps in order. Use `analyze` + `journalAgent` as your reference.

1. **Create the route file**: `backend/src/routes/yourFeature.ts`
   - Mount `router.post('/', handler)` or `router.get('/', handler)`
   - Validate `x-user-id` header
   - Call your agent function
   - Return `{ success: true }` or the result object

2. **Mount in `backend/src/index.ts`**:
   ```typescript
   import yourFeatureRouter from './routes/yourFeature';
   app.use('/api/v1/yourFeature', yourFeatureRouter);
   ```

3. **Create the agent**: `backend/src/services/claude/yourFeatureAgent.ts`
   - Load context from DB
   - Call prompt builder
   - Call `callClaudeJson(system, user)`
   - Write result to DB

4. **Create the prompt builder**: `backend/src/prompts/system/yourFeaturePrompt.ts`
   - Export `buildYourFeatureSystem(context): string`
   - Export `buildYourFeatureUser(input): string`
   - Pure functions — no DB calls, no Claude calls

5. **Add the mobile service call** in `mobile/src/services/api.ts` or a new service file.

See `docs/architecture.md` for the full annotated walkthrough of this pattern.
```

- [ ] **Step 3: Verify — spot-check two endpoint paths**

```bash
grep -n "router\.\(get\|post\|patch\|put\)" backend/src/routes/trajectory.ts | head -10
grep -n "router\.\(get\|post\|patch\|put\)" backend/src/routes/goals.ts | head -10
```

Expected: confirms the methods and paths documented are accurate.

- [ ] **Step 4: Commit**

```bash
git add docs/api.md
git commit -m "docs: add api reference — 9 route groups, request/response shapes, how to add AI endpoint"
```

---

## Task 5: `docs/agent-persona.md`

**Files:**
- Create: `docs/agent-persona.md`
- Read: `backend/src/prompts/system/journalProcessor.ts`, `backend/src/services/claude/journalAgent.ts`

- [ ] **Step 1: Read the current prompt implementation**

```bash
cat backend/src/prompts/system/journalProcessor.ts
```

Read the full file. Note: what instructions are given to Claude, what context is injected, and what JSON shape is expected back.

- [ ] **Step 2: Write `docs/agent-persona.md`**

```markdown
# The Senior Self — Agent Persona & Build Guide

> The primary reference for all AI work. Read this before touching any prompt or adding any new AI feature.
> Source: Product artifact #002-rev2 (agent-persona-002-rev2.docx) + current implementation audit.

---

## Part 1 — What the Product Spec Says

The agent is "The Senior Self" — a version of Baah that has already become what Baah is working toward. 8–10 years of earned perspective as a senior designer. It has navigated the exact transitions Baah is navigating.

It is not a coach, a cheerleader, or a productivity tool. It is a thinking partner with a point of view.

### The Four Interaction Modes

Every response falls into exactly one mode. The mode is chosen by the agent based on what the situation calls for.

**Mode 1 — Mirror**
Fires when: Baah shares something and there is no material gap or risk to surface. Also fires for genuine earned acknowledgment.
- ✅ Confirm input received, reflect back without editorialising, one open question max
- ❌ Insert unprompted guidance, turn acknowledgment into a coaching moment, give empty validation

**Mode 2 — Nudge**
Fires when: there is an insight Baah can likely reach himself. Point toward it, don't state it.
- ✅ One question pointing toward the insight, a reframe without prescribing, "there's something worth exploring here"
- ❌ State the insight (that's Challenge), follow up immediately if Baah doesn't engage, frame it as a next step

**Mode 3 — Challenge**
Fires when: there is a pattern, a conflict with stated goals, or a risky assumption Baah won't surface alone.
- ✅ State the observation directly, name patterns across entries ("this is the third time"), flag goal conflicts
- ❌ Soften into a question to avoid discomfort, issue multiple challenges, repeat a challenge already acknowledged

**Mode 4 — Direct Response**
Fires when: Baah explicitly asks "what should I do" or "what do you think."
- ✅ Clear direct answer, recommendation with reasoning, honest "not enough context to answer" when true
- ❌ Pad with caveats, give a non-answer, use this mode without an explicit ask

### Hard Limits (All Modes)
- One question per response maximum
- Never default to Challenge — it is earned, not the baseline
- Never validate without a specific basis
- Never repeat a challenge Baah has consciously set aside

### What the Agent Tracks Over Time
- Stated goals vs. actual behaviour
- Recurring avoidances or hesitations
- CV-worthy moments from daily work
- Skills being used vs. skills being developed
- Patterns in what Baah notices and what he misses

---

## Part 2 — What's Currently Implemented

The current implementation (`backend/src/prompts/system/journalProcessor.ts`) does **not** implement the Senior Self persona. It is a structured analysis engine.

### What it does:
- Extracts wins, challenges, decisions, action items from the transcript
- Generates a `coach_note` — a single observation from the session
- Assesses goal progress with `progressDelta` scores (−2 to +2)
- Flags CV-worthy moments
- Identifies themes and tags them

### What it does NOT do:
- Does not select a mode (Mirror / Nudge / Challenge / Direct) — always responds as an analyst
- Does not have memory of prior sessions in the prompt — context loaded is flat (profile, goals, themes), not narrative
- Does not support back-and-forth conversation — one-shot analysis only
- Does not implement Mirror — always produces output regardless of whether there's something worth saying
- Does not track "what Baah keeps avoiding" or "patterns he misses" — only what he explicitly logs

### Current prompt shape:
```
System: You are a career coach analysing a voice journal entry.
        Context: [profile] [goals] [open action items] [themes]
        Return JSON: { summary, sentiment, energy_level, wins[], challenges[],
                       decisions[], action_items[], themes[], coach_note,
                       goal_assessments[], pattern_flags[], accountability_callouts[] }

User: [transcript text]
```

---

## Part 3 — How to Build the Gap

This is the build guide. Work through these steps in order with Claude's help. Each step builds on the previous one.

**Before starting:** The four modes only make sense in a back-and-forth conversation. Step 3 (conversation interface) is the prerequisite for Steps 1 and 2 to work well. Recommended order: 3 → 5 → 1 → 2 → 4.

---

### Step 1: Add Mode-Selection Logic to the Prompt

**What to change:** `backend/src/prompts/system/journalProcessor.ts`

**What to add to the system prompt:**

```
Before responding, assess the situation and select exactly one mode:
- MIRROR: if what was shared has no material gap or risk
- NUDGE: if there is an insight the user can likely reach themselves
- CHALLENGE: if there is a pattern, goal conflict, or risky assumption they won't surface alone
- DIRECT: only if the user explicitly asked for your view or recommendation

State the selected mode at the start of your response as: "MODE: [Mirror/Nudge/Challenge/Direct]"

Mode rules:
- MIRROR: acknowledge and reflect only. One question max. No guidance.
- NUDGE: one question that points toward the insight without stating it. Stay quiet after.
- CHALLENGE: state the observation directly. One challenge only. Explain why it matters.
- DIRECT: give a clear, specific answer. No padding.
```

**What to change in the JSON response shape:** Add `"mode": "Mirror | Nudge | Challenge | Direct"` to the expected output.

**How to test:** Send a transcript like "Had a good day, team session went well" → should return MODE: Mirror. Send "I keep saying I'll push for strategy once this project ends" → should return MODE: Challenge.

---

### Step 2: Inject Prior Session Context as Narrative

**What to change:** `backend/src/services/claude/journalAgent.ts`

**What to add:** Load the last 5 journal entries' coach notes and pattern flags before calling the prompt builder.

```typescript
// Add to journalAgent.ts context loading
const recentAnalyses = db.prepare(`
  SELECT ea.coach_note, ea.pattern_flags, je.recorded_at
  FROM entry_analyses ea
  JOIN journal_entries je ON je.id = ea.entry_id
  WHERE je.user_id = ? AND je.status = 'complete'
  ORDER BY je.recorded_at DESC
  LIMIT 5
`).all(userId);
```

**What to add to `buildJournalProcessorSystem()`:**

```
Recent context (last 5 sessions):
${recentAnalyses.map((a, i) =>
  `[${i + 1}] ${a.recorded_at}: ${a.coach_note}`
).join('\n')}

Patterns flagged previously:
${recentAnalyses.flatMap(a => JSON.parse(a.pattern_flags)).join(', ')}
```

**Why this matters:** Without prior context, the agent can't identify "this is the third time you've said X." Pattern recognition requires history.

---

### Step 3: Implement the Conversation Interface

**What this requires:**
- A new backend route: `POST /api/v1/chat/message` — receives a user message + session ID, returns agent response
- A new agent: `backend/src/services/claude/chatAgent.ts` — manages session state, loads memory, calls Claude, stores the exchange
- A new table: `chat_sessions` — stores session ID, user ID, start time, status
- A new table: `chat_messages` — stores session ID, role (user/assistant), content, mode, timestamp
- A new mobile screen: `mobile/app/(tabs)/chat.tsx` — messaging UI, send/receive, session close action

**New route shape:**
```typescript
POST /api/v1/chat/message
Body: { sessionId: string, message: string }
Response: { reply: string, mode: "Mirror|Nudge|Challenge|Direct", cvMomentFlagged: boolean }

POST /api/v1/chat/session/start
Response: { sessionId: string }

POST /api/v1/chat/session/end
Body: { sessionId: string }
Response: { summary: ChatSessionSummary }
```

**Prompt shape for chat:** Unlike the journal analyser, the chat prompt must include the full conversation history in the user turn:

```
System: [Senior Self identity + four modes + memory context]

User: [prior messages as conversation history]
      Latest message: [current user message]
```

Use the Anthropic Messages API `messages` array format — pass alternating `user`/`assistant` turns.

---

### Step 4: Implement the Session Summary

**Fires when:** User taps "End session" in the chat interface.

**What to add:** `POST /api/v1/chat/session/end` calls `buildSessionSummaryPrompt()` with all messages from the session. Claude generates:

```json
{
  "keyMoments": ["string"],
  "insightsSurfaced": ["string"],
  "openThreadsCreated": ["string"],
  "cvMomentsFlagged": ["string"]
}
```

**Where to store:** New `chat_session_summaries` table, or extend `chat_sessions`.

**Mobile:** Show as a full-screen modal after ending the session. Allow navigation to CV Archive or Today from it.

---

### Step 5: Build the Persistent Memory Layer

**What to add to DB:**
- Extend `users` table or create `user_memory` table with:
  - `stated_patterns`: JSON array of named patterns the agent has confirmed (e.g. "defaults to execution mode when problems are ambiguous")
  - `open_threads`: JSON array of `{ title, created_at, last_referenced_at }`
  - `memory_last_updated`: timestamp

**What to change in agents:**
Load `stated_patterns` and `open_threads` from the user record at the start of every chat session. Pass them into the system prompt:

```
Confirmed patterns about this person:
- Defaults to execution mode when problems are ambiguous
- Consistently undervalues the political dimension of design decisions

Open threads (unresolved):
- You mentioned wanting to lead a project end-to-end (3 weeks ago, not revisited)
```

**When to update:** At session end, the agent proposes updates to patterns and threads. These are written to the DB as part of the session summary.
```

- [ ] **Step 3: Verify — check that the JSON fields mentioned match the schema**

```bash
grep "coach_note\|pattern_flags\|goal_assessments\|momentum_signal" backend/src/db/schema.sql
grep "coach_note\|pattern_flags\|goal_assessments" backend/src/prompts/system/journalProcessor.ts | head -10
```

Expected: all field names exist in both schema and prompt builder.

- [ ] **Step 4: Commit**

```bash
git add docs/agent-persona.md
git commit -m "docs: add agent-persona — Senior Self spec, current impl audit, five-step build guide"
```

---

## Task 6: `docs/design-system.md`

**Files:**
- Create: `docs/design-system.md`
- Read: `mobile/src/constants/theme.ts`, `mobile/src/components/` (list only)

- [ ] **Step 1: Read the existing theme and component structure**

```bash
cat mobile/src/constants/theme.ts
ls mobile/src/components/ 2>/dev/null || echo "no components dir yet"
```

- [ ] **Step 2: Write `docs/design-system.md`**

```markdown
# Design System

> Living reference for all UI work. Updated as screens are designed and components extracted.
> Last updated: 2026-04-15 (initial — pre-NativeWind migration)

---

## Status

The UI is being rebuilt from the ground up as part of the product redesign. This doc will grow with each screen.

**Current state:** Existing screens use React Native `StyleSheet` with `mobile/src/constants/theme.ts` as the token source.

**Target state:** NativeWind (Tailwind CSS for React Native). All new and rebuilt screens use NativeWind. The `theme.ts` tokens will be migrated to `tailwind.config.js` as custom values.

**NativeWind setup plan:** `docs/superpowers/plans/nativewind-setup.md` — run this before rebuilding any screen.

---

## The Build Workflow

The design system is not designed upfront. It grows from real screens.

```
1. Design a screen (in Figma or with Claude)
2. Build it with NativeWind
3. Extract reusable patterns into mobile/src/components/ui/
4. Update this doc with the new component
```

**The extraction rule:** if a UI pattern appears in two screens, extract it into `ui/`. Domain-specific components go in `features/`.

---

## Color Tokens

From `mobile/src/constants/theme.ts`. These will become Tailwind custom colors in `tailwind.config.js`.

### Base palette
| Token | Value | When to use |
|---|---|---|
| `background` | `#0A0A0F` | App background, all screens |
| `surface` | `#13131A` | Cards, panels, bottom sheets |
| `surfaceElevated` | `#1C1C27` | Modals, tooltips, elevated cards |
| `border` | `#2A2A38` | Visible borders |
| `borderSubtle` | `#1E1E2A` | Subtle dividers |

### Accent
| Token | Value | When to use |
|---|---|---|
| `accent` | `#7C6FFF` | Primary actions, active states, links |
| `accentMuted` | `#2D2B50` | Accent backgrounds, chips, tags |

### Semantic
| Token | Value | When to use |
|---|---|---|
| `positive` | `#4ADE80` | Wins, positive sentiment, success states |
| `warning` | `#FBBF24` | Stalling momentum, caution states |
| `error` | `#F87171` | Challenges, difficult sentiment, errors |
| `info` | `#60A5FA` | Decisions, informational content |

### Text
| Token | Value | When to use |
|---|---|---|
| `textPrimary` | `#F0F0F8` | Headings, primary content |
| `textSecondary` | `#8888A8` | Body text, descriptions |
| `textTertiary` | `#55556A` | Timestamps, metadata, disabled |
| `textAccent` | `#A89FFF` | Highlighted text, active labels |

### Momentum signals
Used for `momentum_signal` values from analyses.
- `accelerating` → `#4ADE80` (positive)
- `steady` → `#60A5FA` (info)
- `stalling` → `#FBBF24` (warning)
- `recovering` → `#A78BFA` (purple)

---

## Spacing Scale

| Token | Value | When to use |
|---|---|---|
| `xs` | 4px | Icon gaps, tight inline spacing |
| `sm` | 8px | Between related elements |
| `md` | 16px | Default padding, between sections |
| `lg` | 24px | Screen horizontal padding, card padding |
| `xl` | 32px | Section spacing |
| `xxl` | 48px | Large section breaks |

---

## Typography Scale

From `mobile/src/constants/theme.ts`. Document the scale here as screens are built.

*(To be filled in as the UI rebuild begins — extract from first designed screen.)*

---

## Component Catalog

Components are extracted from real screens as they're built. This section grows over time.

### Structure
```
mobile/src/components/
  ui/           Primitive components — no domain knowledge
  layout/       Structural components — Screen, Stack, Row, Divider
  features/     Domain components — EntryCard, GoalTag, CoachNote, ModeChip
```

*(No components extracted yet — UI rebuild starts after NativeWind setup.)*

---

## Rules for Writing New Components

Follow these when building any component so Claude generates consistent code across sessions:

1. **NativeWind classes only** — no `StyleSheet.create()` in new components
2. **Use token names** — `bg-background`, `text-textPrimary`, `border-border` (mapped in `tailwind.config.js`)
3. **Props over variants** — prefer explicit props (`size="sm"`) over internal variant logic
4. **One component per file** — no barrel files for small components; import directly
5. **TypeScript always** — every component has a typed props interface

---

## On Storybook

Not set up yet. Revisit after 3–4 screens are rebuilt and the component library is taking shape. At that point a visual catalog becomes useful — especially before bringing a team member on.

When added: use the Expo + Storybook 9 setup. See [expo.dev/blog/storybook-and-expo](https://expo.dev/blog/storybook-and-expo).
```

- [ ] **Step 3: Verify — confirm token values against source**

```bash
grep "background\|accent\|textPrimary" mobile/src/constants/theme.ts | head -10
```

Expected: hex values in the doc match the source file.

- [ ] **Step 4: Commit**

```bash
git add docs/design-system.md
git commit -m "docs: add design-system — tokens, component structure, NativeWind roadmap"
```

---

## Task 7: `README.md`

**Files:**
- Create: `README.md` (root level)
- Read: `SETUP.md`, all docs written in Tasks 1–6

- [ ] **Step 1: Read SETUP.md**

```bash
cat SETUP.md
```

Note the existing setup steps. README should not duplicate SETUP.md — link to it instead.

- [ ] **Step 2: Write `README.md`**

```markdown
# Taisa

> "I wish I could shadow a senior version of myself while I work."

A personal AI career companion that lives close to your work life. Capture what's happening day-to-day, get coached by a senior version of yourself, and have polished outputs (CV bullets, quarterly reviews) ready when you need them.

Built for one person first — the builder. Validated by real use before expanding.

---

## What It Does

```
You log what happened at work (voice or text)
  ↓
Claude analyses it as a senior career coach
  ↓
Wins, challenges, action items, and CV moments are captured
  ↓
When you need to write a quarterly review or update your CV,
the material is already shaped and waiting
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | React Native + Expo (managed workflow) |
| Styling | NativeWind (Tailwind CSS for React Native) |
| State | Zustand |
| Backend | Node.js + Express + TypeScript |
| Database | SQLite (local, via better-sqlite3) |
| AI — coaching | Anthropic Claude (claude-sonnet-4-6) |
| AI — transcription | OpenAI Whisper |

---

## Running Locally

See [SETUP.md](SETUP.md) for first-time setup (API keys, environment files).

**Common issue:** Port 3000 may be in use by another local dev server. Change `PORT` in `backend/.env` if needed.

```bash
# Terminal 1 — backend
npm run backend

# Terminal 2 — mobile
npm run mobile
```

Your Mac's local IP (for `EXPO_PUBLIC_API_URL` in `mobile/.env`):
```bash
ipconfig getifaddr en0
```

---

## Project Structure

```
taisa/
├── mobile/       React Native app (Expo) — has its own node_modules
├── backend/      Node.js + Express API
├── shared/       TypeScript types shared between mobile and backend
└── docs/         All documentation (start here)
```

---

## Documentation

| Doc | What it's for |
|---|---|
| [docs/v1-status.md](docs/v1-status.md) | What's built, what diverged from spec, what's next |
| [docs/architecture.md](docs/architecture.md) | System overview, data flow, how Claude is wired |
| [docs/data-model.md](docs/data-model.md) | Database schema, entity relationships |
| [docs/api.md](docs/api.md) | All API endpoints, request/response shapes |
| [docs/agent-persona.md](docs/agent-persona.md) | The Senior Self spec + build guide for the AI layer |
| [docs/design-system.md](docs/design-system.md) | Visual language, tokens, component structure |
| [SETUP.md](SETUP.md) | First-time setup, API keys, dev build instructions |
| [docs/product/](docs/product/) | Product design artifacts #001–#005 (.docx) |

**Start with `docs/v1-status.md`** to understand where the project is right now.

---

## Product Vision

See [docs/product/product-brief-001.docx](docs/product/01-product/product-brief-001.docx) for the full product brief. The short version:

The problem is a chain — memory gap → lost context → missing guidance → navigating career growth alone with incomplete information and no real-time perspective. Taisa closes the loop.
```

- [ ] **Step 3: Verify — all doc links resolve**

```bash
ls docs/v1-status.md docs/architecture.md docs/data-model.md docs/api.md docs/agent-persona.md docs/design-system.md SETUP.md docs/product/01-product/product-brief-001.docx
```

Expected: all files exist.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add README — project entry point with doc map"
```

---

## Task 8: `CLAUDE.md`

**Files:**
- Create: `CLAUDE.md` (root level)
- Read: all docs written in Tasks 1–7

- [ ] **Step 1: Write `CLAUDE.md`**

```markdown
# Taisa — Claude Code Context

Taisa is a personal AI career companion for a solo designer (Baah). Users log daily work via voice; Claude analyses it as a senior career coach, extracts wins/challenges/action items, and surfaces CV-worthy moments. The v1 loop is fully functional. The next major build is the chat interface + four-mode Senior Self agent.

**Stack:** React Native/Expo + NativeWind, Node/Express, SQLite, Anthropic SDK (claude-sonnet-4-6), OpenAI Whisper.

---

## Critical Constraints

Do not violate these without explicit instruction:

- **No auth in v1** — `userId` = device UUID, passed via `x-user-id` header. Set automatically in `mobile/src/services/api.ts` Axios interceptor. Do not add auth middleware.
- **SQLite only** — `backend/src/db/connection.ts`. No migrations system. Add columns via `ALTER TABLE` or update `schema.sql` and note manual migration needed.
- **Expo managed workflow** — do not run `npx expo run:ios` or `npx expo eject` unless explicitly asked. Use `npx expo start`.
- **`mobile/` is NOT in root workspace** — it has its own `node_modules`. Run `npm install` inside `mobile/` for mobile deps. Never `npm install` from root for mobile packages.
- **NativeWind for new UI** — all new and rebuilt screens use NativeWind. No `StyleSheet.create()` in new components. See `docs/design-system.md`.

---

## The Critical Gap

**Product docs describe a chat interface with four coaching modes (Mirror / Nudge / Challenge / Direct). What's built is a voice journaling loop with one-shot Claude analysis. Do not conflate them.**

The Senior Self persona from the product docs is NOT yet implemented. The current `journalProcessor.ts` is a structured analyser, not a four-mode coach. The build guide for closing this gap is in `docs/agent-persona.md` Part 3.

---

## Where to Look

| I need to... | Read |
|---|---|
| Understand the current state of the build | `docs/v1-status.md` |
| Understand how the system fits together | `docs/architecture.md` |
| Add or modify a database table | `docs/data-model.md` |
| Add or modify an API endpoint | `docs/api.md` |
| Work on Claude prompts or AI behaviour | `docs/agent-persona.md` |
| Build or modify any UI component | `docs/design-system.md` |
| Understand the product vision | `docs/product/01-product/product-brief-001.docx` |

---

## Backend Pattern

Every AI feature follows: route → agent → prompt builder → `callClaudeJson` → DB write.
Reference: `backend/src/services/claude/journalAgent.ts` + `backend/src/prompts/system/journalProcessor.ts`.
Full walkthrough: `docs/architecture.md` § "How the Backend Calls Claude".

---

## Common Commands

```bash
# Start backend (from repo root)
npm run backend

# Start mobile (from repo root)
npm run mobile

# Install mobile dependency
cd mobile && npm install <package>

# Backend only — install dependency
npm install <package> --workspace=backend
```
```

- [ ] **Step 2: Verify — check that all file paths in "Where to Look" exist**

```bash
ls docs/v1-status.md docs/architecture.md docs/data-model.md docs/api.md docs/agent-persona.md docs/design-system.md docs/product/01-product/product-brief-001.docx
```

Expected: all files exist (written in Tasks 1–7).

- [ ] **Step 3: Verify — check the critical constraint about mobile workspace**

```bash
cat package.json | grep -A5 "workspaces"
```

Expected: confirms `mobile` is NOT in the workspaces array.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md — AI session context, constraints, gap warning, doc index"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `README.md` with founding insight, tech stack, doc map | Task 7 |
| `CLAUDE.md` with constraints, gap warning, doc pointers | Task 8 |
| `docs/architecture.md` with data flow + Claude wiring pattern | Task 2 |
| `docs/data-model.md` with 9 tables + memory model mapping | Task 3 |
| `docs/api.md` with all 9 route groups + "how to add" section | Task 4 |
| `docs/agent-persona.md` — Part 1 spec, Part 2 current impl, Part 3 build guide | Task 5 |
| `docs/design-system.md` — tokens, component structure, NativeWind roadmap | Task 6 |
| `docs/v1-status.md` — built vs spec'd, divergence table, what's next | Task 1 |
| Writing order: v1-status first, CLAUDE.md last | Task ordering ✅ |
| NativeWind noted as prerequisite before UI rebuild | Tasks 6, 8 ✅ |
| Storybook: deferred with revisit note | Task 6 ✅ |

**Placeholder scan:** No TBDs, TODOs, or "implement later" text. One intentional placeholder in `design-system.md` typography section ("To be filled in as UI rebuild begins") — this is correct behaviour for a living doc.

**Type consistency:** No code types defined across tasks — documentation only.

**Gaps found:** None. All spec requirements map to a task.

---

## Notes

- **NativeWind setup is a separate plan.** Run it before rebuilding any screen. File: `docs/superpowers/plans/nativewind-setup.md` (to be written in a future session).
- **`design-system.md` is intentionally thin.** It will grow as screens are designed. Do not pad it upfront.
- **Port 3000 conflict is a known issue** (documented in README). Not fixed here — addressed in a future ops session.
