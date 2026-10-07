# Swift Native Audio and Conversation Streaming Implementation Plan

> **Status:** Approved; Build in progress.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native Apple audio and two-stage streaming foundation for durable, multi-turn Taisa coaching conversations on iPhone and iPad.

**Architecture:** A protocol-backed `VoiceSessionCoordinator` owns the durable turn state machine and checkpoints every side-effect boundary in encrypted storage. Local audio capture remains isolated from networking; strict NDJSON transcription and coaching clients feed ephemeral deltas while only validated terminal events commit messages. The gateway adds durable idempotency receipts and a genuine ordered coaching stream so reconnect and relaunch cannot create duplicate paid work.

**Tech Stack:** Swift 6, Swift Concurrency, AVFoundation, Network, GRDB/SQLCipher, Swift Testing/XCTest, Node 22, TypeScript 5, Express, Zod, NDJSON, Jest.

**Spec:** `docs/superpowers/specs/2026-10-07-swift-native-audio-streaming-design.md`

## Global Constraints

- iOS 17 and macOS 14 remain the Swift package platform floors.
- Audio stays local until explicit Send and is never synchronized, backed up, exported, logged, or added to signed-build evidence.
- A conversation and each turn keep stable UUID identities; transcription and coaching use distinct stable request IDs and idempotency keys.
- Partial transcript and coaching deltas are ephemeral; only validated terminal results enter encrypted history.
- Automatic retry is bounded and allowed only when replay is proven side-effect safe; ambiguous paid work becomes `resumeRequiresConfirmation`.
- Views do not own AVAudioSession, files, upload tasks, sequence reconciliation, retry policy, SQL, or provider concerns.
- The existing TypeScript schemas and shared JSON fixtures remain the portable cross-language authority.
- No final Conversation UI, React Native parity, text-to-speech, live pre-Send transcription, barge-in, audio sync, or account work is included.
- No provider/API configuration, signing, capability, or paid-infrastructure mutation is authorized by this plan.
- Follow TDD for every executable change; diagnose unexpected failures before changing implementation.

## Review Focus

- Disconnect after provider invocation but before acknowledgement must never cause a second paid coaching attempt; Task 2 tests receipt reconciliation and ambiguous outcomes.
- Duplicate, conflicting, missing, oversized, unknown, or post-terminal NDJSON events must fail closed without committing messages; Tasks 1 and 6 test every class.
- Relaunch at every checkpoint must resume only the saved stage and never re-upload audio after an accepted transcript; Tasks 4 and 7 test stage reconstruction.
- Interruption, route loss, media reset, low storage, and permission revocation must preserve one logical turn or produce an actionable terminal state; Task 5 tests adapter events and ownership.
- Cleanup failure must preserve retry metadata while successful cleanup must remove audio without entering sync, backup, export, logs, or evidence; Tasks 3, 4, and 8 test retention boundaries.

---

### Task 1: Define portable coaching-stream contracts and fixtures

**Files:**
- Create: `shared/types/coachingStream.ts`
- Create: `shared/fixtures/coaching-stream/*.json`
- Create: `scripts/native-contracts/verify-coaching-fixtures.mjs`
- Create: `scripts/native-contracts/__tests__/verify-coaching-fixtures.test.mjs`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaContracts/CoachingStreamEvent.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaContracts/StrictNDJSONDecoder.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaContractsTests/CoachingStreamEventTests.swift`
- Modify: `shared/index.ts`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`

**Interfaces:**
- Consumes: `CoachingResponse`, `UsageReceipt`, UUID request IDs, and the transcription envelope discipline.
- Produces: `CoachingStreamEvent`, `isCoachingStreamEvent(value)`, Swift `CoachingStreamEvent`, and a bounded `StrictNDJSONDecoder` accepting the next expected sequence and terminal state.

- [ ] **Step 1: Write failing TypeScript fixture tests**

