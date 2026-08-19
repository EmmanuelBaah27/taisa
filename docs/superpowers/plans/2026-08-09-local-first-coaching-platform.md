# Local-First Coaching Platform Implementation Plan

**Status:** Approved — Build in progress

> **Approved scope reconciliation — 2026-08-10:** Baah confirmed there is no backend data to
> preserve. Task 7 is removed: Taisa will not add a backend migration/export endpoint, migration
> token, mobile importer, or physical-device data-migration journey. Local SQLite schema migrations
> remain part of Task 5 and are unrelated to legacy-data import. The next approval gate is managed
> iPhone recovery/privacy QA. Legacy-route retirement remains a separate Task 10 gate after that
> evidence and Baah's explicit approval; the routes stay mounted until then.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make encrypted on-device storage authoritative for Taisa's durable career data while
preserving high-quality, metered coaching through a stateless gateway.

**Architecture:** The iPhone becomes authoritative for profile, conversations, goals, actions, evidence, and governed memory. The mobile client assembles a bounded `CoachingRequest`; Express validates it and selects one configured provider adapter, returning coaching text, structured proposed deltas, and content-free usage metadata without reading or writing user data. OpenAI is the low-cost primary candidate and existing Anthropic support is the quality benchmark; the production default is chosen from a synthetic evaluation pack. No backend-data migration is required. Legacy CRUD routes remain mounted during BUILD and are retired only after recovery/privacy device evidence and Baah's separate explicit approval.

**Tech Stack:** Expo SDK 54, React Native 0.81, TypeScript 5.9, Expo SQLite with SQLCipher, Expo SecureStore, Expo Crypto, Zustand, Express 4, Zod 3, OpenAI SDK, Anthropic SDK, OpenAI transcription API, Jest/Supertest.

## Global Constraints

- iPhone is the single authoritative store for readable user data.
- No request bodies, response bodies, transcripts, prompts, or coaching text may be written to gateway logs, analytics, crash reports, or backend SQLite.
- Only deliberate Submit sends content off-device; Private Save is complete without AI.
- One coaching provider request per submitted turn. Invalid structured output fails recoverably; it does not trigger an automatic second paid call.
- Provider selection is gateway configuration; the mobile contract and local archive are provider-independent.
- MVP coaching adapters are limited to OpenAI and Anthropic. DeepSeek receives synthetic fixtures only, and unpaid provider tiers never receive sensitive Taisa content.
- The production default must pass the versioned 20-scenario evaluation pack; price alone does not determine the default.
- Daily, monthly, and per-request spend ceilings fail closed before a provider call. There are no silent paid retries.
- Full conversation archive is never sent by default; context is assembled on-device under a fixed budget.
- The AI proposes memory deltas but cannot persist them.
- Each local-first entity has exactly one authoritative store; there is no dual-write period.
- Keep the existing no-auth MVP constraint: device ID remains the caller identifier. It is a rate-limit key, not a security identity.
- Expo managed workflow remains. SQLCipher requires a managed development build and is not available in Expo Go; this approved plan authorizes the `expo-sqlite` SQLCipher configuration. Running native prebuild or creating a managed development build remains a separate explicit execution gate before Task 5 device verification.
- Detailed UI redesign is out of scope. Existing screens receive only minimal wiring needed to validate private save, submit, confirmation, history, and recovery.
- Keep the legacy backend routes/database unchanged as BUILD rollback compatibility until recovery
  evidence and Baah's explicit route-retirement approval. They are not a migration source.
- Manual encrypted export contains database state only, never recorded audio files. It must fail
  closed before artifact creation while nonterminal voice work still references audio.
- Follow TDD for domain logic and gateway behavior; missing native test infrastructure is reported and covered by a physical-device checklist.

---

## File map

### Shared contracts

- Create `shared/types/coaching.ts` — portable request, response, usage, and proposed-delta contracts.
- Create `shared/types/memory.ts` — governed memory, evidence, goal, and action lifecycle contracts.
- Retain `shared/types/migration.ts` only as an unused pre-reconciliation contract; it does not
  authorize or imply a migration endpoint/importer.
- Modify `shared/index.ts` — export all new contracts.

### Stateless gateway

- Create `backend/src/schemas/coaching.ts` — Zod validation and hard request limits.
- Create `backend/src/prompts/system/seniorSelf.ts` — prompt from supplied context only.
- Create `backend/src/services/coaching/provider.ts` — provider-neutral adapter interface and configuration.
- Create `backend/src/services/coaching/openaiProvider.ts` — OpenAI structured-output adapter.
- Create `backend/src/services/coaching/anthropicProvider.ts` — Anthropic structured-output adapter around the existing client.
- Create `backend/src/services/coaching/coachingGateway.ts` — exactly one configured provider call and shared response validation.
- Create `backend/src/evals/coaching/` — versioned synthetic scenarios, runner, rubric, and content-free result summary.
- Create `backend/src/routes/coaching.ts` — stateless `POST /api/v1/coaching/respond`.
- Create `backend/src/middleware/requestContext.ts` — request ID and content-free telemetry.
- Modify `backend/src/routes/transcribe.ts` — guaranteed temporary-file cleanup and usage metadata.
- Modify `backend/src/index.ts` — mount new routes and replace body-unsafe error logging.

