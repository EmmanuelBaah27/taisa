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
   → fetchEntries() called after analyzeEntry()
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
Loads context from the database, assembles the prompt, calls the Claude client, and persists the result.

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
Pure functions that take data and return prompt strings. No database calls, no Claude calls.

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
- `callClaudeJson(system, user)` → parses JSON from response, with fallback extraction for when Claude wraps output in markdown code fences

Both use `claude-sonnet-4-6` with a default max token limit of `4096`.

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
| SQLite (not Postgres/Mongo) | Local-only in v1. No network dependency. Matches the product spec's principle: validate the memory model with real use before adding infrastructure. |
| `ts-node-dev` | Hot-reload TypeScript in dev without a build step. No compiled output needed during development. |
| `deviceId` as `userId` | MVP shortcut. Single user, no login screen. The `x-user-id` header is set automatically by `mobile/src/services/api.ts` via an Axios interceptor. |
| Zustand (not Redux) | Lightweight global state for a solo mobile app. Three stores: `journalStore`, `careerStore`, `uiStore`. |
| Expo managed workflow | Faster iteration, no native build tooling required. Trade-off: some native audio features require a dev build (not Expo Go). |
| `callClaudeJson` with fallback | Claude sometimes wraps JSON in markdown code fences. The fallback parser strips them before parsing. |
