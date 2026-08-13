# Voice-First Composer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mandatory voice review with a bottom-loaded voice-first composer that supports pause/resume, keyboard switching, locally detected voice drafts, mixed input, direct submission, correctable sent transcripts, and voice-ready follow-up continuity.

**Architecture:** A pure composer state model owns transitions and draft rules; the audio service owns native recording pause/resume and emits local metering samples; a local speech-activity accumulator classifies stopped audio as speech, silence, or uncertain. The chat screen renders presentational composer components from this state, while the existing local-first capture service remains the only transcription/coaching boundary and gains an explicit auto-coach voice path plus post-send revision.

**Tech Stack:** React Native, Expo SDK 54, `expo-av`, Reanimated shared values, Zustand, encrypted SQLite repositories, Jest, TypeScript, NativeWind/design-system components.

## Global Constraints

- Recording starts automatically only after an explicit voice entry.
- Nothing is transcribed or coached until the user taps Send.
- Speech detection and draft classification remain entirely on-device.
- Silence creates no Voice Draft; meaningful or uncertain audio is preserved.
- The active input owns the full composer; the inactive input is a removable draft strip.
- Send combines voice transcript first and typed clarification second.
- Sent transcripts are editable; correction visibly regenerates coaching.
- A successful voice turn returns to a non-recording voice-ready control labeled `Reply`; it does
  not activate the microphone automatically.
- The whole voice-ready control starts recording and exposes the accessibility label `Reply by
  voice, starts recording`.
- Explicit voice/keyboard switching persists the conversation's preferred modality locally and
  survives restart and exact resume.
- Existing dirty device-QA fixes must be preserved.
- No new dependency, provider call, background analysis, or navigation redesign.

---

### Task 1: Local recorder lifecycle and speech-aware drafts

**Files:**
- Create: `mobile/src/services/voiceActivity.ts`
- Create: `mobile/src/services/__tests__/voiceActivity.test.ts`
- Modify: `mobile/src/services/audio.ts`
- Modify: `mobile/src/hooks/useVoiceRecorder.ts`
- Test: `mobile/src/services/__tests__/recordingStopSession.test.ts`

**Interfaces:**
- Produces: `VoiceActivitySummary`, `classifyVoiceActivity(samples)`, and recorder methods `pause()`, `resume()`, `stop()` returning `{ uri, durationSeconds, activity }`.
- Consumes: Expo metering values normalized to `0..1` at 80ms intervals.

- [x] **Step 1: Write failing activity tests**

Test sustained samples as `speech`, flat sub-threshold samples as `silence`, and isolated/noisy spikes as `uncertain`; assert duration alone never produces speech.

- [x] **Step 2: Run RED**

Run: `cd mobile && npm test -- voiceActivity --runInBand`

Expected: FAIL because `voiceActivity.ts` does not exist.

- [x] **Step 3: Implement the pure accumulator and native pause/resume boundary**

Use conservative fixed MVP thresholds over normalized local metering windows. Preserve uncertain audio. Pause must stop the duration timer and metering animation without unloading the recording; resume continues the same native recording.

- [x] **Step 4: Run GREEN**

Run: `cd mobile && npm test -- voiceActivity recordingStopSession --runInBand && npm run typecheck`

Expected: all focused tests and typecheck pass.

### Task 2: Deterministic mixed-input composer state

**Files:**
- Create: `mobile/src/services/voiceComposerState.ts`
- Create: `mobile/src/services/__tests__/voiceComposerState.test.ts`

**Interfaces:**
- Consumes: `RecordingResult.activity`, text changes, and user intents `pause`, `resume`, `switch-to-text`, `switch-to-voice`, `delete-text`, `delete-voice`, `send`, and `close`.
- Produces: a discriminated `VoiceComposerState` covering recording, paused, text-only, text-with-voice-draft, voice-with-text-draft, submitting, and error.

- [x] **Step 1: Write table-driven transition tests**

Cover every approved state-map transition, including silence disappearing on keyboard switch, uncertain audio being preserved, text deletion affecting only text, voice deletion requiring confirmation, and switching from keyboard returning to paused voice rather than activating the microphone.

