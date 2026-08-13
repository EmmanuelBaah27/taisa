# Taisa Personal Alpha Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a standalone iPhone personal alpha that works anywhere and collects only explicitly consented response-improvement examples.

**Architecture:** The encrypted phone database remains the product data authority. A Railway-hosted
Node API performs stateless transcription/coaching behind per-installation enrollment credentials,
durable cost limits, and content-free logs. Optional feedback examples are previewed/redacted on the
phone and encrypted before storage in a separate hosted feedback database.

**Tech Stack:** Expo SDK 54, React Native, Expo SecureStore, SQLCipher SQLite, Express, Zod,
better-sqlite3, Node crypto AES-256-GCM, OpenAI gateway, Railway, local Xcode release build.

## Execution status — 2026-08-13

Tasks 1–6 are code-complete through commit `850b3d6`, except the Docker image could not be built
because Docker is not installed locally. No Railway resource, billing, secret, deployment, EAS
upload, Apple credential action, or standalone install has run. Task 7 and the external parts of
Tasks 5–6 remain pending. Continue from the Railway approval gate documented in
`docs/features/personal-alpha-release.md`; do not repeat the completed implementation slices.

## Global Constraints

- Do not deploy or create paid resources before Baah approves this plan and the relevant external action.
- Do not read, print, commit, or transmit secrets or private database content during implementation.
- No conversation content is stored server-side except an individually previewed and explicitly shared feedback example.
- Rating a response is local-only; sharing requires a separate explicit action and payload preview.
- All provider calls retain the existing one-call, zero-SDK-retry, bounded-context, and durable-cost invariants.
- The public API must fail closed without a valid enrolled device credential.
- Keep legacy routes mounted until the separate recovery and route-retirement gates are satisfied.

---

### Task 1: Reconcile and commit the device-QA provider fix

**Files:**
- Modify: `backend/src/services/coaching/openaiProvider.ts`
- Modify: `backend/src/routes/coaching.ts`
- Modify: `backend/src/__tests__/coachingGateway.test.ts`
- Modify: `backend/src/__tests__/coaching.routes.test.ts`
- Modify: `mobile/src/services/coaching.ts`
- Modify: `mobile/src/services/privateCapture.ts`
- Modify: `mobile/src/services/localPlatform.ts`
- Test: `mobile/src/services/__tests__/coaching.test.ts`
- Test: `mobile/src/services/__tests__/privateCapture.test.ts`

**Interfaces:**
- Produces: a provider-compatible OpenAI response schema and content-free diagnostic categories.

- [ ] Add a schema compatibility walker test that rejects unsupported provider keywords and tuple-style array items.
- [ ] Run focused backend/mobile tests and confirm the regression tests fail without the normalization.
- [ ] Retain only reachable definitions, normalize empty arrays, and strip provider-unsupported validation keywords while preserving Zod post-validation.
- [ ] Verify backend full tests/build, mobile full tests/typecheck, workflow, and `git diff --check`.
- [ ] Record the completed iPhone retry result in the QA notes and commit the coherent fix.

### Task 2: Add one-time device enrollment and authenticated API access

**Files:**
- Create: `backend/src/auth/deviceCredentials.ts`
- Create: `backend/src/middleware/deviceAuthentication.ts`
- Create: `backend/src/routes/deviceEnrollment.ts`
- Create: `backend/src/__tests__/deviceAuthentication.test.ts`
- Modify: `backend/src/index.ts`
- Modify: `backend/src/config/env.ts`
- Create: `mobile/src/services/deviceEnrollment.ts`
- Create: `mobile/src/services/__tests__/deviceEnrollment.test.ts`
- Modify: `mobile/src/services/http.ts`

**Interfaces:**
- Produces: `POST /api/v1/device-enrollments` and `requireDeviceCredential`.
- Produces: `ensureDeviceCredential(): Promise<string>` backed by SecureStore.

- [ ] Write failing tests for expired/reused enrollment codes, hashed-at-rest device tokens, constant-time verification, revocation, and unauthenticated provider-route rejection.
- [ ] Run focused tests and observe the missing-module/auth failures.
- [ ] Implement a short-lived single-use enrollment code whose successful exchange returns a random 256-bit device token; store only its SHA-256 digest and lifecycle metadata.
- [ ] Mount authentication before transcription, coaching, feedback, and operational endpoints; keep `/health` content-free and unauthenticated.
- [ ] Add SecureStore enrollment and an Axios interceptor that sends the device token separately from the installation rate-limit ID.
- [ ] Verify focused backend/mobile tests and commit.

### Task 3: Add local reactions and explicit share-preview records

**Files:**
- Modify: `mobile/src/db/schema.ts`
- Modify: `mobile/src/db/migrations.ts`
- Create: `mobile/src/repositories/responseFeedbackRepository.ts`
- Create: `mobile/src/repositories/__tests__/responseFeedbackRepository.test.ts`
- Create: `mobile/src/services/feedbackBundle.ts`
- Create: `mobile/src/services/__tests__/feedbackBundle.test.ts`
- Modify: `mobile/src/components/ui/ChatSurfaces.tsx`
- Modify: `mobile/app/chat/index.tsx`
- Modify: `docs/design-system.md`

