# Taisa Product Scope Design

**Date:** 2026-08-09  
**Status:** Approved in brainstorming; awaiting written-spec review  
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

The assembler enforces a fixed context budget and includes only a few compact excerpts. The full archive is never injected by default. Each excerpt retains its source identifier and timestamp.

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

The mobile app handles the experience. Taisa's backend handles coaching, memory, data, and AI providers.

### Mobile client

- Capture composer and transcript review
- Conversation display and follow-ups
- Goals, actions, evidence, and memory controls
- History and search
- Motion, gestures, and haptics

### Taisa API

- Conversation service
- Coaching orchestrator
- Context assembler
- Evidence retriever
- Memory governance
- Cost and usage guardrails
- Stable contracts independent of mobile framework

### Storage and external services

- SQLite conversation archive
- Durable-memory records
- Goals, actions, and evidence
- AI coaching provider
- Speech transcription provider
- Cached immutable transcripts and coaching outputs

The mobile client does not build vendor prompts, read database tables, or decide memory mutations. This boundary allows a later SwiftUI client or AI-provider change without rebuilding the product engine.

## Cost model

### Free or local operations

- Compose text
- Record audio before submission
- Browse and search history
- Reopen conversations
- View, edit, and complete goals or actions
- Inspect and correct durable memory
- Store conversations and cached outputs

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
- Provide deterministic fixtures for development and automated testing
- Do not run background AI jobs

The exact monetary ceiling is a configuration and validation decision, not hard-coded product scope.

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

## Delivery slices

### Slice 1: Honest coaching loop

Unify text and voice submission, transcript handling, one coaching response, follow-ups, structured deltas, and cost instrumentation. Use existing UI only as a validation client.

### Slice 2: Remember what matters

Add governed durable-memory storage, compact context assembly, and duplicate/conflict detection within the coaching request.

### Slice 3: Follow through

Add confirmation flows, action evolution, first-class evidence, traceability, and reliable long-term resume.

### Slice 4: Validate quality and platform

Measure activation, habit, continuity, trust, cost, and physical-device interaction quality. Use the result as the checkpoint for continued React Native investment versus a SwiftUI client.

## Error handling

- Failed transcription preserves the recording and offers retry without another recording.
- Failed coaching preserves the submitted thought and permits explicit retry.
- Retried operations use idempotency keys to avoid duplicate conversations, actions, evidence, or memory.
- Invalid structured AI output produces no state mutation; the conversation remains recoverable.
- A failed durable-memory write does not hide a successful coaching response and is surfaced as a recoverable sync issue.
- Cost-limit failures explain the limit without discarding the user's draft.
- Missing or contradictory evidence triggers uncertainty, not confident invention.

## Validation and testing

### Behavioral validation

- **Activation:** Complete capture → coaching → saved outcome once.
- **Habit:** Complete the primary journey on three separate days within 14 days.
- **Continuity:** Resume one prior conversation or evolve one existing goal/action.
- **Trust:** Inspect or correct one proposed durable-memory change.
- **Viability:** Measured AI and transcription cost remains within the agreed per-journey ceiling.

### Engineering validation

- Contract tests for text and voice submissions
- Prompt/context snapshot tests with deterministic fixtures
- Structured-response schema validation tests
- Memory admission, lifecycle, and confirmation-policy tests
- Duplicate/conflict and supersession tests
- Evidence ranking and context-budget tests
- Idempotency and partial-failure tests
- Usage metering and ceiling tests
- Existing backend, shared-type, and minimal mobile integration checks

## Approval boundary

This document approves product scope and architecture only. It does not approve implementation. The next artifact is a Platform-first implementation plan. Detailed UI information architecture, visual design, and component work remain a separate Product-track scope led by Baah after the engine is usable.