### Mobile local platform

- Modify `mobile/package.json` — add Expo SQLite, Expo Crypto, Jest preset, and test scripts.
- Modify `mobile/app.json` — enable SQLCipher config plugin.
- Create `mobile/src/db/openDatabase.ts` — SecureStore key creation and encrypted database opening.
- Create `mobile/src/db/migrations.ts` — numbered, transactional local migrations.
- Create `mobile/src/db/schema.ts` — local schema statements.
- Create `mobile/src/db/types.ts` — narrow database adapter used by repositories and tests.
- Create `mobile/src/repositories/` — focused repositories for profile, conversations, goals,
  actions, evidence, and memory.
- Create `mobile/src/domain/memory/` — admission, confirmation, lifecycle, and conflict rules.
- Create `mobile/src/domain/context/` — deterministic bounded context assembly and evidence ranking.
- Create `mobile/src/services/coaching.ts` — gateway client with idempotency and no content logging.
- Create `mobile/src/services/privateCapture.ts` — local private-save and deliberate-submit orchestration.
- Create `mobile/src/services/exportArchive.ts` — passphrase-encrypted SQLCipher export and verified restore.
- Modify mobile stores — replace backend CRUD reads/writes with repositories.
- Modify `mobile/app/chat/index.tsx` minimally — exercise local conversation persistence and proposed-delta confirmation.

### Documentation

- Modify `docs/architecture.md`, `docs/data-model.md`, `docs/api.md`, `docs/v1-status.md`, and `SETUP.md` through BUILD and at the later route-retirement gate.
- Create `docs/features/local-first-cutover-qa.md` — physical-device and recovery checklist.

---

### Task 1: Define portable coaching and memory contracts

**Files:**
- Create: `shared/types/memory.ts`
- Create: `shared/types/coaching.ts`
- Historical only: `shared/types/migration.ts` was created before the approved no-migration reconciliation and has no runtime migration consumer.
- Modify: `shared/index.ts`
- Test: `backend/src/__tests__/coaching.contract.test.ts`

**Interfaces:**
- Produces: `CoachingRequest`, `CoachingResponse`, `CoachingContext`, `MemoryItem`, `MemoryDelta`, `EvidenceItem`, and `UsageReceipt`. `LegacyExportBundleV1` is historical/unused after reconciliation.
- Consumed by: later gateway, database, context, and recovery tasks. No legacy-data migration task remains.

- [ ] **Step 1: Write the failing contract test**

```ts
import type { CoachingRequest, CoachingResponse, MemoryItem } from '@taisa/shared';

test('contracts represent a bounded coaching turn and proposed memory change', () => {
  const memory: MemoryItem = {
    id: 'mem-1', type: 'goal', statement: 'Become a Staff Designer',
    provenance: 'user-confirmed', lifecycle: 'active', confidence: 'established',
    createdAt: '2026-08-09T00:00:00Z', confirmedAt: '2026-08-09T00:00:00Z',
    lastSupportedAt: '2026-08-09T00:00:00Z', statusChangedAt: '2026-08-09T00:00:00Z',
    sourceMessageIds: ['m1'],
  };
  const request: CoachingRequest = {
    requestId: 'req-1', submittedAt: '2026-08-09T00:00:00Z', input: 'I may prefer management',
    context: { profile: null, recentMessages: [], memory: [memory], evidence: [] },
  };
  const response: CoachingResponse = {
    requestId: request.requestId, reply: 'Earlier you preferred the Staff path. Has that changed?',
    stance: 'challenge', proposals: [],
    usage: { provider: 'anthropic', model: 'test', inputTokens: 10, outputTokens: 8, estimatedCostUsd: 0 },
  };
  expect(response.requestId).toBe(request.requestId);
});
```

- [ ] **Step 2: Run the test and confirm the missing exports fail compilation**

Run: `npm test --workspace=backend -- coaching.contract.test.ts --runInBand`

Expected: FAIL because the new shared types do not exist.

- [ ] **Step 3: Add exact discriminated contracts**

```ts
export type MemoryType = 'goal' | 'commitment' | 'decision' | 'preference' | 'career_context' | 'development_area' | 'evidence' | 'pattern';
export type MemoryProvenance = 'user-stated' | 'user-confirmed' | 'ai-inferred' | 'system-observed';
export type MemoryLifecycle = 'proposed' | 'active' | 'paused' | 'superseded' | 'completed' | 'rejected' | 'archived';
export type MemoryConfidence = 'tentative' | 'supported' | 'established';

export interface MemoryItem {
  id: string; type: MemoryType; statement: string; provenance: MemoryProvenance;
  lifecycle: MemoryLifecycle; confidence: MemoryConfidence; createdAt: string;
  confirmedAt: string | null; lastSupportedAt: string; statusChangedAt: string;
  sourceMessageIds: string[]; supersedesId?: string | null;
}

export type MemoryDelta =
  | { operation: 'propose'; candidate: Omit<MemoryItem, 'id' | 'createdAt' | 'confirmedAt' | 'lastSupportedAt' | 'statusChangedAt'>; reason: string; requiresConfirmation: boolean }
  | { operation: 'transition'; targetId: string; to: MemoryLifecycle; reason: string; requiresConfirmation: boolean }
  | { operation: 'support'; targetId: string; sourceMessageId: string; reason: string; requiresConfirmation: false };
```