**Interfaces:**
- Produces: `ResponseReaction`, `FeedbackShareDraft`, and `buildFeedbackPreview(responseId)`.
- Consumes: the exact persisted request context manifest, user turn, assistant decision, and response.

- [ ] Write migration/repository tests for local helpful/unhelpful reactions, optional notes, no-upload default, and idempotent edits.
- [ ] Write bundle tests proving unrelated messages/memory/audio/secrets are excluded and only context actually used is eligible.
- [ ] Implement local records and deterministic preview/redaction using the existing Unicode-safe redaction boundary.
- [ ] Add typed DS reaction controls and a separate **Share this example** review sheet with explicit consent copy.
- [ ] Verify repository/service/component tests, mobile typecheck, DS scans, and commit.

### Task 4: Add encrypted hosted feedback storage and deletion

**Files:**
- Create: `backend/src/feedback/feedbackCrypto.ts`
- Create: `backend/src/feedback/feedbackRepository.ts`
- Create: `backend/src/routes/feedback.ts`
- Create: `backend/src/__tests__/feedback.routes.test.ts`
- Modify: `backend/src/config/env.ts`
- Modify: `backend/src/index.ts`
- Create: `mobile/src/services/feedbackClient.ts`
- Create: `mobile/src/services/__tests__/feedbackClient.test.ts`

**Interfaces:**
- Produces: `POST /api/v1/feedback-examples` returning an opaque receipt ID.
- Produces: `DELETE /api/v1/feedback-examples/:receiptId` scoped to the enrolled device.

- [ ] Write failing tests for strict payload bounds, explicit consent timestamp, authentication, idempotency, ciphertext-at-rest, content-free metadata/logs, and owner-scoped deletion.
- [ ] Implement AES-256-GCM envelope encryption using a Railway secret key; store nonce/tag/ciphertext and content-free lifecycle metadata in a dedicated SQLite database.
- [ ] Implement upload/delete clients that update local receipt state without blocking normal coaching.
- [ ] Verify no feedback content appears in logs or operational ledgers; run backend/mobile tests and commit.

### Task 5: Package the hosted API for Railway with hard budgets

**Files:**
- Create: `backend/Dockerfile`
- Create: `railway.json`
- Create: `backend/src/__tests__/productionConfig.test.ts`
- Modify: `backend/src/config/env.ts`
- Modify: `docs/setup.md`
- Modify: `docs/architecture.md`

**Interfaces:**
- Consumes: Railway environment secrets and one persistent volume mounted for operational/auth/feedback SQLite files.
- Produces: `/health` and authenticated `/api/v1/*` over HTTPS.

- [ ] Write production-config tests that fail closed without provider key, credential pepper, feedback encryption key, public origin, durable volume path, and daily/monthly/per-request ceilings.
- [ ] Add a non-root multi-stage container, health check, graceful SQLite closure, and one-instance deployment constraint.
- [ ] Document exact Railway variables without values, volume mount, region, resource cap, log policy, and rollback procedure.
- [ ] Run container build, backend full tests/build, secret scans, and commit.
- [ ] Stop for Baah approval before creating Railway resources, adding billing, setting secrets, or deploying.

### Task 6: Produce a standalone iPhone release build

**Files:**
- Create: `mobile/eas.json`
- Modify: `mobile/app.json`
- Modify: `mobile/src/config/env.ts`
- Modify: `docs/features/local-first-cutover-qa.md`
- Modify: `docs/setup.md`

**Interfaces:**
- Consumes: the hosted HTTPS API origin as a non-secret build variable.
- Produces: a signed release-mode iOS build with no Metro dependency.

- [ ] Add environment tests proving production rejects localhost/LAN origins and contains no provider/enrollment secret.
- [ ] Configure distinct development, personal-alpha internal, and future store profiles; disable dev-client behavior in personal alpha.
- [ ] Run Expo config inspection, mobile full tests/typecheck, native config diff review, and secret scan.
- [ ] Stop for Baah approval before EAS cloud upload or Apple credential action; prefer a local Xcode release install for the first registered iPhone.
- [ ] Install the signed build and confirm launch with Metro stopped.

### Task 7: Run personal-alpha privacy, recovery, and quality QA

**Files:**
- Modify: `docs/features/local-first-cutover-qa.md`
- Modify: `docs/features/personal-alpha-release.md`
- Modify: `docs/v1-status.md`
- Modify: `docs/workflow.md`

**Interfaces:**
- Produces: dated device evidence and the final Ship recommendation.

- [ ] Verify text and voice coaching on cellular with the Mac and Metro stopped.
- [ ] Verify local persistence, force-quit recovery, credential revocation/re-enrollment, and hard cost rejection before provider calls.
- [ ] Verify local reactions cause zero feedback traffic; preview, redact, share, inspect receipt, and delete one synthetic feedback example.
- [ ] Verify logs/databases contain no prohibited plaintext and complete the pending SQLCipher/recovery/privacy checks that block Ship.
- [ ] Run backend/mobile full verification, workflow verification, DS compliance, diff checks, and final code review.
- [ ] Present evidence and stop at Baah's Ship gate before PR merge or branch cleanup.