```js
test('accepts ordered delta, completed, and failed fixtures', () => {
  assert.deepEqual(verifyCoachingFixtures(fixtures).validFailures, []);
});
test('rejects wrong request, gap, duplicate conflict, unknown field, and post-terminal data', () => {
  assert.deepEqual(verifyCoachingFixtures(fixtures).invalidAccepted, []);
});
```

- [ ] **Step 2: Run RED**

Run: `node --test scripts/native-contracts/__tests__/verify-coaching-fixtures.test.mjs`  
Expected: FAIL because the coaching fixture verifier and schema do not exist.

- [ ] **Step 3: Implement the strict portable event family**

```ts
export type CoachingStreamEvent =
  | { type: 'coaching.delta'; requestId: string; sequence: number; delta: string }
  | { type: 'coaching.completed'; requestId: string; sequence: number; response: CoachingResponse; idempotencyReceipt: string }
  | { type: 'coaching.failed'; requestId: string; sequence: number; code: CoachingStreamFailureCode; retryable: boolean };
```

Validate exact fields, UUID identity, non-negative contiguous sequence, one terminal, bounded line size, and no data after terminal. Mirror the models in Swift without accepting unknown fields.

- [ ] **Step 4: Run TypeScript GREEN and Swift RED/GREEN**

Run: `node --test scripts/native-contracts/__tests__/verify-coaching-fixtures.test.mjs scripts/native-contracts/__tests__/verify-transcription-fixtures.test.mjs`  
Expected: PASS.

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TaisaContractsTests`  
Expected before implementation: FAIL because the Swift decoder is missing. Expected after implementation: PASS.

- [ ] **Step 5: Commit**

```bash
git add shared scripts/native-contracts apple/Packages/TaisaFoundation
git commit -m "feat: define portable coaching stream contracts"
```

### Task 2: Add durable gateway idempotency and genuine coaching streaming

**Files:**
- Create: `backend/src/services/coaching/coachingIdempotencyStore.ts`
- Create: `backend/src/services/coaching/streamingCoaching.ts`
- Create: `backend/src/__tests__/coaching.streaming.test.ts`
- Create: `backend/src/__tests__/coaching.idempotency.test.ts`
- Modify: `backend/src/db/schema.sql`
- Modify: `backend/src/db/connection.ts`
- Modify: `backend/src/routes/coaching.ts`
- Modify: `backend/src/services/coaching/coachingGateway.ts`
- Modify: `backend/src/services/usage/costLedger.ts`
- Modify: `docs/api.md`
- Modify: `docs/data-model.md`

**Interfaces:**
- Consumes: `CoachingRequest`, `CoachingResponse`, provider attempt observer, cost reservation, `Idempotency-Key`, and `x-request-id`.
- Produces: `POST /api/v1/coaching/respond/stream`, `GET /api/v1/coaching/requests/:requestId`, `CoachingIdempotencyStore.begin/reconcile/complete/fail`, and ordered NDJSON events from Task 1.

- [ ] **Step 1: Write failing gateway tests**

```ts
it('replays one authoritative completion for duplicate idempotency keys', async () => {
  const first = await postStream(request, key);
  const second = await postStream(request, key);
  expect(provider.calls).toHaveLength(1);
  expect(second.terminal).toEqual(first.terminal);
});

it('reports ambiguous work without starting another provider attempt', async () => {
  store.seed({ key, requestId, status: 'provider-started' });
  expect(await reconcile(requestId)).toMatchObject({ status: 'ambiguous' });
  expect(provider.calls).toHaveLength(0);
});
```

- [ ] **Step 2: Run RED**

Run: `npm test --workspace=backend -- --runInBand coaching.streaming.test.ts coaching.idempotency.test.ts`  
Expected: FAIL because the stream route and durable receipt store do not exist.

- [ ] **Step 3: Implement atomic receipts, settlement, stream, and lookup**

Persist request hash, idempotency key, lifecycle status, attempt/cost status, terminal response, and content-free failure metadata. Reserve/settle cost against the same transaction identity. Emit deltas only as presentation events; validate the final structured response before `coaching.completed`. A key reused with a different request hash returns a contract error.

- [ ] **Step 4: Verify GREEN and legacy compatibility**

Run: `npm test --workspace=backend -- --runInBand coaching.streaming.test.ts coaching.idempotency.test.ts coaching.routes.test.ts coachingGateway.test.ts coaching.rateLimit.test.ts`  
Expected: PASS with one provider invocation and one settlement per stable key.

Run: `npm run build --workspace=backend && npm run build --workspace=shared`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend shared docs/api.md docs/data-model.md
git commit -m "feat: stream coaching with durable idempotency"
```

