# Taisa Product Scope Design

**Date:** 2026-08-09  
**Status:** Approved in brainstorming; local-first revision approved
**Tier:** Full  
**Track:** Platform first; Product UI follows separately  
**Authors:** Baah + Codex

## Product thesis

Taisa is a senior-self career coach, not a journal with AI attached. A user brings a real work moment, receives a useful interpretation or next move, preserves what matters, and can return later without rebuilding the context.

The MVP promise is:

> Talk through a real work moment, leave with one clearer interpretation or next action, and return to continue it later.

The product rule is:

> Capture freely. Analyse on submission. Remember what matters.

Composing, recording, browsing, searching, reopening, editing, and completing records do not trigger AI. A deliberate submission triggers transcription when the input is audio and one controlled coaching request. Background re-analysis is excluded.

## Product goals

1. Help the user interpret a real work moment and identify a useful next move in under five minutes.
2. Preserve durable career context so coaching remains coherent across months.
3. Evolve existing goals, commitments, and actions instead of accumulating duplicates.
4. Preserve evidence of progress without requiring a separate archive workflow.
5. Validate the coaching habit with controlled and measurable AI and transcription cost.
6. Keep the product engine portable so a future SwiftUI client can reuse it.
7. Keep the user's readable career archive on the phone and disclose every operation that sends content to an external processor.

## Non-goals

- Proactive AI-generated Today feed
- Weekly AI digest
- Background pattern detection or archive re-analysis
- Full trajectory dashboard
- Automatic CV rewriting or a dedicated CV archive
- Semantic vector search
- Payments or subscriptions
- Android client
- SwiftUI rewrite during MVP validation
- Autonomous changes to consequential career memory
- Taisa-readable cloud backup or server-authoritative user data
- Seamless multi-device synchronization
- Fully on-device coaching or transcription

## User journeys

### 1. Think through a work moment

**Goal:** “Help me make sense of what happened and decide what to do.”

1. The user opens Taisa after a win, difficulty, decision, uncertainty, or upcoming conversation.
2. The user composes text or records audio without incurring an AI cost.
3. For audio, the user deliberately submits and reviews the resulting transcript.
4. Taisa assembles the current thread, compact durable memory, and bounded relevant evidence.
5. One coaching request analyses the moment, connects it to the user's career context, and returns a useful response.
6. The response may include proposed changes to a goal, action, evidence item, or durable memory.
7. The user may ask a follow-up and may save or confirm a useful outcome.

**Success:** The user leaves with one clearer interpretation or next move in under five minutes.

### 2. Continue unfinished thinking

**Goal:** “Help me pick this up without reconstructing everything.”

1. The user browses or searches conversation history.
2. A result shows enough context to recognize the topic and last outcome.
3. The user reopens the original conversation, including one from months earlier.
4. A new submission includes the current thread and current durable career state.
5. The outcome can evolve an existing goal or action rather than create a duplicate.

**Success:** The user can resume a prior conversation without repeating its context.

### 3. Keep career evidence

**Goal:** “Do not let useful wins, decisions, and lessons disappear.”

1. During coaching, Taisa identifies candidate evidence already supported by the submitted moment.
2. The evidence is linked to its source conversation and optionally to a goal or development area.
3. The user can find the evidence later through the Career surface or source conversation.

**Success:** Evidence is retained during the coaching flow without a separate archiving task.

### 4. Maintain useful context

**Goal:** “Understand my career direction without inventing things about me.”

1. Lightweight onboarding captures role, goals, and coaching preferences.
2. Taisa maintains compact durable memory from submitted conversations.
3. Safe, non-consequential evidence links can update automatically.
4. Ambiguous, sensitive, or direction-changing updates require confirmation.
5. The user can inspect, correct, reject, archive, or delete durable records.

**Success:** Coaching feels longitudinally relevant while the user remains in control.

## Product surfaces

The scope describes product responsibilities, not final UI designs. Detailed UI work follows in a separate Product-track design cycle.

### Today

Provides a lightweight return point: resume an open action or start a new thought. It does not generate a proactive AI feed in the MVP.

### Conversation

Supports text and voice composition, deliberate submission, transcript review, coaching responses, follow-up turns, and confirmation of proposed changes.

### Career

Provides coherent access to goals, open actions, saved evidence, and governed durable memory.

### History

Supports browsing, local search, reopening conversations, and tracing saved outcomes to source conversations.

These responsibilities may be combined into fewer navigation destinations during UI design. They do not mandate a four-tab interface.

## Privacy and data ownership