Add the remaining exact contracts:

```ts
export interface EvidenceItem {
  id: string; statement: string; occurredAt: string; sourceMessageIds: string[];
  goalIds: string[]; actionIds: string[];
}

export interface CoachingContext {
  profile: Pick<CareerProfile, 'currentRole' | 'currentCompany' | 'careerStage' | 'coachingStyle' | 'accountabilityLevel'> | null;
  recentMessages: Array<{ role: 'user' | 'assistant'; content: string }>;
  memory: MemoryItem[];
  evidence: EvidenceItem[];
}

export interface CoachingRequest {
  requestId: string; submittedAt: string; input: string; context: CoachingContext;
}

export interface UsageReceipt {
  provider: 'anthropic' | 'openai'; model: string; inputTokens?: number;
  outputTokens?: number; audioSeconds?: number; estimatedCostUsd: number;
}

export interface CoachingResponse {
  requestId: string; reply: string;
  stance: 'mirror' | 'nudge' | 'challenge' | 'direct';
  proposals: MemoryDelta[]; usage: UsageReceipt;
}

// Superseded runtime-migration concept retained only as a historical contract.
// No endpoint or importer consumes this type.
export interface LegacyExportBundleV1 {
  schemaVersion: 1; exportedAt: string; userId: string;
  profile: CareerProfile; entries: JournalEntry[]; analyses: EntryAnalysis[];
  sessions: Array<{ id: string; entryId: string | null; title: string | null; startedAt: string; status: 'active' | 'ended' }>;
  messages: Array<{ id: string; sessionId: string; role: 'user' | 'assistant'; content: string; createdAt: string }>;
  goals: Goal[]; actions: ActionItem[]; reviews: PerformanceReview[];
  trajectory: TrajectorySnapshot[];
}
```

Runtime schemas cap arrays and strings; TypeScript describes transport shape only.

- [ ] **Step 4: Export contracts and rerun checks**

Run: `npm test --workspace=backend -- coaching.contract.test.ts --runInBand && npm run build --workspace=backend`

Expected: PASS and backend TypeScript build exits 0.

- [ ] **Step 5: Commit**

```bash
git add shared backend/src/__tests__/coaching.contract.test.ts
git commit -m "feat: define portable coaching contracts"
```

---

### Task 2: Build the provider-neutral stateless coaching gateway

**Files:**
- Create: `backend/src/schemas/coaching.ts`
- Create: `backend/src/prompts/system/seniorSelf.ts`
- Create: `backend/src/services/coaching/provider.ts`
- Create: `backend/src/services/coaching/openaiProvider.ts`
- Create: `backend/src/services/coaching/anthropicProvider.ts`
- Create: `backend/src/services/coaching/coachingGateway.ts`
- Create: `backend/src/routes/coaching.ts`
- Create: `backend/src/__tests__/coaching.routes.test.ts`
- Create: `backend/src/__tests__/coachingGateway.test.ts`
- Inspect only in this ungated slice: `backend/src/index.ts` (legacy mounts remain unchanged)
- Modify: `backend/src/services/claude/client.ts`

**Interfaces:**
- Consumes: `CoachingRequest`, `CoachingResponse`, `MemoryDelta` from Task 1.
- Produces: `CoachingProvider`, `getConfiguredProvider()`, `POST /api/v1/coaching/respond`, and `requestCoaching(request): Promise<CoachingResponse>`.

- [ ] **Step 1: Write route tests proving the route is bounded and database-independent**

```ts
jest.mock('../services/coaching/coachingGateway', () => ({
  requestCoaching: jest.fn().mockResolvedValue({
    requestId: 'req-1', reply: 'What changed?', stance: 'nudge', proposals: [],
    usage: { provider: 'anthropic', model: 'mock', inputTokens: 5, outputTokens: 3, estimatedCostUsd: 0 },
  }),
}));

test('accepts supplied context without loading backend user data', async () => {
  const res = await request(app).post('/api/v1/coaching/respond').set('x-user-id', 'device-1').send(validRequest);
  expect(res.status).toBe(200);
  expect(res.body.data.reply).toBe('What changed?');
  expect(jest.requireMock('../services/coaching/coachingGateway').requestCoaching).toHaveBeenCalledWith(validRequest);
});

test.each([
  ['input', { ...validRequest, input: 'x'.repeat(4001) }],
  ['memory', { ...validRequest, context: { ...validRequest.context, memory: Array(51).fill(memory) } }],
  ['messages', { ...validRequest, context: { ...validRequest.context, recentMessages: Array(21).fill(message) } }],
])('rejects oversized %s', async (_name, body) => {
  expect((await request(app).post('/api/v1/coaching/respond').set('x-user-id', 'd1').send(body)).status).toBe(400);
});
```

