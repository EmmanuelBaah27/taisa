# Post-Send Streaming Transcription Implementation Plan

**Status:** Build and automated verification complete on 2026-08-15; managed-device QA pending.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream voice transcription into Taisa immediately after Send, auto-coach clear speech, move uncertain text into the composer, and create no interaction for unusable audio.

**Architecture:** Audio remains local until Send. The mobile client uploads the retained file once through an `XMLHttpRequest` transport that incrementally parses typed NDJSON events from the gateway; the gateway relays OpenAI transcription deltas, classifies the final recognition evidence, and preserves current cleanup and cost boundaries. The local capture service remains the durable authority: only a clear final transcript can atomically persist the user message and begin coaching, while uncertain text returns to transient composer state.

**Tech Stack:** React Native 0.81, Expo SDK 54, TypeScript, XMLHttpRequest incremental response text, Express, OpenAI transcription streaming, NDJSON, SQLite/SQLCipher, Jest.

**Spec:** `docs/superpowers/specs/2026-08-15-streaming-transcription-design.md`

## Global Constraints

- No audio leaves the device before the user taps Send.
- A clear final transcript automatically starts coaching; normal voice turns have no review screen.
- An uncertain final transcript becomes editable text composer state and starts zero coaching requests.
- No usable speech creates neither a conversation message nor a coaching request.
- Phrase blacklists and semantic judgments about whether a thought sounds sensible are forbidden.
- Provider credentials and raw confidence metadata remain inside the gateway.
- Request/response bodies, transcript text, audio paths, and provider payloads never enter logs.
- The existing durable request ID owns retries, stale-event rejection, usage, and idempotency.
- Mobile UI changes use existing NativeWind design-system components; no `StyleSheet.create()`.

## File Structure

- `shared/types/transcription.ts` — provider-independent stream events and final quality outcomes.
- `shared/index.ts` — exports the transcription contract.
- `backend/src/services/transcription/streamingTranscription.ts` — OpenAI stream adapter and final confidence/stability classification.
- `backend/src/routes/transcribe.ts` — multipart validation, NDJSON response, spend reservation, and temporary-file cleanup.
- `backend/src/__tests__/transcription.streaming.test.ts` — stream ordering, quality outcomes, privacy, cleanup, and abort coverage.
- `mobile/src/services/streamingTranscription.ts` — incremental XHR transport and NDJSON parser.
- `mobile/src/services/transcription.ts` — content-free public client error mapping and compatibility export removal.
- `mobile/src/services/privateCapture.ts` — durable clear/uncertain/no-speech transaction boundary.
- `mobile/src/stores/chatStore.ts` — provisional draft ownership and final UI outcome.
- `mobile/src/components/ui/VoiceComposer.tsx` — existing composer presentation for provisional and uncertain text.
- `mobile/app/chat/index.tsx` — screen orchestration only.
- `docs/api.md`, `docs/features/local-first-coaching-platform-qa-notes.md`, `docs/decisions/2026-08-15-voice-transcription-flow.md` — contract and QA evidence.

---

### Task 1: Define the provider-independent stream contract

**Files:**
- Create: `shared/types/transcription.ts`
- Modify: `shared/index.ts`
- Test: `backend/src/__tests__/transcription.streaming.test.ts`

**Interfaces:**
- Produces: `TranscriptionStreamEvent`, `TranscriptionQuality`, `TranscriptionCompletedData`, and `isTranscriptionStreamEvent(value)`.
- Consumes: no earlier task interfaces.

- [ ] **Step 1: Write the failing contract test**

```ts
import { isTranscriptionStreamEvent } from '@taisa/shared';

test('accepts typed deltas and rejects provider-shaped or content-ambiguous events', () => {
  expect(isTranscriptionStreamEvent({
    type: 'transcript.delta',
    requestId: '11111111-1111-4111-8111-111111111111',
    sequence: 1,
    delta: 'I led',
  })).toBe(true);
  expect(isTranscriptionStreamEvent({ type: 'transcript.delta', token_logprobs: [] })).toBe(false);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `npm test --workspace=backend -- --runInBand src/__tests__/transcription.streaming.test.ts`

Expected: FAIL because `isTranscriptionStreamEvent` is not exported.

- [ ] **Step 3: Implement the exact shared contract**

```ts
export type TranscriptionQuality = 'clear' | 'uncertain';