### Task 3: Persist recoverable native conversation turns atomically

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Models/VoiceTurnRecord.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Repositories/ConversationTurnRepository.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/ConversationTurnRepositoryTests.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaSchema.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaMigrator.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaRecovery/SnapshotService.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaSync/SyncProjection.swift`

**Interfaces:**
- Consumes: encrypted `TaisaStore`, `ConversationRecord`, append-only `MessageRecord`, and mutation context.
- Produces: `VoiceTurnRecord`, `VoiceTurnState`, `VoiceTurnStage`, and `ConversationTurnRepository.checkpoint(_:messages:cleanup:)` as one database transaction.

- [ ] **Step 1: Write failing repository tests**

```swift
@Test func checkpointQueuesTurnBeforeAnyTransportStarts() async throws { /* queued row and outbox metadata commit together */ }
@Test func completedTurnCommitsBothMessagesAndReceiptAtomically() async throws { /* no partial history */ }
@Test func snapshotAndSyncExcludeAudioReferencesAndEphemeralText() async throws { /* explicit projection assertion */ }
```

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter ConversationTurnRepositoryTests`  
Expected: FAIL because the record, migration, and repository do not exist.

- [ ] **Step 3: Implement schema, repository, and exclusion rules**

Store stable identities, stage, audio fingerprint/reference, transcript decision, retry metadata, receipts, cleanup state, and final message IDs. Do not store partial deltas or audio bytes. Reject illegal terminal-to-active regressions and request-identity mutation.

- [ ] **Step 4: Verify GREEN plus recovery/sync regressions**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter 'ConversationTurnRepositoryTests|SnapshotTests|SyncProjection'`  
Expected: PASS and serialized archives/projections contain no audio path or bytes.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: persist recoverable voice conversation turns"
```

### Task 4: Build the pure voice-session state machine

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceTurnState.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceSessionCommand.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceSessionEffect.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceSessionReducer.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaVoiceTests/VoiceSessionReducerTests.swift`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`

**Interfaces:**
- Consumes: stable conversation/turn/request identities and typed capture/stream/repository outcomes.
- Produces: pure `VoiceSessionReducer.reduce(state:command:) throws -> Transition` with durable next state plus ordered effects.

- [ ] **Step 1: Write the exhaustive failing transition table**

Cover record, pause, resume, Send, cancel, discard, clear/uncertain/no-speech terminals, transcript confirmation, coaching completion, recoverable/terminal failure, retry, ambiguous-paid confirmation, cleanup, and next turn under the same conversation.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter VoiceSessionReducerTests`  
Expected: FAIL because `TaisaVoice` and the reducer do not exist.

- [ ] **Step 3: Implement the minimal pure reducer**

Every transition returns a checkpoint before an external side effect. Illegal commands return typed errors without changing state. Cancellation preserves recoverable data; discard is terminal and authorizes deletion.

- [ ] **Step 4: Verify GREEN and transition completeness**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter VoiceSessionReducerTests`  
Expected: PASS for every allowed edge and every forbidden regression.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: define durable voice session state machine"
```

### Task 5: Implement local audio capture and lifecycle ownership

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaAudio/AudioCaptureService.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaAudio/AudioSessionAdapter.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaAudio/AudioRecorderAdapter.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaAudio/AudioFileStore.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaAudioTests/AudioCaptureServiceTests.swift`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Modify: `apple/Config/TaisaInfo.plist`
- Modify: `apple/Config/TaisaPersonalInfo.plist`