- [ ] **Step 2: Run the route tests and confirm 404/module failures**

Run: `npm test --workspace=backend -- coaching.routes.test.ts --runInBand`

Expected: FAIL because the route and service do not exist.

- [ ] **Step 3: Implement runtime validation with hard limits**

```ts
export const CoachingRequestSchema = z.object({
  requestId: z.string().uuid(), submittedAt: z.string().datetime(),
  input: z.string().trim().min(1).max(4000),
  context: z.object({
    profile: z.record(z.unknown()).nullable(),
    recentMessages: z.array(z.object({ role: z.enum(['user', 'assistant']), content: z.string().max(4000) })).max(20),
    memory: z.array(MemoryItemSchema).max(50),
    evidence: z.array(EvidenceItemSchema).max(8),
  }),
});
```

- [ ] **Step 4: Write failing adapter and service tests for provider independence and one-call structured output**

Test both adapters against the same contract fixture. Configure each provider in turn, call `requestCoaching`, assert exactly one adapter invocation, validate the returned proposals, and assert no import or call of `getDb`. Add a test proving invalid structured output returns a recoverable error without calling either adapter again.

- [ ] **Step 5: Add the provider contract, selector, and two one-call adapters**

```ts
export interface CoachingProvider {
  readonly id: 'openai' | 'anthropic';
  respond(input: ProviderCoachingInput): Promise<ProviderCoachingResult>;
}
```

Use each provider's native schema-constrained output feature and parse the result through `CoachingResponsePayloadSchema`; do not retry invalid output. `TAISA_COACHING_PROVIDER` selects `openai` or `anthropic`, and absent/invalid configuration fails at startup rather than silently choosing a provider. Model IDs and input/output prices come from environment configuration so provider or pricing changes do not require code or a mobile release.

- [ ] **Step 6: Build the Senior Self prompt exclusively from supplied context**

The prompt must define Mirror/Nudge/Challenge/Direct as internal stances, require concise coaching text, return valid JSON, distinguish observations from facts, and forbid claims unsupported by supplied memory/evidence. It must not read profile, goals, themes, sessions, or messages from backend SQLite.

- [ ] **Step 7: Mount the route and run focused checks**

Run: `npm test --workspace=backend -- coaching.routes.test.ts coachingGateway.test.ts --runInBand && npm run build --workspace=backend`

Expected: PASS; TypeScript build exits 0.

- [ ] **Step 8: Commit**

```bash
git add backend/src shared
git commit -m "feat: add stateless coaching gateway"
```

---

### Task 3: Add the synthetic provider evaluation pack

**Files:**
- Create: `backend/src/evals/coaching/scenarios.ts`
- Create: `backend/src/evals/coaching/rubric.ts`
- Create: `backend/src/evals/coaching/run.ts`
- Create: `backend/src/__tests__/coaching.eval.test.ts`
- Modify: `backend/package.json`

**Interfaces:**
- Consumes: `CoachingProvider` from Task 2 and the shared `CoachingResponse` schema from Task 1.
- Produces: `npm run eval:coaching -- --provider=openai|anthropic` and a content-free JSON summary.

- [ ] **Step 1: Write failing tests for scenario completeness and redaction**

Assert the pack contains at least 20 synthetic scenarios spanning work conflict, career goals, forgotten or conflicting goals, related historical context, evidence, sensitive inference, action evolution, and no-memory cases. Assert serialized summaries contain only scenario IDs, numeric rubric scores, latency, token usage, estimated cost, schema status, and error codes—not prompts or model responses.

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `npm test --workspace=backend -- coaching.eval.test.ts --runInBand`

Expected: FAIL because the evaluation modules do not exist.

- [ ] **Step 3: Implement the scenarios, deterministic checks, and runner**

Each scenario includes synthetic input/context, expected proposal constraints, forbidden mutations, and rubric dimensions: coaching usefulness, continuity/conflict detection, action quality, memory correctness, and schema compliance. The runner requires an explicit provider, performs one call per scenario, never retries, and writes no raw content to disk.

- [ ] **Step 4: Add the command and verify without incurring provider cost**

Run the unit test with fake adapters, then run `npm run build --workspace=backend`. Do not execute the live evaluation command during automated tests or without an explicit cost-approved invocation.

- [ ] **Step 5: Commit**

```bash
git add backend/src/evals backend/src/__tests__/coaching.eval.test.ts backend/package.json
git commit -m "test: add coaching provider evaluation pack"
```

---

### Task 4: Make gateway telemetry and transcription content-safe