- [x] **Step 2: Run RED**

Run: `cd mobile && npm test -- voiceComposerState --runInBand`

Expected: FAIL because the state reducer does not exist.

- [x] **Step 3: Implement the minimal pure reducer**

Keep destructive confirmation as explicit state. Never infer submission from pause, switch, or close.

- [x] **Step 4: Run GREEN**

Run: `cd mobile && npm test -- voiceComposerState --runInBand && npm run typecheck`

Expected: focused tests and typecheck pass.

### Task 3: Direct voice coaching and visible transcript correction

**Files:**
- Modify: `mobile/src/services/privateCapture.ts`
- Modify: `mobile/src/services/localPlatform.ts`
- Modify: `mobile/src/stores/chatStore.ts`
- Test: `mobile/src/services/__tests__/privateCapture.test.ts`
- Test: `mobile/src/stores/__tests__/localStores.test.ts`

**Interfaces:**
- Produces: `submitVoiceAndCoach(...) -> CompletedSubmissionResult` and `reviseSubmittedTranscript(...) -> CompletedSubmissionResult`.
- Consumes: the existing persisted voice request, transcription receipt, bounded coaching context, retry IDs, and audio cleanup queue.

- [x] **Step 1: Write failing orchestration tests**

Assert one deliberate voice Send performs exactly one transcription then one coaching request, returns a completed result without confirmation state, persists the transcript before coaching, and retains exact retry recovery. Assert revising a completed voice transcript preserves the correction, supersedes the visible assistant response, increments the attempt, and runs one new bounded coaching request.

- [x] **Step 2: Run RED**

Run: `cd mobile && npm test -- privateCapture localStores --runInBand`

Expected: FAIL because voice submission stops at transcript confirmation and completed transcripts cannot be revised.

- [x] **Step 3: Implement direct submission and revision**

Keep transcription and coaching as sequential paid boundaries under the existing operation lease. Store the transcript before coaching. Revision must be explicit, local-first, retryable, and must not create a second user message.

- [x] **Step 4: Run GREEN**

Run: `cd mobile && npm test -- privateCapture localStores --runInBand && npm run typecheck`

Expected: focused tests and typecheck pass.

### Task 4: Bottom-loaded composer UI

**Files:**
- Create: `mobile/src/components/ui/VoiceComposer.tsx`
- Create: `mobile/src/components/ui/VoiceDraftStrip.tsx`
- Create: `mobile/src/components/ui/VoiceComposer.stories.tsx`
- Modify: `mobile/src/components/ui/index.ts`
- Modify: `mobile/app/chat/index.tsx`
- Modify: `docs/design-system.md`
- Test: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`

**Interfaces:**
- Consumes: `VoiceComposerState`, recorder amplitude/duration, and screen callbacks.
- Produces: full-width voice or text composer, negative-space Pause/Resume control, inactive-input draft strip, voice deletion confirmation, direct Send, and sent-transcript edit affordance.

- [x] **Step 1: Write failing UI behavior tests**

Assert fresh voice entry auto-records; keyboard switch preserves speech/uncertain audio and drops silence; Resume is labeled; Send works from recording, paused, and mixed states; the old recording-ready and transcript-review screens are absent; the pending user message appears before Taisa finishes.

- [x] **Step 2: Run RED**

Run: `cd mobile && npm test -- localCaptureRoutes voiceComposer --runInBand`

Expected: FAIL because the current screen still uses Stop, recording review, and transcript confirmation.

- [x] **Step 3: Build DS components, then wire the screen**

Use existing theme tokens and UI primitives. The waveform splits around a deliberate center cradle; paused state expands the cradle for `Resume`. Keyboard mode gets the full text width, with any Voice Draft above it. Voice mode shows any Text Draft above it. The strip body switches modes and its isolated `×` removes only that draft.

- [x] **Step 4: Run GREEN and complete verification**

Run: `cd mobile && npm test -- --runInBand && npm run typecheck`

Expected: all mobile tests and typecheck pass.

- [ ] **Step 5: Physical-device QA**

Verify live waveform response, pause/resume continuity, silence/noise/speech classification, keyboard avoidance, mixed-draft deletion, direct transcription/coaching, transcript correction/regeneration, force-quit recovery, and no orphaned audio.

### Task 5: Voice-ready follow-up and durable modality

**Files:**
- Modify: `shared/types/local.ts`
- Modify: `mobile/src/db/schema.ts`
- Modify: `mobile/src/db/migrations.ts`
- Modify: `mobile/src/db/__tests__/migrations.test.ts`
- Modify: `mobile/src/repositories/conversationRepository.ts`
- Modify: `mobile/src/repositories/__tests__/conversationRepository.test.ts`
- Modify: `mobile/src/services/voiceComposerState.ts`
- Modify: `mobile/src/services/__tests__/voiceComposerState.test.ts`
- Modify: `mobile/src/components/ui/VoiceComposer.tsx`
- Modify: `mobile/src/components/ui/VoiceComposer.stories.tsx`
- Modify: `mobile/src/stores/chatStore.ts`
- Modify: `mobile/src/stores/__tests__/localStores.test.ts`
- Modify: `mobile/app/chat/index.tsx`
- Modify: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`
- Modify: `docs/design-system.md`