The iPhone is the authoritative store for readable user data. Conversations, transcripts, profile, goals, commitments, actions, evidence, durable memory, and cached coaching outputs live on-device.

The product distinguishes two actions:

- **Private save:** Preserve a draft, note, or recording locally without AI processing.
- **Submit to Taisa:** Send a deliberately selected, minimal context package to external transcription and/or coaching processors.

Local storage does not mean fully on-device processing. The UI must clearly disclose that submitted content leaves the phone for processing. Users should not submit employer-confidential content when their workplace policy prohibits external AI processing.

### Privacy principles

1. Only deliberate submission sends user content off-device.
2. Send the minimum context required for useful coaching, never the full archive by default.
3. Do not log request or response bodies in the Taisa gateway, infrastructure logs, analytics, or crash reporting.
4. Keep provider identifiers and cost metadata without retaining user content.
5. Cache transcripts and coaching outputs on-device so unchanged work is never resubmitted automatically.
6. Make provider processing visible and allow the user to remove or redact identifiers before submission.
7. Treat private local capture as a complete supported outcome, not a failed or incomplete coaching flow.
8. Use only paid/commercial API paths whose terms state that submitted content is not used to train or improve provider models by default.
9. Keep provider selection server-side so changing a model never requires a mobile release or migration of the local archive.

### Device protection and recovery

- Encrypt the local database using a key protected by the iOS Keychain.
- Support an optional Face ID/app lock after the core local data path is stable.
- Hide sensitive content in notification previews and the app switcher.
- Provide manual encrypted export and restore in the MVP recovery slice.
- Treat optional end-to-end encrypted backup as a later capability. Taisa must not possess the decryption key.
- Explain during onboarding that data is not recoverable before the user creates an encrypted export.

Device-local authority creates accepted constraints: loss risk before export, no seamless multi-device state, harder support diagnostics, on-device migrations, and weaker background intelligence. These are explicit tradeoffs, not accidental omissions.

## Durable career memory

Chats preserve conversations. Durable memory preserves what those conversations mean for the user's career.

### Memory types

- Goal
- Commitment
- Decision
- Preference
- Career context
- Development area
- Evidence
- Pattern

Each record has independent metadata:

| Dimension | Values |
|---|---|
| Provenance | user-stated, user-confirmed, AI-inferred, system-observed |
| Lifecycle | proposed, active, paused, superseded, completed, rejected, archived |
| Confidence | tentative, supported, established |
| Time | created, confirmed, last-supported, status-changed timestamps |
| Traceability | source conversation and message identifiers |

### Admission rule

A candidate becomes durable only if knowing it could materially change future coaching. Ordinary conversational detail remains in the archive.

### Mutation protocol

1. Analyse the submitted thought.
2. Compare proposed meaning with active durable memory.
3. Propose an add, update, relationship, pause, completion, or supersession.
4. Request confirmation when the change is ambiguous, sensitive, identity-level, or direction-changing.
5. Persist the approved or safely automatic change with source traceability.

Taisa may automatically archive conversations, link evidence to a confirmed entity, strengthen support for an existing observation, and record an explicitly completed action. It must ask before creating or replacing a career goal, promoting an inference into an accepted fact, storing a sensitive interpretation, superseding a decision or preference, or merging potentially distinct goals.

Contradictory evidence lowers confidence or prompts a question. It never silently overwrites existing memory. Superseded records remain available so Taisa can understand how the user's direction evolved.

## Context assembly and evidence retrieval

Every coaching request contains:

- The current submitted thought
- The active conversation's bounded history
- Compact profile context
- Active and paused goals
- Open commitments and actions
- Relevant durable decisions, preferences, and career context
- Coaching preferences

Relevant archive evidence is added only when needed. Retrieval ranks candidates by:

1. Direct durable-entity link
2. Shared goal, commitment, or action
3. Recency
4. Text relevance

The on-device assembler enforces a fixed context budget and includes only a few compact excerpts. The full archive is never injected by default. Each excerpt retains its source identifier and timestamp. The gateway validates the package shape and limits but does not retrieve or retain user history.

## Coaching engine

A submitted turn follows this pipeline:

```text
Input
  → transcribe if voice
  → assemble compact context
  → retrieve bounded evidence
  → analyse and choose coaching stance
  → return coaching response
  → return structured proposed deltas
  → apply safe writes or request confirmation
```

The response contract separates user-facing coaching text from structured proposals. Structured proposals may target goals, commitments, actions, evidence, decisions, preferences, development areas, or patterns. This prevents mobile clients from parsing prose to determine state changes.

