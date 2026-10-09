# Swift Native Audio and Conversation Streaming

**Tier:** Full
**Track:** Platform
**Status:** Review — automated matrix passed; exact signed iPhone/iPad QA pending
**Depends on:** shipped Swift native foundation and encrypted local persistence/recovery

---

## What is it?

A native Apple audio and streaming foundation for multi-turn Taisa coaching conversations on iPhone and iPad. It keeps voice private and local while the user records, supports deliberate pause and resume within a turn, and begins network work only after Send.

After Send, Taisa streams transcription and then the coaching response through two independently recoverable stages coordinated by one durable conversation-session engine. The foundation exposes stable state, recovery, accessibility, and fixture contracts for later SwiftUI voice-conversation screens without defining their final visual design.

## Why now?

Encrypted local persistence and recovery are shipped, so Taisa can safely checkpoint a voice turn before attempting network work. Voice coaching is the primary interaction model and blocks the Conversation product slice; proving audio-session ownership, interruption recovery, real streaming, idempotency, and cleanup first prevents every later screen from inventing incompatible behavior.

The gateway already exposes strict ordered NDJSON transcription events and a validated structured coaching response. This scope extends those portable contracts to real coaching-response streaming while preserving the local-first privacy boundary and exactly-once paid-request behavior.

`Taisa-Personal` may connect only to an explicitly configured HTTPS Taisa voice gateway (or localhost for simulator development). Durable conversation history remains encrypted and device-local, temporary audio remains excluded from backup/sync/export, and the Personal target still has no CloudKit capability. Production ownership comes from authenticated device middleware; the legacy `X-User-ID` QA fallback is disabled in production.

## Acceptance criteria

- [x] A conversation session supports multiple voice turns, and every turn has a stable durable identity beneath one stable conversation-session identity.
- [x] Within one turn, the user can record, pause, resume, Send, cancel, or explicitly discard while Taisa accurately communicates the current state.
- [x] Nothing leaves the device before Send; pausing and resuming operate only on local audio.
- [x] Send durably checkpoints the queued turn before upload, so a network failure or process termination cannot erase an accepted recording.
- [x] Post-Send transcription appears incrementally from ordered validated stream events without persisting partial transcript deltas as completed history.
- [x] A clear final transcript is committed and automatically begins coaching; an uncertain transcript becomes an editable private draft and waits for confirmation; no-speech creates no user message and starts no coaching request.
- [x] Coaching reply text appears incrementally from a real ordered stream, while only the final validated structured response enters encrypted conversation history.
- [x] Transcription and coaching use separate retry boundaries under one conversation coordinator: retrying coaching never uploads or transcribes audio again, and retrying transcription never creates a coaching request prematurely.
- [x] Stable request identities and gateway idempotency prevent reconnects, relaunches, and manual retries from creating duplicate messages or unintended second paid requests.
- [x] Ordinary connectivity loss automatically resumes with bounded backoff when the network returns; an ambiguous potentially chargeable request waits for explicit user action unless the gateway can prove exactly-once reconciliation.
- [x] Phone calls, Siri, alarms, audio-route changes, Bluetooth loss, backgrounding, foregrounding, and force-quit resolve to typed recoverable states without silently losing the conversation turn.
- [x] Permission denial, low storage, invalid audio, authentication failure, rate or cost rejection, malformed stream data, and incompatible contracts fail safely with actionable user-visible recovery behavior.
- [x] Temporary audio remains available while a turn can still be retried and is deleted only after the accepted transcript and terminal outcome are durably committed or the user explicitly discards it.
- [x] Unknown, duplicate, missing, or out-of-order stream events cannot corrupt visible text, advance durable state, or create duplicate history.
- [x] VoiceOver, Dynamic Type, Reduce Motion, non-colour status communication, and accessible pause/resume/cancel/retry actions work throughout recording and streaming.
- [x] Logs, metrics, crash diagnostics, previews, automated artifacts, and signed-build evidence contain no raw audio, transcript text, coaching text, or private context.
- [x] Deterministic automated fixtures cover clear, uncertain, no-speech, offline queueing, reconnection, interruption, cancellation, relaunch, retry, completion, cleanup, and the next turn in the same conversation.
- [ ] Exact signed builds pass physical-device audio, interruption, route, lifecycle, connectivity, privacy, accessibility, and performance QA on the registered iPhone and iPad.

## Prerequisites

- The native Swift/SwiftUI shell, build identities, deterministic fixtures, CI, signed-build evidence, and iPhone/iPad installation are shipped.
- Encrypted repositories and recovery can durably checkpoint conversation and turn state without including audio in backup or synchronization.
- Canonical TypeScript transcription and coaching schemas remain the cross-language authority.
- The gateway retains provider credentials, cost enforcement, validation, fallback, and content-free operational diagnostics.

## Out of scope

- Final voice-conversation screen layout, visual styling, navigation, or Product design.
- Live transcription before Send, always-listening behavior, or wake words.
- Interrupting or speaking over an in-progress coaching response.
- Simultaneous response playback and microphone recording.
- Text-to-speech playback or voice selection for coaching responses.
- Synchronizing, backing up, exporting, or restoring recorded or temporary audio.
- Redesigning the coaching personality, prompt, four stance modes, memory policy, proposals, or product information architecture.
- React Native implementation or parity work.
- CloudKit activation, Taisa accounts, server-stored conversation history, or readable backend persistence.
- Indefinite automatic retry or any retry that may create an ambiguous duplicate paid request.
- Retiring existing backend endpoints or removing React Native code.

## Verification status

Automated verification on 2026-10-07 passed the backend suite (388 tests), backend TypeScript compilation, Swift foundation suite (398 tests), portable contract/evidence checks, native design-system checks, development/preview/Personal simulator suites, generic device and Release compilation, native isolation inspection, and workflow verification.

Independent whole-branch review remediation is complete: capture file identity is checkpointed before recording begins; interrupted capture relaunch selects and safely cleans the retained file; capture discard completes durable cleanup and releases ownership; media-services reset produces an actionable terminal outcome instead of a false Resume action; terminal transcription/coaching failures delete retained audio and unlock the next turn; and cancelled capture no longer exposes an illegal Retry action. The earlier owner-bound encrypted transcription idempotency, completed replay, reconciliation, and explicit authorization for ambiguous paid work remain intact. Production requires a separate `TAISA_TRANSCRIPTION_RECEIPT_ENCRYPTION_KEY`.

The final acceptance criterion remains open until the reviewed exact commit is integrated into `preview/taisa`, signed as `Taisa-Personal`, installed on both registered physical devices, exercised against every row in `docs/qa/swift-native-audio-streaming-device-matrix.md`, and accepted by `apple/scripts/verify-voice-evidence.mjs`.