**Files:**
- Create: `backend/src/middleware/requestContext.ts`
- Create: `backend/src/services/usage/costLedger.ts`
- Create: `backend/src/__tests__/privacy.middleware.test.ts`
- Modify: `backend/src/routes/transcribe.ts`
- Modify: `backend/src/index.ts`
- Modify: `backend/src/__tests__/chat.routes.test.ts`

**Interfaces:**
- Produces: `req.requestId`, content-free `recordUsage(receipt)`, and transcription `UsageReceipt`.
- Consumed by: coaching and transcription routes and later mobile usage display.

- [ ] **Step 1: Write failing privacy tests**

```ts
test('logs method, route, status, latency, and requestId without content', async () => {
  await request(app).post('/api/v1/coaching/respond').set('x-user-id', 'device-1').send(validRequest);
  const output = logSpy.mock.calls.flat().join(' ');
  expect(output).toContain('/api/v1/coaching/respond');
  expect(output).not.toContain(validRequest.input);
  expect(output).not.toContain(validRequest.context.memory[0].statement);
});

test('deletes uploaded audio when transcription succeeds or fails', async () => {
  openaiMock.mockRejectedValueOnce(new Error('provider failure'));
  await request(app).post('/api/v1/transcribe').attach('audio', fixturePath);
  expect(fs.existsSync(capturedTempPath)).toBe(false);
});
```

- [ ] **Step 2: Run tests and confirm they fail**

Run: `npm test --workspace=backend -- privacy.middleware.test.ts --runInBand`

- [ ] **Step 3: Replace generic request/error logging with content-free structured logging**

```ts
export function requestContext(req: Request, res: Response, next: NextFunction) {
  const started = Date.now();
  req.requestId = req.header('x-request-id') ?? randomUUID();
  res.setHeader('x-request-id', req.requestId);
  res.on('finish', () => console.info(JSON.stringify({
    requestId: req.requestId, method: req.method, route: req.originalUrl.split('?')[0],
    status: res.statusCode, latencyMs: Date.now() - started,
  })));
  next();
}
```

Error handlers log request ID, error code, and stack only; they never serialize `req.body`, provider payloads, or provider responses.

- [ ] **Step 4: Put transcription cleanup in `finally` and return content-free usage**

Use `fs.promises.rm(req.file.path, { force: true })` in `finally`. Reject duration above the configured MVP ceiling before calling OpenAI. Return transcript to the caller but persist only provider/model/duration/cost metadata in the ledger.

- [ ] **Step 5: Run privacy, transcription, and backend checks**

Run: `npm test --workspace=backend -- privacy.middleware.test.ts --runInBand && npm test --workspace=backend -- --runInBand && npm run build --workspace=backend`

Expected: all tests pass; build exits 0.

- [ ] **Step 6: Commit**

```bash
git add backend/src
git commit -m "feat: enforce content-safe AI telemetry"
```

---

### Task 5: Establish encrypted on-device SQLite

**Execution gate:** Plan approval authorizes adding the SQLCipher configuration and testable JavaScript/TypeScript foundation. Do not run `npx expo prebuild`, `npx expo run:ios`, or a managed cloud build without a separate explicit approval when physical-device verification is reached.

**Files:**
- Modify: `mobile/package.json`
- Modify: `mobile/app.json`
- Modify: `mobile/tsconfig.json`
- Create: `mobile/jest.config.js`
- Create: `mobile/src/db/types.ts`
- Create: `mobile/src/db/schema.ts`
- Create: `mobile/src/db/migrations.ts`
- Create: `mobile/src/db/openDatabase.ts`
- Create: `mobile/src/db/__tests__/migrations.test.ts`

**Interfaces:**
- Produces: `openTaisaDatabase(): Promise<SQLiteDatabase>`, `runMigrations(db)`, and schema version 1.
- Consumed by: every mobile repository and export/restore.

- [ ] **Step 1: Add dependencies and test scripts**

Run from `mobile/`:

```bash
npx expo install expo-sqlite expo-crypto
npm install --save-dev jest jest-expo @types/jest
```

Add `"test": "jest"` and `"typecheck": "tsc --noEmit"`. Configure Jest with preset `jest-expo` and test roots under `src`.

- [ ] **Step 2: Enable SQLCipher in managed configuration**

```json
["expo-sqlite", { "useSQLCipher": true }]
```

Add this entry to `expo.plugins`. SQLCipher is unavailable in Expo Go; record the required development-build command in `SETUP.md` without executing a local eject or checked-in native project.

- [ ] **Step 3: Write failing migration tests against a `DatabaseLike` fake**

```ts
test('runs each migration once and advances user_version transactionally', async () => {
  const db = new FakeDatabase(0);
  await runMigrations(db);
  expect(db.userVersion).toBe(1);
  await runMigrations(db);
  expect(db.appliedStatements.filter(s => s.includes('CREATE TABLE conversations'))).toHaveLength(1);
});
```

- [ ] **Step 4: Define the schema**

