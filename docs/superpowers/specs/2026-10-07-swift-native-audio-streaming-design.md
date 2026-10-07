# Swift Native Audio and Conversation Streaming Design

**Date:** 2026-10-07
**Status:** Approved
**Tier:** Full
**Track:** Platform
**Scope:** `docs/features/swift-native-audio-streaming.md`

## Outcome

Taisa gains a native, recoverable audio and streaming subsystem for multi-turn coaching conversations on iPhone and iPad. A user records locally, pauses and resumes deliberately, and sends one turn into a two-stage pipeline: ordered transcription streaming followed by ordered coaching-response streaming. The system preserves exactly-once semantics across connectivity loss, interruption, cancellation, and relaunch without treating voice as a disposable note or persisting partial output as finished history.

This foundation stops at stable Platform contracts and narrow validation surfaces. Later Product slices own the final Conversation screen, navigation, visual hierarchy, and interaction polish.

## User intent and approved decisions

- Voice is a continuing coaching conversation, not a voice-note uploader.
- Pause and resume are required within one recorded turn.
- Multiple turns share one conversation-session identity; each turn has its own durable identity.
- Audio remains local until explicit Send.
- Both transcription and coaching response stream genuinely after Send.
- Transcription and coaching remain separate network stages with independent retry boundaries.
- Partial transcript and coaching deltas are temporary display state; only validated terminal results are durable history.
- Ordinary network loss resumes automatically when safe.
- Potentially duplicate paid work fails safe unless the gateway can prove exactly-once reconciliation.
- Continuous listening, barge-in, simultaneous playback/recording, and text-to-speech are deferred.

## Approaches considered

### Selected: two real streams coordinated by one durable native session engine

The native client uploads audio to the existing transcription stream. A clear or user-confirmed transcript then starts a distinct coaching-response stream. The coordinator shares conversation and turn identity across both stages while preserving distinct request identifiers, idempotency keys, receipts, and retry boundaries.

This approach preserves the existing privacy and cost boundaries, allows transcription correction without paying for coaching, and lets coaching resume without re-uploading audio.

### Rejected: one combined audio-to-coaching server stream

A single endpoint could make the client superficially simpler, but it couples audio upload, transcription quality decisions, user confirmation, provider fallback, and coaching billing into one long-lived request. Safe partial retry and uncertain-transcript editing become harder, and the gateway would own product-session state it currently does not persist.

### Rejected: streamed transcription plus locally animated completed coaching JSON

Animating a completed response would avoid a backend streaming change, but it is not genuine response streaming. It delays the first useful coaching text, weakens cancellation semantics, and creates misleading UI state.

## System boundaries

```text
SwiftUI Conversation Slice (later Product work)
  -> Conversation Feature Model
    -> VoiceSessionCoordinator
       -> AudioCaptureService
       -> ConversationTurnRepository
       -> TranscriptionStreamClient
       -> CoachingStreamClient
       -> ConnectivityMonitor / RetryScheduler
    <- explicit durable + ephemeral render state

TranscriptionStreamClient -> POST transcription audio -> ordered NDJSON events
CoachingStreamClient      -> POST coaching request    -> ordered NDJSON events
Gateway -> transient providers, validation, fallback, cost ledger, idempotency receipts
```

Views never own `AVAudioSession`, files, upload tasks, sequence reconciliation, retry policy, SQL, or provider concerns. Domain state does not import SwiftUI. Device-service adapters are protocol-backed and replaceable by deterministic fixtures.

## Native components

### AudioCaptureService

Owns microphone authorization, `AVAudioSession`, recorder lifecycle, local file creation, pause/resume, metering samples, interruptions, route changes, media-services reset, and content-free capture diagnostics. It emits typed events and never initiates networking.

The service uses one explicitly owned recording at a time. Pause preserves the same logical turn and local file timeline. Resume continues that turn. A route or system interruption never silently starts a new turn.

### VoiceSessionCoordinator

Owns the durable conversation-turn state machine and is the only component allowed to advance a turn between capture, queued upload, transcription, confirmation, coaching, completion, recoverable failure, and discard. It checkpoints state before side effects, cancels child tasks when ownership changes, and reconciles terminal receipts before retrying.