export interface TranscriptionCompletedData {
  transcript: string;
  durationSeconds: number;
  quality: TranscriptionQuality;
  usage: UsageReceipt;
}

export type TranscriptionStreamEvent =
  | { type: 'transcript.delta'; requestId: string; sequence: number; delta: string }
  | ({ type: 'transcript.completed'; requestId: string; sequence: number } & TranscriptionCompletedData)
  | { type: 'transcript.no_speech'; requestId: string; sequence: number }
  | { type: 'transcript.failed'; requestId: string; sequence: number; code: 'TRANSCRIPTION_FAILED' };
```

Implement `isTranscriptionStreamEvent` with explicit object, UUID-shaped request ID, non-negative integer sequence, finite positive duration, `UsageReceipt`, and discriminant checks. It must reject unknown keys that expose provider confidence structures on the wire.

- [ ] **Step 4: Run the contract test and shared consumer build**

Run: `npm test --workspace=backend -- --runInBand src/__tests__/transcription.streaming.test.ts && npm run build --workspace=backend`

Expected: PASS.

- [ ] **Step 5: Commit the contract**

```bash
git add shared/types/transcription.ts shared/index.ts backend/src/__tests__/transcription.streaming.test.ts
git commit -m "feat: define transcription stream contract"
```

---

### Task 2: Adapt OpenAI streaming transcription behind a quality boundary

**Files:**
- Create: `backend/src/services/transcription/streamingTranscription.ts`
- Modify: `backend/src/__tests__/transcription.streaming.test.ts`

**Interfaces:**
- Consumes: `TranscriptionStreamEvent`, `TranscriptionCompletedData` from Task 1.
- Produces:

```ts
export interface StreamingTranscriptionInput {
  requestId: string;
  file: File;
  model: string;
  durationSeconds: number;
  usage: UsageReceipt;
}

export type ProviderTranscriptionEvent =
  | { type: 'transcript.text.delta'; delta: string; logprobs?: Array<{ logprob?: number }> }
  | { type: 'transcript.text.done'; text: string; logprobs?: Array<{ logprob?: number }> };

export function classifyTranscriptionEvidence(input: {
  transcript: string;
  speechDetected: boolean;
  tokenLogprobs: readonly number[];
  materialRevisionRatio: number;
}): 'clear' | 'uncertain' | 'no-speech';