Schema version 1 contains `profile`, `conversations`, `messages`, `goals`, `milestones`, `actions`, `evidence`, `memory_items`, `memory_sources`, `usage_receipts`, reserved `migration_state`, and FTS5 tables for message/evidence search. Foreign keys are enabled; all IDs and timestamps are supplied by the client.

- [ ] **Step 5: Implement key creation and encrypted open**

```ts
const KEY_NAME = 'taisa.database-key.v1';

async function getOrCreateKey(): Promise<string> {
  const existing = await SecureStore.getItemAsync(KEY_NAME);
  if (existing) return existing;
  const bytes = await Crypto.getRandomBytesAsync(32);
  const key = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
  await SecureStore.setItemAsync(KEY_NAME, key, { keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY });
  return key;
}

export async function openTaisaDatabase() {
  const db = await SQLite.openDatabaseAsync('taisa-local.db');
  const key = await getOrCreateKey();
  await db.execAsync(`PRAGMA key = "x'${key}'"; PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;`);
  await runMigrations(db);
  return db;
}
```

If the key is missing while the database file already exists, stop and present recovery; never generate a replacement key over an unreadable archive.

- [ ] **Step 6: Run unit checks and verify on a managed iPhone development build**

Run: `cd mobile && npm test -- --runInBand && npm run typecheck`

On device, create a record, restart the app, verify it persists, and verify opening the database without its SecureStore key fails. Record evidence in `docs/features/local-first-cutover-qa.md`.

- [ ] **Step 7: Commit**

```bash
git add mobile SETUP.md docs/features/local-first-cutover-qa.md
git commit -m "feat: add encrypted local data foundation"
```

---

### Task 6: Add focused local repositories

**Files:**
- Create: `mobile/src/repositories/profileRepository.ts`
- Create: `mobile/src/repositories/conversationRepository.ts`
- Create: `mobile/src/repositories/goalRepository.ts`
- Create: `mobile/src/repositories/actionRepository.ts`
- Create: `mobile/src/repositories/evidenceRepository.ts`
- Create: `mobile/src/repositories/memoryRepository.ts`
- Create: `mobile/src/repositories/__tests__/*.test.ts`

**Interfaces:**
- Produces: repository functions returning shared domain types; each mutation accepts a database transaction and an idempotency ID.
- Consumed by: context assembly, stores, and export/restore.

- [ ] **Step 1: Write repository contract tests**

Cover create/read/update/list for each entity, cascade behavior, FTS search, duplicate idempotency IDs, source traceability, and lifecycle filtering. Example:

```ts
test('transitioning a goal to superseded preserves its history and successor', async () => {
  await goals.insert(activeManagementGoal);
  await goals.supersede(activeManagementGoal.id, staffGoal, 'mutation-1');
  expect((await goals.get(activeManagementGoal.id))?.lifecycle).toBe('superseded');
  expect((await goals.get(staffGoal.id))?.supersedesId).toBe(activeManagementGoal.id);
});
```

- [ ] **Step 2: Run tests and confirm missing modules fail**

Run: `cd mobile && npm test -- repositories --runInBand`

- [ ] **Step 3: Implement one-responsibility repositories**

Repositories contain SQL mapping only. They do not call the gateway, decide confirmation policy, or mutate unrelated entities. Cross-entity operations receive a transaction from a domain service.

- [ ] **Step 4: Run repository and type checks**

Run: `cd mobile && npm test -- repositories --runInBand && npm run typecheck`

- [ ] **Step 5: Commit**

```bash
git add mobile/src/repositories
git commit -m "feat: add local career repositories"
```

---

### Task 7: Removed — no backend-data migration

**Approved reconciliation — 2026-08-10:** Baah confirmed there is no backend data to preserve.
This task was removed from product scope before implementation.

- [x] Do not create a backend export route, migration token, mobile importer, legacy archive, or
  device authority-migration marker.
- [x] Do not run a physical-device data-migration journey. The next device gate is Task 10
  recovery/privacy QA against the local-first archive.
- [x] Leave local SQLite schema migrations from Task 5 intact; they version the on-device schema
  and are not a legacy-data import mechanism.
- [x] Treat the existing `LegacyExportBundleV1` type and reserved `migration_state` table as unused
  pre-reconciliation artifacts. Neither is permission to add migration behavior.

---

### Task 8: Implement governed memory and bounded context assembly

**Files:**
- Create: `mobile/src/domain/memory/admission.ts`
- Create: `mobile/src/domain/memory/confirmationPolicy.ts`
- Create: `mobile/src/domain/memory/applyDelta.ts`
- Create: `mobile/src/domain/context/rankEvidence.ts`
- Create: `mobile/src/domain/context/assembleContext.ts`
- Create: `mobile/src/domain/**/__tests__/*.test.ts`

**Interfaces:**
- Produces: `requiresConfirmation(delta, state)`, `applyConfirmedDelta(tx, delta)`, `rankEvidence(query, candidates)`, and `assembleCoachingContext(input, repositories, limits)`.
- Consumed by: submission orchestration in Task 9.

- [ ] **Step 1: Write memory-policy tests from the approved rules**