The four named coaching modes—Mirror, Nudge, Challenge, and Direct—may inform the internal stance in the MVP, but do not require separate user-selectable modes or additional AI calls.

## Architecture boundary

The mobile app handles the experience and owns durable user data. Taisa's gateway handles provider credentials, request validation, cost enforcement, and transient AI orchestration. External providers perform transcription and coaching.

### Mobile client

- Capture composer and transcript review
- Conversation display and follow-ups
- Goals, actions, evidence, and memory controls
- History and search
- Motion, gestures, and haptics
- Encrypted local database and migrations
- Durable-memory governance and evidence retrieval
- Context assembly and redaction preview
- Private save versus deliberate submission
- Encrypted export and restore

### Stateless Taisa gateway

- Provider credential protection
- Request authentication and validation
- Payload-size and context-budget enforcement
- Transient coaching and transcription orchestration
- Provider abstraction
- Content-free usage and cost accounting
- Stable contracts independent of mobile framework
- No user-content database and no request/response body logging

### On-device storage and external services

- Encrypted SQLite conversation archive
- Durable-memory, goals, actions, and evidence
- Cached transcripts and coaching outputs
- Encrypted export files
- AI coaching provider
- Speech transcription provider

The mobile client does not hold provider credentials or depend on provider-specific response formats. Shared contracts define the coaching input, structured response, memory deltas, and usage envelope. Memory governance is deterministic client-side product logic; the AI may propose deltas but cannot persist them directly.

### Provider strategy

Taisa owns one provider-neutral coaching contract. Provider adapters translate that contract to external APIs and must return the same schema-validated response and content-free usage receipt.

- **Primary MVP candidate:** the lowest-cost capable OpenAI model that passes Taisa's evaluation pack. OpenAI also supplies the initial speech-transcription path, keeping the first operational setup to one account and billing surface.
- **Quality benchmark:** Anthropic Sonnet. The existing Anthropic implementation remains available behind configuration for comparison and controlled fallback, not automatic retry.
- **Not an MVP production provider:** DeepSeek. It may be evaluated with synthetic, non-sensitive fixtures, but it must not receive real work or personal content until Taisa can verify API-specific training, retention, processing-location, and structured-output commitments appropriate to the product's privacy promise.
- **Not permitted for sensitive production data:** unpaid Gemini services or any other provider tier that may use prompts or responses to improve products or expose them to human review.

The MVP integrates at most two coaching providers: OpenAI and Anthropic. It does not build model routing, automatic quality escalation, or a provider marketplace. A model is selected through gateway configuration, and every submitted turn still makes at most one paid coaching call.

Provider adoption is evidence-led. A versioned pack of at least 20 synthetic Taisa scenarios measures coaching usefulness, continuity and conflict detection, action quality, memory-proposal correctness, schema compliance, latency, and estimated cost. No production default is chosen solely from published benchmarks or token price.

This target differs from the current implementation, where backend SQLite is authoritative and Express routes perform user-data CRUD. The migration reuses the existing schema concepts and prompt services while relocating durable storage, retrieval, and mutations to the phone. During transition, dual authority is prohibited: each migrated entity has one declared authoritative store.

A future SwiftUI client can reuse the gateway contracts and product rules, but it will need to import or migrate the encrypted on-device archive.

## Cost model

### Free or local operations

- Compose text
- Record audio before submission
- Browse and search history
- Reopen conversations
- View, edit, and complete goals or actions
- Inspect and correct durable memory
- Store conversations and cached outputs
- Assemble memory context and retrieve evidence
- Export and restore an encrypted archive

### Metered operations

- Transcribe deliberately submitted audio
- Run one coaching request for each deliberately submitted thought or follow-up

### Guardrails

- Cap recording duration for the MVP
- Cache transcripts permanently for unchanged audio
- Never regenerate an unchanged coaching result automatically
- Include compact memory rather than the full archive
- Log provider, model, input/output tokens, transcription duration, estimated cost, latency, and outcome for each metered journey
- Enforce configurable daily and per-request ceilings
- Enforce a configurable monthly ceiling and fail closed before a request that would exceed it
- Expose a development-only cost summary without storing prompt or response content
- Provide deterministic fixtures for development and automated testing
- Do not run background AI jobs
- Strip or hash content from gateway telemetry and error reporting
- Offer a redaction preview for selected names, organizations, project names, and metrics

The exact monetary ceiling is a configuration and validation decision, not hard-coded product scope.

Provider prices and model names are runtime configuration, not durable product rules. The gateway records the selected provider/model and actual usage returned by the provider; estimated cost is calculated from configuration so pricing changes do not require an app release.