**Interfaces:**
- Consumes: one stable turn ID, deliberate authorization command, app lifecycle events, AVAudioSession notifications, and protected app-support storage.
- Produces: `AudioCaptureEvent`, `FinalizedAudio(fileID:url:duration:byteCount:sha256:)`, metering samples, and idempotent `start/pause/resume/finalize/cancel/discard` methods.

- [ ] **Step 1: Write failing adapter-driven tests**

```swift
@Test func pauseAndResumeKeepOneTurnAndOneTimeline() async throws { /* same turn/file manifest */ }
@Test func interruptionAndRouteLossNeverSilentlyCreateANewRecording() async throws { /* typed event */ }
@Test func lowStoragePreservesValidFinalizedAudioAndBlocksIncompleteUpload() async throws { /* recoverable outcome */ }
```

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TaisaAudioTests`  
Expected: FAIL because the audio target and protocols do not exist.

- [ ] **Step 3: Implement protocol-backed service and AVFoundation adapter**

Request permission only from `start`, use one owned recording, apply complete file protection, emit content-free events for interruption/route/reset/storage outcomes, and never initiate networking.

- [ ] **Step 4: Verify GREEN and project build**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TaisaAudioTests`  
Expected: PASS.

Run: `xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Dev -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`  
Expected: BUILD SUCCEEDED with microphone usage text present.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation apple/Config
git commit -m "feat: add recoverable native audio capture"
```

### Task 6: Implement strict native transcription and coaching stream clients

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaNetworking/NDJSONStreamTransport.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/TranscriptionStreamClient.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/CoachingStreamClient.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaVoiceTests/StreamClientTests.swift`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`

**Interfaces:**
- Consumes: finalized local audio, stable stage request/idempotency identity, Task 1 contracts, and `URLSession.AsyncBytes`.
- Produces: `AsyncThrowingStream<TranscriptionStreamEvent, Error>`, `AsyncThrowingStream<CoachingStreamEvent, Error>`, and content-free typed transport errors.

- [ ] **Step 1: Write failing scripted-transport tests**

Test fragmented UTF-8, split lines, maximum line/buffer sizes, request mismatch, gaps, byte-identical duplicate replay, conflicting duplicate, multiple terminal, post-terminal data, timeout, cancellation, and HTTP/auth/rate/cost mapping.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter StreamClientTests`  
Expected: FAIL because clients and bounded transport do not exist.

- [ ] **Step 3: Implement bounded incremental clients**

Upload audio only from the transcription client after queued state is durable. Apply exact header identities. Coaching sends accepted transcript/context without persisting provider payloads. Clear ephemeral deltas on unreconciled failure.

- [ ] **Step 4: Verify GREEN**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter 'StreamClientTests|TranscriptionStreamEventTests|CoachingStreamEventTests'`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: add strict native conversation stream clients"
```

### Task 7: Coordinate persistence, side effects, reconnect, and relaunch

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceSessionCoordinator.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/ConnectivityMonitoring.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceRetryScheduler.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceSessionRecovery.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaVoiceTests/VoiceSessionCoordinatorTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaVoiceTests/VoiceSessionRecoveryTests.swift`

**Interfaces:**
- Consumes: reducer effects, turn repository, capture service, both stream clients, connectivity opportunity, clock, sleeper, and gateway reconciliation lookup.
- Produces: `VoiceSessionCoordinator.send(_:)`, observable durable/ephemeral session snapshots, bounded automatic recovery, and explicit `resumeRequiresConfirmation` commands.

- [ ] **Step 1: Write failing end-to-end coordinator tests with fakes**

```swift
@Test func offlineSendQueuesThenAutoResumesOnceWhenNetworkReturns() async throws { /* one upload */ }
@Test func retryingCoachingNeverRetranscribesAudio() async throws { /* stage isolation */ }
@Test func ambiguousPaidWorkWaitsForConfirmation() async throws { /* no automatic provider call */ }
@Test func relaunchAtEveryCheckpointResumesOnlyAuthorizedStage() async throws { /* table driven */ }
```

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter 'VoiceSessionCoordinatorTests|VoiceSessionRecoveryTests'`  
Expected: FAIL because orchestration and recovery do not exist.