export async function* streamTranscription(...): AsyncGenerator<TranscriptionStreamEvent>;
```

- [ ] **Step 1: Write failing classifier tests**

```ts
test.each([
  [{ transcript: '', speechDetected: false, tokenLogprobs: [], materialRevisionRatio: 0 }, 'no-speech'],
  [{ transcript: 'I led the review', speechDetected: true, tokenLogprobs: [-0.12, -0.18], materialRevisionRatio: 0.05 }, 'clear'],
  [{ transcript: 'unclear draft', speechDetected: true, tokenLogprobs: [-1.3, -1.1], materialRevisionRatio: 0.1 }, 'uncertain'],
  [{ transcript: 'changing draft', speechDetected: true, tokenLogprobs: [-0.2], materialRevisionRatio: 0.55 }, 'uncertain'],
])('classifies recognition evidence without judging phrase meaning', (input, expected) => {
  expect(classifyTranscriptionEvidence(input)).toBe(expected);
});
```

Add a case proving `Thanks for watching` is `clear` when backed by strong speech evidence; the classifier must never special-case its words.

- [ ] **Step 2: Run tests and verify RED**

Run: `npm test --workspace=backend -- --runInBand src/__tests__/transcription.streaming.test.ts`

Expected: FAIL because the adapter and classifier do not exist.

- [ ] **Step 3: Implement the classifier with named policy constants**

```ts
const MIN_MEAN_TOKEN_LOGPROB = -0.8;
const MAX_LOW_CONFIDENCE_TOKEN_RATIO = 0.25;
const LOW_CONFIDENCE_TOKEN_LOGPROB = -1;
const MAX_MATERIAL_REVISION_RATIO = 0.35;
```

Return `no-speech` only when speech evidence is absent or the normalized transcript is empty. Return `uncertain` when token evidence exists and either the mean or low-confidence ratio fails, or material revision ratio exceeds the maximum. Missing provider confidence is `uncertain`, not `clear`.

- [ ] **Step 4: Write failing stream adapter tests**

Use an injected async iterable. Assert ordered sequence numbers, exact delta concatenation, one terminal event, no provider fields in emitted events, and `quality: 'clear' | 'uncertain'` only on completion.

- [ ] **Step 5: Implement the provider adapter**

Call OpenAI with:

```ts
{
  file,
  model,
  language: 'en',
  stream: true,
  response_format: 'json',
  include: ['logprobs'],
  chunking_strategy: { type: 'server_vad', threshold: 0.8 },
  temperature: 0,
}
```

Accumulate deltas and token log probabilities internally. Track material revisions only from provider completion corrections; never send confidence arrays to mobile. Yield exactly one terminal event.

- [ ] **Step 6: Run adapter tests and backend build**

Run: `npm test --workspace=backend -- --runInBand src/__tests__/transcription.streaming.test.ts && npm run build --workspace=backend`

Expected: PASS with no logged transcript content.

- [ ] **Step 7: Commit the provider boundary**

```bash
git add backend/src/services/transcription/streamingTranscription.ts backend/src/__tests__/transcription.streaming.test.ts
git commit -m "feat: classify streaming transcription quality"
```

---

### Task 3: Stream typed NDJSON from the transcription route

**Files:**
- Modify: `backend/src/routes/transcribe.ts`
- Modify: `backend/src/__tests__/transcription.streaming.test.ts`
- Modify: `backend/src/__tests__/privacy.middleware.test.ts`

**Interfaces:**
- Consumes: `streamTranscription(input, provider)` from Task 2.
- Produces: `POST /api/v1/transcribe` with `application/x-ndjson` response; one JSON event per newline.

- [ ] **Step 1: Write failing route tests**

Cover:

```ts
expect(response.headers['content-type']).toMatch(/application\/x-ndjson/);
expect(parseNdjson(response.text).map((event) => event.type)).toEqual([
  'transcript.delta',
  'transcript.delta',
  'transcript.completed',
]);
```

Also assert:

- no provider call occurs for invalid duration, size, missing configuration, or exhausted cost ceiling;
- provider failure produces one content-free `transcript.failed` event;
- client abort invokes iterator cleanup and deletes the temporary audio file;
- clear, uncertain, and no-speech provider calls commit one usage receipt because provider work occurred;
- response and logs contain no transcript fixture when failure or cleanup fails;
- OpenAI retries remain disabled.

- [ ] **Step 2: Run route tests and verify RED**

Run: `npm test --workspace=backend -- --runInBand src/__tests__/transcription.streaming.test.ts src/__tests__/privacy.middleware.test.ts`

Expected: FAIL because `/transcribe` returns one JSON envelope.

- [ ] **Step 3: Implement the NDJSON response lifecycle**

After all pre-provider validation:

```ts
res.status(200);
res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
res.setHeader('Cache-Control', 'no-store');
res.flushHeaders();

for await (const event of streamTranscription(input, provider)) {
  if (res.destroyed) break;
  res.write(`${JSON.stringify(event)}\n`);
}
res.end();
```

Use `req.on('aborted', ...)` and `res.on('close', ...)` to abort provider iteration. Keep reservation commit/release and `fs.promises.rm` in one `finally` block. Do not encode private error messages into terminal events.

- [ ] **Step 4: Remove the temporary threshold experiment**

Delete `containsDetectedSpeech`, `containsIntelligibleSpeech`, `verbose_json` segment thresholds, and their interim tests from `privacy.middleware.test.ts`. Their behavior is superseded by the provider-independent classifier and stream tests; retain upload, spend, privacy, and cleanup coverage.

- [ ] **Step 5: Run backend route and privacy verification**

Run: `npm test --workspace=backend -- --runInBand src/__tests__/transcription.streaming.test.ts src/__tests__/privacy.middleware.test.ts && npm run build --workspace=backend`

Expected: PASS.

- [ ] **Step 6: Commit the streaming route**

```bash
git add backend/src/routes/transcribe.ts backend/src/__tests__/transcription.streaming.test.ts backend/src/__tests__/privacy.middleware.test.ts
git commit -m "feat: stream transcription events from gateway"
```

---

### Task 4: Parse incremental NDJSON on mobile with abort and stale-request safety

**Files:**
- Create: `mobile/src/services/streamingTranscription.ts`
- Create: `mobile/src/services/__tests__/streamingTranscription.test.ts`
- Modify: `mobile/src/services/transcription.ts`
- Modify: `mobile/src/services/__tests__/transcription.test.ts`

**Interfaces:**
- Consumes: `TranscriptionStreamEvent`, `isTranscriptionStreamEvent` from Task 1; installation ID and device credential from existing services.
- Produces:

```ts
export interface StreamingTranscriptionRequest {
  requestId: string;
  audioUri: string;
  durationSeconds: number;
}