Test that new/replacement goals, sensitive interpretations, fact promotion, preference/decision supersession, and merges require confirmation. Test that evidence linking, support increments, explicit action completion, and conversation archival are safe automatic operations.

- [ ] **Step 2: Write conflict and temporal tests**

Use the management-versus-Staff example. Assert the engine stages a question and a proposed transition rather than creating a second unrelated active direction or overwriting history.

- [ ] **Step 3: Implement pure policy functions**

```ts
export function requiresConfirmation(delta: MemoryDelta): boolean {
  if (delta.operation === 'support') return false;
  if (delta.operation === 'transition') return ['superseded', 'rejected', 'archived'].includes(delta.to);
  return ['goal', 'decision', 'preference'].includes(delta.candidate.type)
    || delta.candidate.provenance === 'ai-inferred';
}
```

Sensitive/identity-level flags are carried explicitly in the proposed delta schema and always return true.

- [ ] **Step 4: Write evidence-ranking and budget tests**

Assert ordering by direct entity link, shared goal/action, recency, then normalized text relevance. Assert at most 8 evidence excerpts, 50 memory items, 20 messages, and the configured character/token estimate.

- [ ] **Step 5: Implement deterministic context assembly**

The assembler returns both the gateway context and a local manifest of included IDs. The manifest is stored on-device with the response so “what did Taisa know?” is inspectable without gateway logs.

- [ ] **Step 6: Run domain tests and commit**

Run: `cd mobile && npm test -- domain --runInBand && npm run typecheck`

```bash
git add mobile/src/domain
git commit -m "feat: add governed career memory engine"
```

---

### Task 9: Cut the coaching flow over to private local capture and stateless submission

**Files:**
- Create: `mobile/src/services/coaching.ts`
- Create: `mobile/src/services/privateCapture.ts`
- Create: `mobile/src/services/__tests__/privateCapture.test.ts`
- Modify: `mobile/src/services/transcription.ts`
- Modify: `mobile/src/stores/chatStore.ts`
- Modify: `mobile/src/stores/threadStore.ts`
- Modify: `mobile/src/stores/careerStore.ts`
- Modify: `mobile/app/chat/index.tsx`

**Interfaces:**
- Consumes: Task 2 gateway, Task 6 repositories, and Task 8 context/memory functions.
- Produces: `savePrivateDraft`, `submitText`, `submitVoice`, `confirmProposal`, and local-first Zustand selectors.

- [ ] **Step 1: Write orchestration tests**

```ts
test('private save persists locally and never calls transcription or coaching', async () => {
  const saved = await service.savePrivateDraft({ conversationId: 'c1', content: 'Confidential launch detail' });
  expect(saved.status).toBe('private');
  expect(transcribe).not.toHaveBeenCalled();
  expect(coach).not.toHaveBeenCalled();
});

test('submit stores local user message, sends bounded context, and stages proposals', async () => {
  await service.submitText({ conversationId: 'c1', content: 'I may prefer Staff IC' });
  expect(coach).toHaveBeenCalledWith(expect.objectContaining({ context: expect.any(Object) }));
  expect(await messages.list('c1')).toHaveLength(2);
  expect(await proposals.listPending()).toHaveLength(1);
});
```

- [ ] **Step 2: Implement idempotent orchestration**

Generate one UUID request ID before the network call and persist a local pending submission. On retry, reuse the same request ID. The gateway returns no persisted session ID; local conversation/message IDs remain authoritative.

- [ ] **Step 3: Implement voice submission semantics**

Recording remains local until Submit. On Submit: upload once, store returned transcript locally, allow correction, then trigger coaching only after transcript confirmation. A transcription retry never records new audio or duplicates the local message.

- [ ] **Step 4: Replace store CRUD with repositories**

`fetchThreads`, `fetchThread`, profile reads/writes, goal/action operations, and search read from local repositories. Remove network calls to legacy CRUD routes from local-first stores. Keep Zustand as view state, not durable state.

- [ ] **Step 5: Add minimal validation UI wiring**

Use the current chat surface to expose Private Save, Submit, retry, and proposal confirmation. Do not redesign navigation, typography, animation, or Career screens in this plan.

- [ ] **Step 6: Run checks and physical-device journey**

Run: `cd mobile && npm test -- privateCapture --runInBand && npm run typecheck`

On device verify: private text produces zero gateway requests; submitted text produces one coaching request; submitted voice produces one transcription and one coaching request after transcript confirmation; force-quit and reopen preserves the complete conversation.

- [ ] **Step 7: Commit**

```bash
git add mobile
git commit -m "feat: run coaching from local career context"
```

---

### Task 10: Add encrypted recovery and prepare gated backend-route retirement