- [ ] **Step 3: Implement actor-owned orchestration**

Serialize commands in one actor, checkpoint before executing effects, cancel stale child tasks, apply bounded exponential backoff with injected jitter, reconcile receipts before retry, and publish partial text separately from durable history.

- [ ] **Step 4: Verify GREEN and repeated-run stability**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter 'VoiceSessionCoordinatorTests|VoiceSessionRecoveryTests' --repeat 10`  
Expected: PASS without duplicate transport calls or leaked tasks.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: coordinate recoverable voice conversations"
```

### Task 8: Add retention, orphan reconciliation, privacy diagnostics, and fixtures

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceAudioCleanup.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaPreviewSupport/VoiceSessionFixtures.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaVoiceTests/VoiceAudioCleanupTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaPreviewSupportTests/VoiceSessionFixtureTests.swift`
- Modify: `apple/Packages/TaisaFoundation/Tests/TaisaSecurityTests/DiagnosticRedactionTests.swift`
- Modify: `docs/product-contracts/native-foundation.md`

**Interfaces:**
- Consumes: terminal/recoverable turn records, protected audio inventory, cleanup retry state, and deterministic fake services.
- Produces: startup orphan reconciliation, idempotent cleanup, and fixtures for clear, uncertain, no-speech, offline, reconnecting, interrupted, ambiguous, failed, completed, and second-turn states.

- [ ] **Step 1: Write failing retention and privacy tests**

Assert recoverable audio is retained, terminal/discarded audio is deleted, unknown files follow bounded quarantine/cleanup policy, cleanup failure checkpoints a retry, and diagnostics/evidence never contain audio paths, transcript, response, or private context.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter 'VoiceAudioCleanupTests|VoiceSessionFixtureTests|DiagnosticRedactionTests'`  
Expected: FAIL because cleanup and fixtures do not exist.

- [ ] **Step 3: Implement cleanup and deterministic fixture registry**

Keep fixtures synthetic and network-denied. Record only content-free stage, counts, sizes, durations, sequences, fingerprints, and timestamps.

- [ ] **Step 4: Verify GREEN**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter 'VoiceAudioCleanupTests|VoiceSessionFixtureTests|DiagnosticRedactionTests'`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation docs/product-contracts/native-foundation.md
git commit -m "feat: enforce voice retention and fixture privacy"
```

### Task 9: Add the narrow SwiftUI diagnostic and accessibility surface

**Files:**
- Create: `apple/TaisaApp/Voice/VoiceSessionDiagnosticsView.swift`
- Create: `apple/TaisaApp/Voice/VoiceSessionDiagnosticsViewModel.swift`
- Create: `apple/TaisaPreview/VoiceSessionScenarios.swift`
- Create: `apple/TaisaUnitTests/VoiceSessionDiagnosticsViewModelTests.swift`
- Create: `apple/TaisaPreviewUITests/VoiceSessionAccessibilityTests.swift`
- Modify: `apple/TaisaApp/FoundationRootView.swift`
- Modify: `apple/TaisaPreview/PreviewRegistry.swift`
- Modify: `apple/project.yml`

**Interfaces:**
- Consumes: coordinator snapshot/commands and deterministic fixtures only.
- Produces: a development/preview validation surface for every Platform state, with accessible record, pause, resume, Send, cancel, discard, transcript confirmation, retry, and ambiguous-resume actions.

- [ ] **Step 1: Write failing view-model and accessibility tests**

Verify action availability derives from domain state, private content is not auto-announced, status is not colour-only, Dynamic Type preserves actions, Reduce Motion disables waveform animation, and VoiceOver focus remains chronological.

- [ ] **Step 2: Run RED**

Run: `xcodebuild test -project apple/Taisa.xcodeproj -scheme Taisa-Preview -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/VoiceSessionDiagnosticsViewModelTests -only-testing:TaisaPreviewUITests/VoiceSessionAccessibilityTests`  
Expected: FAIL because the diagnostic surface is missing.