export interface StreamingTranscriptionSubscription {
  completed: Promise<Extract<TranscriptionStreamEvent, { type: 'transcript.completed' | 'transcript.no_speech' }>>;
  abort(): void;
}

export function createStreamingTranscriptionClient(dependencies: {
  createRequest(): XMLHttpRequest;
  getInstallationId(): Promise<string>;
  getDeviceCredential(): Promise<string | null>;
  baseUrl: string;
}): (request: StreamingTranscriptionRequest, onEvent: (event: TranscriptionStreamEvent) => void) => Promise<StreamingTranscriptionSubscription>;
```

- [ ] **Step 1: Write failing incremental parser tests**

Use a fake XHR that advances `responseText` through split boundaries such as:

```ts
'{"type":"transcript.del'
'ta",...}\n{"type":"transcript.completed",...}\n'
```

Assert exactly-once ordered delivery, buffering of incomplete lines, rejection of malformed/unknown events, content-free public errors, Authorization/device headers, multipart fields, and `abort()` behavior.

- [ ] **Step 2: Run tests and verify RED**

Run: `cd mobile && npm test -- --runInBand src/services/__tests__/streamingTranscription.test.ts`

Expected: FAIL because the client does not exist.

- [ ] **Step 3: Implement the XHR transport**

Track `consumedResponseLength`, append only new response text on `onprogress`, split complete newline records, and validate every parsed record before delivery. Set:

```ts
xhr.open('POST', `${baseUrl}/transcribe`);
xhr.setRequestHeader('x-user-id', installationId);
xhr.setRequestHeader('x-request-id', request.requestId);
if (credential) xhr.setRequestHeader('Authorization', `Bearer ${credential}`);
```

Do not set `Content-Type`; XHR must add the multipart boundary for `FormData`. Reject non-2xx, timeout, abort-before-terminal, malformed terminal, duplicate terminal, and sequence regression as `TranscriptionClientError` without copying response content.

- [ ] **Step 4: Retire the Axios batch client**

Keep `TranscriptionClientError` as the public content-free error. Replace `requestTranscription`/`transcribeAudio` exports with the streaming client export. Update tests so the words “Thanks for watching” are accepted when a validated clear completion carries them; phrase content is never a client decision.

- [ ] **Step 5: Run mobile transport tests and typecheck**

Run: `cd mobile && npm test -- --runInBand src/services/__tests__/streamingTranscription.test.ts src/services/__tests__/transcription.test.ts && npm run typecheck`

Expected: PASS.

- [ ] **Step 6: Commit the mobile transport**

```bash
git add mobile/src/services/streamingTranscription.ts mobile/src/services/transcription.ts mobile/src/services/__tests__/streamingTranscription.test.ts mobile/src/services/__tests__/transcription.test.ts
git commit -m "feat: stream transcription events on mobile"
```

---

### Task 5: Make durable capture distinguish clear, uncertain, and no-speech outcomes

**Files:**
- Modify: `mobile/src/services/privateCapture.ts`
- Modify: `mobile/src/services/__tests__/privateCapture.test.ts`
- Modify: `mobile/src/repositories/coachingRequestRepository.ts`
- Modify: `mobile/src/db/migrations.ts`
- Modify: `mobile/src/db/__tests__/migrations.test.ts`

**Interfaces:**
- Consumes: streaming completion contract from Tasks 1 and 4.
- Produces:

```ts
export type VoiceSubmissionResult =
  | CompletedSubmissionResult
  | { status: 'transcription-uncertain'; requestId: string; transcript: string }
  | { status: 'no-speech'; requestId: string };