## MVP feature inventory and current state

| Capability | Current position | Required MVP change |
|---|---|---|
| Text and voice capture | Voice-led UI; backend accepts text | Unified deliberate submission contract |
| Transcription | Whisper route exists | Submit-only invocation, cap, caching, usage logging |
| Coaching | One-shot analysis and basic chat exist | Unified coaching orchestrator and structured deltas |
| Conversation continuity | Sessions, messages, and search exist | Reliable long-term resume and outcome preview |
| Durable memory | Goals, actions, themes exist separately | Governed memory model and lifecycle |
| Goal/action evolution | CRUD and progress fields exist | Compare, propose, confirm, update, supersede |
| Career evidence | Wins exist inside analysis JSON | First-class evidence linked to source and goals |
| Cost controls | Provider calls exist without product guardrails | Metering, caps, caching, fixtures, visibility |
| User control | Limited profile editing | Inspect, correct, reject, archive, and delete memory |
| Data authority | Backend SQLite owns durable data | Migrate durable entities to encrypted on-device SQLite |
| Gateway privacy | Express routes read and write user content | Stateless validated forwarding with content-free telemetry |
| Recovery | JSON export from backend-oriented data | Manual encrypted device export and restore |

## Delivery slices

### Slice 1: Honest coaching loop

Define portable contracts and make the gateway stateless for the new submission path. Establish encrypted on-device storage, private save, deliberate text/voice submission, transcript handling, one coaching response, structured deltas, and content-free cost instrumentation. Use existing UI only as a validation client.

### Slice 2: Remember what matters

Migrate goals, actions, conversations, and governed durable memory to the authoritative on-device store. Add local context assembly, local evidence retrieval, and duplicate/conflict detection within the coaching request.

### Slice 3: Follow through

Add confirmation flows, action evolution, first-class evidence, traceability, and reliable long-term resume.

### Slice 4: Protect and recover

Add database-key protection, privacy-safe app surfaces, redaction preview, manual encrypted export/restore, migration validation, and explicit recovery disclosures.

### Slice 5: Validate quality and platform

Measure activation, habit, continuity, trust, privacy comprehension, cost, and physical-device interaction quality. Evaluate missed historical connections and diagnostic limitations. Use the result as the checkpoint for continued React Native investment versus a SwiftUI client and for optional end-to-end encrypted backup.

## Error handling

- Failed transcription preserves the recording and offers retry without another recording.
- Failed coaching preserves the submitted thought and permits explicit retry.
- Retried operations use idempotency keys to avoid duplicate conversations, actions, evidence, or memory.
- Invalid structured AI output produces no state mutation; the conversation remains recoverable.
- A failed durable-memory write does not hide a successful coaching response and is surfaced as a recoverable sync issue.
- Cost-limit failures explain the limit without discarding the user's draft.
- Missing or contradictory evidence triggers uncertainty, not confident invention.
- Gateway failures retain no submitted payload and leave the local submission retryable.
- Local migration failures preserve the pre-migration encrypted archive and prevent partial authority changes.
- Export and restore verify archive integrity before replacing active local state.

## Validation and testing

### Behavioral validation

- **Activation:** Complete capture → coaching → saved outcome once.
- **Habit:** Complete the primary journey on three separate days within 14 days.
- **Continuity:** Resume one prior conversation or evolve one existing goal/action.
- **Trust:** Inspect or correct one proposed durable-memory change.
- **Viability:** Measured AI and transcription cost remains within the agreed per-journey ceiling.
- **Privacy comprehension:** The user can distinguish private save from external processing and identify what context will be sent.
- **Recovery:** An encrypted export can restore conversations, memory, goals, actions, and evidence on a clean installation.

### Engineering validation

- Contract tests for text and voice submissions
- Prompt/context snapshot tests with deterministic fixtures
- Structured-response schema validation tests
- Memory admission, lifecycle, and confirmation-policy tests
- Duplicate/conflict and supersession tests
- Evidence ranking and context-budget tests
- Idempotency and partial-failure tests
- Usage metering and ceiling tests
- Gateway no-content-retention and telemetry-redaction tests
- Local database encryption and key-loss behavior tests
- Entity-by-entity authority migration tests
- Encrypted export/restore round-trip and corruption tests
- Private-save versus submit disclosure tests
- Existing backend, shared-type, and minimal mobile integration checks

## Approval boundary

This document approves product scope and architecture only. It does not approve implementation. The next artifact is a Platform-first implementation plan. Detailed UI information architecture, visual design, and component work remain a separate Product-track scope led by Baah after the engine is usable.
