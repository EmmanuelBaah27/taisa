# Final review-fix report

**Date:** 2026-08-13
**Branch:** `feature/local-first-coaching-platform`
**Base:** `2ac699c`
**Stage:** Full-tier Build; Baah's Ship approval remains the next gate after device QA.

## Review findings resolved

1. **Transcript correction authority** — Revising a completed voice transcript now atomically deletes its pending memory confirmations, removes the superseded assistant message, resets the request's assistant/context/stance state, and regenerates with an attempt-specific assistant idempotency key. Both corrected `clarify` and `redirect` turns prove zero stale confirmations and exclude the previous reply from regenerated context and hydration.
2. **Direct voice recovery** — The chat store uses the single persisted `submitVoiceAndCoach` path. Deliberate send is persisted as approved before transcription, so transcription completion moves directly to `coaching-pending`. Hydration automatically resumes voice `transcription-pending`, `coaching-pending`, and legacy `transcript-confirmation-required` interstitials; retry also automatically continues a recovered transcript into coaching. IDs and the transcription request are reused without duplicate rows or a removed review-screen dependency.
3. **Voice-first central entry** — The central `VoiceButton` now opens capture with a one-shot voice auto-start intent. The chat consumes it once, switches to voice mode, and requests recording. Ordinary completed voice turns reset only to the voice-ready `Reply` control and never enqueue another automatic start.
4. **Paused-silence cleanup** — Switching a paused or recording silent draft to text synchronously clears the owned native-session reference, cancels any pending start, then stops and discards the recording. A subsequent Reply can acquire a new session normally.
5. **Trusted v1 archive restore** — A verified schema-v1 archive is copied as bound row values into a fresh locally created schema-v1 device-key candidate. Exact source/candidate schema identity is established before ordinary-row fingerprint/import; selected-archive virtual-table behavior is never invoked. The trusted candidate rebuilds and verifies FTS locally, then bundled migrations take it to v2 before re-fingerprint, promotion, and exact reopen matching. Forward versions and archive-owned/malicious schema objects remain rejected; no source schema SQL is copied or run as a migration.
6. **Evaluation result semantics** — The evaluation CLI writes its content-free summary and synthetic manual-review artifact, then exits nonzero with `EVAL_COACHING_REVIEW_REQUIRED` whenever automated checks fail or manual review remains required. It can no longer report success while human review is outstanding.
7. **Hard total evaluation budget** — OpenAI and Anthropic adapters expose a conservative maximum-call receipt using one input token per UTF-8 byte, configured structured-output overhead, and configured maximum output tokens. The durable ledger reserves that maximum against the explicit total before every provider invocation; insufficient remaining budget prevents the call. A successful receipt replaces its reservation. Provider calls remain one per scenario with SDK retries disabled.
8. **Design-system compliance** — Chat rendering moved into typed exported `ChatScreenShell`, `ChatConversationSurface`, message, transcript, processing, error, proposal, composer-dock, and `VoiceEntryButton` components. `app/chat/index.tsx` retains business/state/recorder/gesture orchestration and no longer constructs native visual primitives, declares a `StyleSheet`, or uses raw colors. Required native color values use documented tokens, including the new transparent-background gradient token. Semantic component and store tests cover the extracted interactions.

Operational `*.sqlite`, `*.sqlite-shm`, and `*.sqlite-wal` files are now ignored. Existing usage-ledger files were not deleted, modified, or committed.

## TDD evidence

- RED: corrected transcript context still contained the superseded assistant and stale confirmations.
- GREEN: correction tests cover both `clarify` and `redirect` with zero stale confirmations.
- RED: the store called legacy `submitVoice`, hydration restored stranded interstitials, and transcription retry stopped at removed review UI.
- GREEN: direct submission and automatic recovery tests pass.
- RED: central entry had no one-shot voice intent; paused silence retained its recorder owner.
- GREEN: semantic store/lifecycle tests prove consume-once entry and detach-before-discard behavior.
- RED: schema-v1 service restore failed the current-version gate and the real SQLite v1 candidate failed trusted-schema identity.
- GREEN: real SQLite v1-to-v2 roundtrip and malicious-v1/forward rejection pass.
- RED: SQL observation proved source-owned FTS integrity commands ran during selected-archive inspection before trust verification.
- GREEN: inspection never executes selected-archive virtual tables; corrupted source FTS is rebuilt and verified only inside the locally trusted candidate.
- RED: CLI tests encoded exit 0 with manual review outstanding; a total below one configured maximum did not prevent the old proportional reservation design.
- GREEN: CLI nonzero semantics, zero-call insufficient budget, actual-replaces-reservation, durable receipts, and maximum-estimator tests pass.

## Verification

- `cd mobile && npm test -- --runInBand` — 40 suites / 395 tests passed.
- `cd mobile && npm test -- --runInBand src/services/__tests__/privateCapture.test.ts` — 47 passed.
- `cd mobile && npm run typecheck` — passed.
- `cd backend && npm test -- --runInBand` — 15 suites / 199 tests passed with localhost-only Supertest permission and no external calls.
- `cd backend && npm test -- --runInBand src/__tests__/coaching.eval.test.ts` — 45 passed.
- `cd backend && npm run build` — passed.
- `bash scripts/verify-workflow.sh` — passed.
- `git diff --check` — passed.
- Changed-screen DS scan — no native visual JSX primitives, `StyleSheet`, raw hex, or raw rgba in `mobile/app/chat/index.tsx` or `mobile/src/components/VoiceButton.tsx`; typed surfaces are exported and documented.
- Independent final diff re-review — no remaining Critical or Important finding.

## Deliberately not run / remaining gate

No native build, simulator, physical-device action, live provider evaluation, paid call, or external network request was run. Baah's iPhone QA remains required for native waveform and pause/resume behavior, permission and keyboard/VoiceOver behavior, fresh-entry auto-start versus response-ready behavior, force-quit recovery, offline messaging, encrypted recovery/key-loss/privacy checks, and the six live guardrail equivalents. Live provider evaluation remains separately gated by Baah's paid approval and an explicit total budget; its CLI remains nonzero until manual review is completed outside this command.