The coordinator exposes ephemeral partial text separately from durable state. Relaunch reconstructs the durable checkpoint and starts only work authorized by the recovery policy.

### TranscriptionStreamClient

Uploads the finalized local audio file only after Send and consumes the existing `application/x-ndjson` transcription contract. It validates every line against the canonical event envelope, request identity, monotonically increasing sequence, strict allowed fields, and exactly one terminal event.

Existing terminal meanings remain authoritative:

- `transcript.completed` with `quality: clear` commits the transcript and permits coaching.
- `transcript.completed` with `quality: uncertain` commits only a private editable draft and waits for confirmation.
- `transcript.no_speech` creates no message and no coaching request.
- `transcript.failed` records a typed retryable or terminal failure without inventing text.

### CoachingStreamClient

Consumes a new strict `application/x-ndjson` coaching stream using the same envelope discipline as transcription. The portable event family is:

- `coaching.delta`: ordered reply-text delta for temporary display;
- `coaching.completed`: one terminal event containing the complete validated `CoachingResponse`, usage receipt, and idempotency receipt;
- `coaching.failed`: one terminal content-free typed error code and retry classification.

The terminal structured response remains authoritative for reply text, mode, relevance, context sufficiency, stance, proposals, request identity, and usage. A concatenation of deltas is never accepted as a substitute for a missing or invalid terminal response.

### ConversationTurnRepository

Persists the minimum recoverable turn state in the encrypted local store: conversation ID, turn ID, request IDs, idempotency keys, capture metadata, local audio reference, accepted transcript or uncertain draft, durable state, retry counters/timestamps, terminal receipts, final user message, final coaching response, and cleanup status.

Partial deltas, waveform samples, raw provider fields, and readable diagnostics are not stored as durable product records. Audio bytes remain file-backed and excluded from sync, backup, export, and restore.

### Connectivity and retry services

A connectivity monitor signals opportunity, not proof that the internet or provider is usable. A durable retry scheduler applies bounded exponential backoff with jitter, an attempt ceiling, and a next-attempt timestamp. Authentication, validation, incompatible-contract, invalid-audio, cost-limit, and explicit cancellation states do not auto-retry.

## Identity and exactly-once rules

Each conversation has a stable `conversationId`. Each user turn receives a stable `turnId`. Transcription and coaching each receive distinct stable request IDs and idempotency keys derived or stored for that turn; reconnecting or retrying a stage reuses its original identity.

The gateway must persist or otherwise durably reconcile an idempotency receipt for coaching before automatic recovery is allowed to re-enter provider work. A duplicate coaching request with the same key returns or reconnects to the authoritative result; it never invokes another provider attempt. Cost reservation and settlement bind to the same idempotency record.

If the client loses connectivity after sending but before receiving proof, it queries or reconnects using the same identity. If the gateway cannot prove whether paid work began or completed, the turn becomes `resumeRequiresConfirmation` and waits for explicit user action. The UI must never label this state as an ordinary retry.

Transcription uses the same identity discipline. When the current gateway cannot resume from an acknowledged sequence, the client may restart transcription with the same idempotency key only after the server contract can reconcile the previous attempt without charging or emitting conflicting terminal results.

## Durable state model

A turn moves through explicit states:

```text
draft -> recording <-> paused -> queued
queued -> transcribing -> transcriptClear -> coaching -> completed
transcribing -> transcriptUncertain -> awaitingTranscriptConfirmation -> coaching
transcribing -> noSpeech
any active side effect -> recoverableFailure | terminalFailure | cancelled
recoverableFailure -> queued/transcribing/coaching according to the saved stage
any non-terminal local state -> discarded (explicit user action)
```

State transitions and their outbox/retry metadata commit atomically. `completed`, `noSpeech`, `terminalFailure`, and `discarded` are terminal. Cancellation is distinct from discard: cancellation stops current work and preserves the turn when recovery remains possible; discard authorizes audio deletion and prevents automatic restart.

## End-to-end flow