**Files:**
- Create: `mobile/src/services/exportArchive.ts`
- Create: `mobile/src/services/privacyGuard.ts`
- Create: `mobile/src/services/redactSubmission.ts`
- Create: `mobile/src/services/__tests__/exportArchive.test.ts`
- Create: `mobile/src/services/__tests__/privacyGuard.test.ts`
- Create: `mobile/src/services/__tests__/redactSubmission.test.ts`
- Modify: `mobile/app/(tabs)/you.tsx` minimally for export/restore actions
- Modify: `mobile/app/_layout.tsx` for optional unlock and app-switcher shielding
- Modify: `mobile/src/services/notifications.ts` to exclude private content
- Modify: `backend/src/index.ts`
- Modify: `docs/architecture.md`
- Modify: `docs/data-model.md`
- Modify: `docs/api.md`
- Modify: `docs/v1-status.md`
- Modify: `SETUP.md`
- Modify: `docs/features/local-first-cutover-qa.md`

**Interfaces:**
- Produces: `exportEncryptedArchive(passphrase)` and `restoreEncryptedArchive(uri, passphrase)`.
- Produces the recovery/privacy evidence required before a separately approved legacy-route
  retirement change; this ungated slice does not itself retire routes.

- [x] **Step 1: Write export/restore tests**

Test round-trip counts and hashes, wrong passphrase, corrupted archive, unsupported schema version,
insufficient free space, interrupted restore, preservation of the active database on every failure,
and rejection before artifact creation when nonterminal voice work still references audio.

- [x] **Step 2: Implement SQLCipher export with a separate passphrase**

Use SQLCipher `ATTACH DATABASE ... KEY`, `sqlcipher_export`, and `DETACH DATABASE` to create an encrypted export database in the document directory. Never reuse or expose the device database key. Require a passphrase of at least 12 characters and confirmation before export.

The export contains database state, including completed transcripts, but never bundles recorded
audio files. Before allocating an export URI, fail closed if any nonterminal coaching request still
has an `audio_uri`; the user must finish or abandon that voice work first.

- [x] **Step 3: Implement candidate restore and atomic promotion**

Open the selected archive as a candidate, validate its schema version, run integrity checks, compare required entity counts, close the active database, atomically promote the candidate, and reopen. Preserve the active database and SecureStore key until all checks pass.

- [ ] **Step 4: Complete managed-device recovery/privacy QA**

Export, remove the app's local data in a controlled test installation, restore, and verify conversations, goals, actions, evidence, memory sources, and search. Verify app-switcher shielding and content-free notification previews.

- [x] **Step 5: Add submission redaction and device privacy guards**

Implement a deterministic redaction preview that never calls AI. It detects user-selected names, organizations, project labels, and numeric metrics and returns both the redacted text and replacement map kept only in memory:

```ts
export function redactSubmission(input: string, selections: RedactionSelection[]): RedactionResult {
  return selections
    .sort((a, b) => b.start - a.start)
    .reduce((result, selection) => ({
      text: result.text.slice(0, selection.start) + `[${selection.kind.toUpperCase()}]` + result.text.slice(selection.end),
      replacements: [...result.replacements, selection],
    }), { text: input, replacements: [] as RedactionSelection[] });
}
```

Add optional LocalAuthentication unlock, obscure the root view while AppState is inactive/backgrounded, and ensure notifications contain generic copy such as “You have an open Taisa action” rather than titles or excerpts. Tests cover overlapping redactions, background transitions, lock cancellation, and notification payloads.

- [ ] **Step 6: Retire legacy user-data routes after recovery evidence and separate explicit approval**

After Step 4 passes and Baah explicitly approves this separate change, unmount profile, entries,
analyze, reviews, goals, action-items, trajectory, notifications, chat history, and today routes
from `backend/src/index.ts`. Keep only health, stateless coaching, and transcription. There is no
migration route or migration token to disable. Keep the unchanged legacy database as a BUILD/Ship
rollback artifact, not as a migration source.

- [x] **Step 7: Update canonical documentation**

Document the phone-authoritative data flow, stateless endpoints, local schema, the approved
no-migration decision, route-retirement gate, privacy limitations, backup limitations,
development-build requirement, and exact verification commands. Mark server-authoritative
diagrams/endpoints as legacy while mounted and retired only after Step 6 actually runs.

- [x] **Step 8: Run the complete verification matrix**

Run:

```bash
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
cd mobile && npm test -- --runInBand && npm run typecheck
cd .. && npm run verify:workflow
git diff --check
```

Expected: all available automated checks pass. Record SQLCipher, privacy, private-save, submission,
and restore device evidence separately; missing device evidence blocks Ship. No device migration
evidence is required because Task 7 was removed.

- [ ] **Step 9: Commit**

```bash
git add mobile backend docs SETUP.md
git commit -m "feat: add local recovery and privacy controls"
```

---

## Plan boundaries and follow-up plans

This plan delivers the Platform engine and the minimum validation client. It intentionally excludes the final Today/Conversation/Career/History information architecture, visual design, interaction polish, and SwiftUI implementation. After the engine passes device QA, write separate Product plans from Baah's UI designs.

Optional end-to-end encrypted cloud backup is also a separate future Platform spec. Do not convert manual encrypted export into cloud synchronization inside this plan.