submitVoiceAndCoach(input: {
  conversationId: string;
  audioUri: string;
  durationSeconds: number;
  typedClarification?: string;
  preferredInputMode?: LocalConversation['preferredInputMode'];
  intentId?: string;
  onTranscriptEvent?: (event: TranscriptionStreamEvent) => void;
}): Promise<VoiceSubmissionResult>;
```

- [ ] **Step 1: Write failing durable-state tests**

Prove:

- delta callbacks never write partial text to SQLite;
- clear completion writes one user message, one usage receipt, and invokes coaching once;
- uncertain completion persists request status plus retained audio ownership, writes no user message, and invokes coaching zero times;
- no-speech records a terminal non-coaching request state, writes no message, invokes coaching zero times, and queues audio cleanup;
- retry reuses request ID and audio without duplicating usage or messages;
- process restart can hydrate uncertain text without treating it as coaching context.

- [ ] **Step 2: Run service tests and verify RED**

Run: `cd mobile && npm test -- --runInBand src/services/__tests__/privateCapture.test.ts src/db/__tests__/migrations.test.ts`

Expected: FAIL because streaming outcomes and statuses do not exist.

- [ ] **Step 3: Add explicit durable statuses**

Add `transcription-uncertain` and `no-speech` to the repository union and migration rebuild/check-constraint path. Preserve existing databases and add migration assertions from the immediately previous schema version.

- [ ] **Step 4: Implement the transaction boundary**

Forward deltas through `onTranscriptEvent` without persistence. On terminal:

- `clear`: persist final transcript/usage, then continue the existing coaching transaction;
- `uncertain`: persist final transcript and status, retain audio, return without coaching;
- `no-speech`: persist terminal status, enqueue/discard audio according to current cleanup ownership, return without coaching;
- failed/aborted: preserve current retryable `transcription-failed` semantics.

- [ ] **Step 5: Run durable service and migration tests**

Run: `cd mobile && npm test -- --runInBand src/services/__tests__/privateCapture.test.ts src/db/__tests__/migrations.test.ts`

Expected: PASS.

- [ ] **Step 6: Commit durable outcomes**

```bash
git add mobile/src/services/privateCapture.ts mobile/src/services/__tests__/privateCapture.test.ts mobile/src/repositories/coachingRequestRepository.ts mobile/src/db/migrations.ts mobile/src/db/__tests__/migrations.test.ts
git commit -m "feat: persist safe voice transcription outcomes"
```

---

### Task 6: Transfer provisional and uncertain text into the existing composer

**Files:**
- Modify: `mobile/src/stores/chatStore.ts`
- Modify: `mobile/src/stores/__tests__/localStores.test.ts`
- Modify: `mobile/src/services/voiceComposerState.ts`
- Modify: `mobile/src/services/__tests__/voiceComposerState.test.ts`
- Modify: `mobile/src/components/ui/VoiceComposer.tsx`
- Modify: `mobile/src/components/ui/__tests__/ChatSurfaces.test.ts`
- Modify: `mobile/app/chat/index.tsx`
- Modify: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`

**Interfaces:**
- Consumes: `VoiceSubmissionResult` from Task 5.
- Produces store state:

```ts
provisionalTranscript: string;
transcriptionOutcome: 'none' | 'streaming' | 'uncertain' | 'no-speech';
```

and action:

```ts
clearTranscriptionDraft(): void;
```

- [ ] **Step 1: Write failing store ownership tests**

Assert that ordered deltas for the active request update `provisionalTranscript`; stale request events are ignored; clear completion clears provisional state and shows the persisted message; uncertain completion returns the transcript to editable text mode; no-speech clears it and sets the recoverable error; retry/close clears abandoned provisional state.

- [ ] **Step 2: Write failing composer presentation tests**

Assert:

- streamed text appears in the existing text field while disabled for submission;
- uncertain completion enables editing and the normal text Send action;
- clear completion never pauses for review;
- no-speech copy is exactly `I couldn’t hear any clear speech. Try recording again or use the keyboard.`;
- there is no confirmation CTA or transcript-review card in this flow.

- [ ] **Step 3: Run store and UI tests and verify RED**

Run: `cd mobile && npm test -- --runInBand src/stores/__tests__/localStores.test.ts src/services/__tests__/voiceComposerState.test.ts src/components/ui/__tests__/ChatSurfaces.test.ts src/navigation/__tests__/localCaptureRoutes.test.ts`

Expected: FAIL because provisional/uncertain state is absent.

- [ ] **Step 4: Implement store event ownership**

Capture the active request ID before opening the stream. Apply deltas only when both request ID and conversation generation still match. Set final state:

```ts
if (result.status === 'transcription-uncertain') {
  setIfCurrent(ownership, {
    provisionalTranscript: '',
    transcriptionOutcome: 'uncertain',
    phase: 'idle',
  });
}
```

Return the uncertain transcript to the screen as store state; do not insert it into `currentMessages`.

- [ ] **Step 5: Wire the existing design-system composer**