**Interfaces:**
- Produces: `LocalConversation.preferredInputMode: 'voice' | 'text'`, schema migration v2,
  `VoiceDraftState: 'none' | 'ready' | 'recording' | 'paused'`, and a presentational voice-ready
  composer variant.
- Consumes: explicit mode-switch events, hydrated conversation state, successful/failed voice
  completion, transcript regeneration, local connectivity state, and the existing recorder start
  callback.

- [ ] **Step 1: Write failing migration and repository tests**

Assert a v1 database migrates once to v2 with `preferred_input_mode TEXT NOT NULL DEFAULT 'text'`
and a check constraint for `voice|text`; new conversations default predictably; an explicit mode
update is idempotent; and archive export/restore column allowlists include the field.

- [ ] **Step 2: Run the persistence RED**

Run: `cd mobile && npm test -- migrations conversationRepository exportArchive --runInBand`

Expected: FAIL because conversations do not persist a preferred input mode and the archive schema
does not yet recognize it.

- [ ] **Step 3: Implement schema v2 and repository mapping**

Add `preferredInputMode` to `LocalConversation`, migration v2, exact repository columns and
mutation fingerprints, and the trusted export/restore allowlist. Preserve existing v1 records as
`text`; only an explicit switch writes a later change.

- [ ] **Step 4: Run the persistence GREEN**

Run: `cd mobile && npm test -- migrations conversationRepository exportArchive --runInBand && npm run typecheck`

Expected: focused tests and typecheck pass.

- [ ] **Step 5: Write failing composer and store transition tests**

Assert a completed voice response becomes `ready`, not `recording`; tapping the full ready control
starts recording; keyboard switch stores `text`; voice switch stores `voice`; hydration and
force-quit resume restore the stored mode; failed voice submission retains its draft and mode;
cancelling returns to ready; transcript correction/regeneration returns to ready; and an older
conversation's async completion cannot change the active conversation's mode.

- [ ] **Step 6: Run the interaction RED**

Run: `cd mobile && npm test -- voiceComposerState localStores localCaptureRoutes --runInBand`

Expected: FAIL because reset returns to text/none and the UI has no voice-ready variant.

- [ ] **Step 7: Implement voice-ready state and screen wiring**

Render one soft-grey full-width tappable control with a black microphone icon and `Reply` label.
Use accessibility label `Reply by voice, starts recording`. Disable it only while a submission is
processing; offline recording remains available, while Send exposes the existing connection
requirement. A successful voice response, cancellation, or corrected-response completion returns
to ready without calling the recorder until the user taps.

- [ ] **Step 8: Run full mobile verification and device QA**

Run: `cd mobile && npm test -- --runInBand && npm run typecheck`

Expected: all mobile tests and typecheck pass. On iPhone, verify voice reply → grey `Reply` → one
tap recording, keyboard/voice persistence after force-quit, offline local recording, failed-send
draft retention, cancellation, transcript correction, VoiceOver label, and no automatic microphone
activation.