1. The user begins a turn after microphone authorization succeeds.
2. Audio is recorded into an app-owned temporary file. Metering may drive UI but is not durable.
3. Pause and resume keep the same turn identity and recording ownership.
4. Send finalizes the file and atomically checkpoints `queued` before starting upload.
5. Ordered transcript deltas update temporary display state.
6. A clear terminal transcript becomes the durable user message and starts coaching automatically.
7. An uncertain terminal transcript becomes an editable private draft; confirmation or correction creates the accepted user message and then starts coaching.
8. No-speech records the terminal outcome, creates no message, and returns the conversation to readiness for another turn.
9. Ordered coaching deltas update temporary response text.
10. The terminal validated coaching response and its receipt commit atomically with the assistant message and applicable staged proposals.
11. After the transcript and terminal turn outcome are durable, cleanup deletes the audio file and records completion. Cleanup retries safely if deletion fails.
12. The conversation returns to ready state for the next turn under the same conversation identity.

## Automatic recovery policy

Automatic recovery is allowed only when replay is known to be side-effect safe:

- a finalized local recording is queued but upload never began;
- an upload or stream can reconnect/reconcile under the same idempotency key;
- a gateway receipt proves the authoritative terminal result;
- cleanup is incomplete after durable product completion.

Connectivity return triggers eligible work with bounded backoff. The app does not rely on indefinite iOS background execution; background tasks checkpoint and cancel cleanly, then resume on the next permitted foreground or system opportunity.

Automatic recovery is forbidden for invalid audio, permission denial, authentication failure, validation/contract mismatch, cost-limit rejection, explicit cancellation/discard, exhausted attempts, and ambiguous paid coaching work without a reconciled receipt.

## Audio and lifecycle behavior

- Microphone permission is requested only from a deliberate user action. Denial produces settings guidance and no recording row or file.
- Phone calls, Siri, alarms, and system interruptions pause or finalize capture according to whether the underlying recorder can safely resume. The visible state explains what happened.
- Route changes, including Bluetooth or wired-device removal, never silently switch ownership while presenting an uninterrupted state. Taisa either continues on the confirmed route or pauses with recovery guidance.
- Backgrounding checkpoints capture state. Recording continuation is allowed only where the approved audio-session category and iOS policy support the active user-initiated session; there is no background listening.
- Media-services reset rebuilds the audio stack without losing the durable turn identity.
- Low storage or file-write failure stops capture, preserves any valid finalized audio, and prevents upload of an incomplete file.
- Force-quit recovery reconstructs state from the encrypted repository and verified local file identity before offering or starting recovery.

## Stream validation and failure handling

Both stream clients use incremental line decoding with bounded buffers. Every event must have the expected request ID, exact allowed fields, a non-negative sequence, and the next expected sequence number. Duplicate events may be ignored only when byte-equivalent to the already accepted event and covered by a reconciled receipt; conflicting duplicates, gaps, unknown types, extra fields, multiple terminals, data after terminal, invalid UTF-8/JSON, and oversized lines fail closed.

Partial display text is cleared or reconstructed from the current connection when a stream fails; it never advances durable product state. Typed errors distinguish offline/unreachable, timeout, authentication, rate limit, cost limit, invalid audio, provider unavailable, malformed stream, incompatible contract, cancellation, storage failure, and ambiguous paid-work status.

## Privacy and data retention

Audio, transcript text, coaching text, private context, and provider payloads never enter logs, metrics, crash reports, notifications, preview metadata, screenshots captured by automated evidence, or signed-build records. Diagnostics contain only content-free identifiers or fingerprints, stage, error category, bounded counts, durations, byte sizes, sequence numbers, and timestamps.

Audio is retained only while the owning turn is recordable, reviewable, uploadable, or recoverable. It is removed after durable success/no-speech/discard and remains excluded from CloudKit, encrypted recovery archives, Files export, and any future transport unless separately scoped and approved.

## Accessibility and user communication contract

The later Product view must expose record, pause, resume, Send, cancel, discard, edit uncertain transcript, retry, and resume-with-confirmation as distinct accessible actions. State changes and terminal outcomes are announced without reading private content automatically. Status never relies only on colour or animation.

Dynamic Type must preserve every primary action. Reduce Motion removes nonessential waveform/transition motion without hiding state. VoiceOver ordering follows conversation chronology and keeps temporary streaming text from repeatedly stealing focus.

## Portable contracts