Use the existing `VoiceComposer` text field and tokens. During streaming, display `provisionalTranscript` as read-only/disabled text with a `Transcribing…` label. On uncertain completion, switch composer mode to text, copy the final transcript into `draft`, focus the input, and allow ordinary text submission. No new visual primitive or design-system component is required.

Remove the interim amplitude-modulation and hardcoded provider-threshold experiments only after the stream-quality path is covered. Retain on-device activity for waveform/no-speech hints, but it is not the sole authority.

- [ ] **Step 6: Run mobile behavior tests and typecheck**

Run: `cd mobile && npm test -- --runInBand src/stores/__tests__/localStores.test.ts src/services/__tests__/voiceComposerState.test.ts src/components/ui/__tests__/ChatSurfaces.test.ts src/navigation/__tests__/localCaptureRoutes.test.ts && npm run typecheck`

Expected: PASS.

- [ ] **Step 7: Commit the composer flow**

```bash
git add mobile/src/stores/chatStore.ts mobile/src/stores/__tests__/localStores.test.ts mobile/src/services/voiceComposerState.ts mobile/src/services/__tests__/voiceComposerState.test.ts mobile/src/components/ui/VoiceComposer.tsx mobile/src/components/ui/__tests__/ChatSurfaces.test.ts mobile/app/chat/index.tsx mobile/src/navigation/__tests__/localCaptureRoutes.test.ts
git commit -m "feat: stream uncertain voice text into composer"
```

---

### Task 7: Document, verify, and run managed-device QA

**Files:**
- Modify: `docs/api.md`
- Modify: `docs/features/local-first-coaching-platform-qa-notes.md`
- Modify: `docs/features/local-first-cutover-qa.md`
- Modify: `docs/decisions/2026-08-15-voice-transcription-flow.md`
- Modify: `docs/workflow.md`

**Interfaces:**
- Consumes: completed cross-stack behavior from Tasks 1–6.
- Produces: review-ready verification evidence and an updated storyworthy decision record.

- [ ] **Step 1: Update API and architecture documentation**

Document `application/x-ndjson`, every public event shape, ordering/terminal guarantees, request ID ownership, abort/retry behavior, and the fact that raw confidence never crosses the gateway.

- [ ] **Step 2: Update QA evidence and decision consequences**

Record the original `Thanks for watching` hallucination, why phrase filtering and single-threshold tuning were rejected, and the final clear/uncertain/no-speech policy. Do not mark device checks complete before Baah performs them.

- [ ] **Step 3: Run the complete cross-stack verification matrix**

Run:

```bash
npm test --workspace=backend -- --runInBand
npm run build --workspace=backend
cd mobile && npm test -- --runInBand
cd mobile && npm run typecheck
bash scripts/verify-workflow.sh
git diff --check
```

Expected: all commands exit 0; backend and mobile suites report zero failures.

- [ ] **Step 4: Perform managed-device cases**

On the managed iPhone verify:

1. Audio remains local and the backend sees zero requests before Send.
2. Clear speech begins showing text promptly after Send and automatically produces exactly one coaching response.
3. Silence and steady background noise produce the no-speech error and zero coaching requests.
4. Unintelligible or deliberately unclear speech leaves the best transcript editable in the text composer and produces zero coaching requests.
5. Editing and sending uncertain text uses the normal text path and produces exactly one coaching response.
6. Network interruption retains the recording; retry reuses it without duplicate messages or usage.
7. Force-quit during transcription and reopen restores a safe retryable state without partial transcript messages.

- [ ] **Step 5: Commit documentation and verification evidence**

```bash
git add docs/api.md docs/features/local-first-coaching-platform-qa-notes.md docs/features/local-first-cutover-qa.md docs/decisions/2026-08-15-voice-transcription-flow.md docs/workflow.md
git commit -m "docs: verify post-send streaming transcription"
```

---

## Plan Approval Summary

This plan replaces the current batch Whisper response with a post-Send stream. It adds no mandatory confirmation and sends no audio before Send. Clear recognition continues automatically to coaching; uncertain recognition becomes editable composer text; no usable speech becomes an error. The gateway owns provider confidence and privacy, while the durable local request remains the authority for retries and exactly-once coaching.

**Design-system impact:** Reuse `VoiceComposer`, `ChatComposerDock`, and `ChatConversationSurface`. No new DS component is planned. The only presentation extension is a typed provisional/read-only state on the existing composer, using current tokens and NativeWind classes.
