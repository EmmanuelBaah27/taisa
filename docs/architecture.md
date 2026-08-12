# Architecture

> Read this before touching any code. The local-first coaching platform is in BUILD and is not
> shipped until its SQLCipher development-build and physical-device checklist passes.

## Current authority boundary

The new coaching path is phone-authoritative. Readable profile, conversations, transcripts,
goals, actions, evidence, governed memory, context manifests, and cached coaching responses live
in the SQLCipher database on the iPhone. A deliberate submit sends one bounded context package to
the gateway; private save, browse, search, edit, confirmation, export, and restore are local.

```text
iPhone (readable authority)
  capture → encrypted SQLite → bounded context → explicit submit
                                         │
                                         ▼
Taisa gateway (transient processing)
  validate → cost/rate guard → one configured provider call → structured response
                                         │
                                         ▼
iPhone
  cache response → stage governed deltas → persist only after local policy/user confirmation
```

The gateway stores only content-free usage/cost reservations. It must not write prompts,
transcripts, request/response bodies, or coaching text to logs, analytics, crash reports, or
backend SQLite. The mobile app has no provider credentials.

There is no migration/export endpoint. Baah confirmed that no legacy backend data needs to be
migrated, so Task 7 was removed. Legacy backend CRUD and AI routes are still mounted as rollback
compatibility during BUILD; they are not part of the local coaching flow and cannot be retired
until encrypted recovery passes on device and Baah explicitly approves route retirement.

### Recovery and privacy engine

- Manual backup uses a separate, confirmed passphrase (minimum 12 non-whitespace characters),
  SQLCipher `ATTACH ... KEY`, and `sqlcipher_export`.
- The archive contains encrypted database state, not recorded audio files. Export fails closed
  before creating an artifact if a nonterminal coaching request still references audio; the user
  must finish or abandon that voice work first.
- Restore stages the selected file and reads it through a query-only maintenance connection. It
  verifies format/version, SQLite and foreign-key integrity, exact allowlisted table mappings,
  required entity counts, a deterministic content hash, and two-way message/evidence search-index
  alignment.
- Restore builds a fresh device-key candidate from trusted current migrations and copies only
  allowlisted rows with bound values; archive-owned schema is never promoted. The active database
  and Keychain key remain recoverable through a digest-verified rollback copy and durable promotion
  marker until the promoted candidate reopens and matches the verified fingerprint.
- Optional LocalAuthentication stores only an enabled/disabled preference. The operating system
  owns biometric material. Inactive/background UI is covered by a root privacy shield.
- Notifications use generic content-free copy. Redaction is deterministic and local; its
  replacement map exists in memory only, and the displayed preview is submitted only after an
  explicit action.

SQLCipher compilation, parameterized SQLCipher `ATTACH`, filesystem promotion behavior, Face ID,
app-switcher timing, file sharing/picking, and clean-install recovery still require the gated
managed iPhone development-build checklist.

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

## Legacy data flow — voice journal to server insight

This describes the still-mounted pre-cutover route family. It is retained for rollback and old
screens during BUILD, not as the authority model for the new local coaching flow:

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

## Legacy backend agents

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

## Adding a new AI feature

New coaching features must use the provider-neutral stateless path:

1. Extend the portable shared contract and runtime schema.
2. Assemble bounded readable context on-device.
3. Validate and meter it in the gateway without backend user-data reads or content logging.
4. Make exactly one configured provider call.
5. Return structured proposals; deterministic mobile governance owns persistence.

The route → database-loading agent → prompt → backend-write pattern below is legacy-only and must
not be copied for new readable-user-data features. It remains solely as historical documentation
for still-mounted rollback routes.

Legacy-only reference: those pre-cutover routes call backend-data agents and persist their result.
New readable-user-data features must follow the five stateless coaching steps above instead.

See `docs/api.md` for the request/response patterns. See `docs/agent-persona.md` for the Senior Self prompt engineering guide.

---

## Tech Decisions and Why

| Decision | Why |
|---|---|
| SQLCipher SQLite on iPhone | Single readable authority with a device-only Keychain key. Expo Go cannot validate this native configuration. |
| Backend SQLite | Legacy CRUD rollback store plus a content-free usage ledger during BUILD; not a destination for new coaching content. |
| `ts-node-dev` | Hot-reload TypeScript in dev without a build step. No compiled output needed during development. |
| Installation ID in `x-user-id` | MVP transport shortcut for usage accounting and rate limiting, not authentication or career-data identity. The authoritative local `profile.id` lives in encrypted SQLite; the separate installation ID is set automatically by `mobile/src/services/api.ts`. |
| Zustand (not Redux) | Lightweight global state for a solo mobile app. Three stores: `journalStore`, `careerStore`, `uiStore`. |
| Expo managed workflow | Native configuration stays managed, but SQLCipher and LocalAuthentication require a development build; Expo Go is insufficient. |
| `callClaudeJson` with fallback | Claude sometimes wraps JSON in markdown code fences. The fallback parser strips them before parsing. |