Canonical TypeScript runtime schemas remain authoritative. Shared JSON fixtures cover every valid and invalid transcription/coaching event, identity rule, terminal outcome, and retry classification. Swift `Decodable` models and backend handlers consume the same fixtures.

The product-contract record captures state names, visible intent, recovery copy, accessibility semantics, and Apple-only adaptations. A future React Native client can recreate the behavior without copying Swift implementation details.

## Verification strategy

### Automated

- Pure state-machine tests cover every transition, cancellation point, retry decision, idempotency rule, and cleanup path.
- Audio-service tests use injected session/recorder/file adapters for permission, pause/resume, interruption, route loss, reset, storage failure, and cleanup.
- Contract tests validate Swift and TypeScript against the same clear, uncertain, no-speech, coaching-delta, coaching-completed, coaching-failed, malformed, duplicate, gap, wrong-request, and post-terminal fixtures.
- Repository integration tests prove atomic checkpoints, relaunch reconstruction, file-identity validation, accepted-message creation, and exclusion of audio from sync/backup.
- Gateway tests prove genuine ordered coaching streaming, structured terminal validation, cost settlement, stable idempotency receipts, reconnect/reconciliation, cancellation, fallback, and content-free failures.
- UI tests cover permission denial, record/pause/resume/Send, uncertain editing, no speech, offline queueing, automatic reconnection, coaching streaming, cancellation, relaunch, cleanup, and a second turn in the same conversation.
- Accessibility tests cover labels, traits, actions, focus stability, announcements, Dynamic Type, Reduce Motion, and non-colour state.

### Physical-device QA

Exact signed builds are tested on the registered iPhone and iPad with built-in microphones and available speaker, wired, and Bluetooth routes. The matrix covers permission changes, calls/Siri/alarms, route removal, background/foreground, device lock/unlock, force-quit, cellular/Wi-Fi loss and return, low-storage simulation where practical, cancellation at each network stage, and multi-turn continuation.

Performance evidence records time to recording readiness, audio-file growth, memory and energy behavior, time to first transcript event, time to first coaching event, reconnection latency, and cleanup completion. Device evidence binds commit, app/build version, database schema, contract-fixture revision, backend environment, signer/profile, device, and OS.

## Deliberate exclusions

- No final Conversation UI or navigation implementation.
- No pre-Send/live transcription, continuous listening, or wake word.
- No barge-in, simultaneous playback/recording, speech synthesis, or voice playback controls.
- No audio sync, backup, export, restore, attachment model, or CloudKit activation.
- No coaching-persona, stance, memory, prompt, proposal, or product-IA redesign.
- No React Native implementation or migration harness work.
- No public accounts, server-readable history, or backend persistence of private conversation content.
- No endpoint retirement, React Native deletion, or production cutover.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| A reconnect creates duplicate paid coaching | Stable idempotency key, durable gateway receipt, atomic cost settlement, and confirmation-required ambiguous state. |
| iOS interruption or route behavior differs by device | Protocol-backed audio ownership, typed events, deterministic tests, and exact-build iPhone/iPad QA. |
| Partial stream text leaks into durable history | Separate ephemeral state; only strict validated terminal events may commit messages. |
| Audio is deleted before recovery is safe | Cleanup follows durable transcript/terminal outcome and uses retryable cleanup state. |
| Audio accumulates indefinitely | Retention invariants, startup orphan reconciliation, bounded age/size checks, and explicit cleanup evidence. |
| Background execution is assumed rather than granted | Checkpoint and cancel safely; resume on permitted foreground/system opportunity without claiming indefinite execution. |
| Coaching streaming weakens structured output validation | Deltas are presentation-only; the complete structured terminal response remains authoritative. |
| Future React Native work cannot reproduce native behavior | Portable schemas, fixtures, state/recovery contracts, and recorded Apple-only adaptations. |

## Approval gates

1. **Written design:** Baah reviews this committed specification.
2. **Implementation plan:** exact files, dependencies, gateway changes, state transitions, tests, device matrix, and task sequencing require separate approval.
3. **Build external mutations:** provider/API configuration, signing/capability changes, or paid infrastructure changes require target-specific approval if the plan identifies any.
4. **Ship:** automated verification, independent review, signed exact-build iPhone/iPad QA, accepted differences, and explicit Baah approval.