- [ ] **Step 3: Implement the narrow validation surface**

Use existing design-system components and string resources. Do not establish final Conversation layout, navigation, styling, or motion. Keep production diagnostics behind the existing development/QA entry and previews network-denied.

- [ ] **Step 4: Verify GREEN and design-system compliance**

Run: `xcodebuild test -project apple/Taisa.xcodeproj -scheme Taisa-Preview -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/VoiceSessionDiagnosticsViewModelTests -only-testing:TaisaPreviewUITests/VoiceSessionAccessibilityTests`  
Expected: PASS.

Run: `node scripts/native-apple/verify-design-system.mjs`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apple
git commit -m "feat: expose accessible voice platform diagnostics"
```

### Task 10: Verify contracts, recovery, builds, and physical-device matrix

**Files:**
- Create: `docs/qa/swift-native-audio-streaming-device-matrix.md`
- Create: `apple/scripts/verify-voice-evidence.mjs`
- Create: `apple/scripts/__tests__/verify-voice-evidence.test.mjs`
- Modify: `scripts/native-apple/verify-all.sh`
- Modify: `docs/features/swift-native-audio-streaming.md`
- Modify: `docs/workflow.md`

**Interfaces:**
- Consumes: all prior task verification commands and signed-build metadata.
- Produces: content-free exact-build evidence bound to commit, build, schema, fixture revision, backend environment, signer/profile, device, and OS.

- [ ] **Step 1: Write failing evidence-verifier tests**

Reject evidence containing private text/audio/path fields, wrong commit or fixture revision, missing iPhone/iPad rows, absent interruption/route/connectivity cases, or simulator-only claims.

- [ ] **Step 2: Run RED**

Run: `node --test apple/scripts/__tests__/verify-voice-evidence.test.mjs`  
Expected: FAIL because the verifier and matrix do not exist.

- [ ] **Step 3: Implement the verifier and matrix template**

Include permission, pause/resume, phone/Siri/alarm, Bluetooth/wired route removal, background/foreground, lock/unlock, force-quit, Wi-Fi/cellular loss and return, cancellation per stage, multi-turn continuation, privacy scan, and performance measurements.

- [ ] **Step 4: Run the complete automated matrix**

Run: `npm test --workspace=backend -- --runInBand && npm run build --workspace=backend && npm run build --workspace=shared`  
Expected: PASS.

Run: `node --test scripts/native-contracts/__tests__/*.test.mjs apple/scripts/__tests__/verify-voice-evidence.test.mjs`  
Expected: PASS.

Run: `cd apple/Packages/TaisaFoundation && swift test`  
Expected: PASS.

Run: `bash scripts/native-apple/verify-all.sh`  
Expected: PASS.

- [ ] **Step 5: Build, install, and execute the signed device matrix**

Build the exact commit with `Taisa-Personal`, install it on the registered iPhone and iPad, record only content-free evidence, and run `node apple/scripts/verify-voice-evidence.mjs docs/qa/swift-native-audio-streaming-device-matrix.md`.

Expected: every required row passes on both devices; any failure returns the feature to Build and creates QA notes.

- [ ] **Step 6: Commit**

```bash
git add docs apple scripts/native-apple
git commit -m "test: verify native audio streaming foundation"
```

## Plan self-review

- Spec coverage: all acceptance criteria map to Tasks 1–10; final Product UI remains deliberately excluded.
- Placeholder scan: no implementation placeholder or deferred in-scope behavior remains.
- Type consistency: Task 1 event identities feed Tasks 2 and 6; Task 3 persistence and Task 4 transitions feed Task 7; Tasks 5–7 feed Tasks 8–10.
- External mutations: no signing, capability, provider configuration, or paid infrastructure change is planned. If implementation proves one necessary, stop for target-specific approval.
- Execution recommendation: native inline execution, because the ten tasks share tightly coupled identities and state-machine contracts; one whole-branch independent review remains mandatory before QA.
