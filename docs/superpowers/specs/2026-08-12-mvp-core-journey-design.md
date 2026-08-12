# Taisa MVP Core Journey Design

**Date:** 2026-08-12

**Status:** Approved direction; written-spec review pending

**Track:** Platform first, then Product
**Tier:** Full

## Product promise

Taisa helps a person understand what is happening in their work, connect it over time,
decide what matters, and follow through—without surrendering control of their private
career history.

The MVP is not a general-purpose assistant, meeting archive, or integration hub. Its core
value is a trustworthy recurring coaching loop.

## Priority user journey

1. The user freely composes text or records audio locally.
2. Voice is sent for transcription only after deliberate submission.
3. The user reviews and may edit the transcript before coaching.
4. Deliberate coaching submission sends only bounded relevant context to the configured
   provider.
5. Taisa responds, connects relevant history, and may propose memories or commitments.
6. The user confirms consequential memory changes and reviews proposed commitments.
7. Conversations, decisions, actions, and evidence persist locally and remain resumable.
8. Home answers: **What should I focus on today?**

## MVP workstreams

### 1. Reliable coaching loop

Complete the device QA and recovery boundaries already represented in
`docs/features/local-first-cutover-qa.md`:

- text and voice submission;
- transcript review and confirmation;
- immediate Recents refresh;
- force-quit/restart continuity;
- encrypted export/restore and key-loss recovery;
- keyboard, Face ID, and interrupted-request recovery;
- strict per-request and cumulative cost ceilings.

Small UX issues that obstruct the journey are fixed during this workstream. Pure polish that
does not affect comprehension, control, privacy, or task completion is deferred.

### 2. Career-scope guardrails

Every deliberate coaching submission is classified into one of three relevance levels:

1. **Career-relevant:** engage fully using bounded goals, actions, evidence, profile, and
   conversation history.
2. **Adjacent personal context:** answer briefly, then connect the issue to work, wellbeing,
   decisions, relationships, or goals when a genuine bridge exists.
3. **Unrelated:** provide a concise answer, avoid an extended general-assistant conversation,
   and offer an optional work-relevant bridge.

Off-topic material must not automatically become durable career memory, evidence, goals, or
actions. A user may still explicitly create a relevant commitment after Taisa makes the bridge.
Safety-sensitive requests continue to use applicable safety behavior before career steering.

The relevance decision is part of the same bounded coaching call; it does not introduce
background analysis or a second provider call.

### 3. Coaching quality and feedback

Each coaching response may expose a small optional reaction control:

- Helpful
- Missed context
- Too generic
- Not relevant
- Optional private note

Feedback is stored locally and linked to the response, provider/model configuration, and a
content-free context manifest. It is never automatically sent to an AI provider or analytics
service.

Private examples enter an evaluation dataset only with explicit consent. Otherwise, Taisa uses
synthetic scenarios that reproduce the behavioral issue without copying the user's content.
Evaluation scores cover relevance, continuity, context use, actionability, tone, privacy, and
structured-contract validity.

Taisa's coaching quality is controlled in the product repository—not in a provider console—by:

- coaching instructions and response contract;
- bounded context assembly and ranking;
- durable-memory governance;
- conversation-state and steering rules;
- versioned synthetic evaluation scenarios and thresholds.

Provider consoles remain operational tools for billing, usage, and isolated experiments.

### 4. Journey-led information architecture

The initial navigation is replaced only after the core behavior above is stable. Proposed MVP
destinations are:

- **Today:** focus, open commitments, and the most relevant next step; recent conversations
  appear beneath.
- **Conversations:** searchable history, pending recovery states, and exact resume.
- **Progress:** goals, evidence, recurring patterns, and movement over time.
- **Actions:** proposed inbox, active commitments, and completed actions.
- **You:** career context, coaching preferences, privacy, export/restore, and provider/cost
  visibility.

The persistent capture control remains available across primary destinations. Navigation labels
and screen composition require a Product design handoff before implementation.

### 5. Proposed action inbox

Taisa may extract a possible commitment from a coaching response, but it does not silently make
that commitment active.

Flow:

`Conversation → proposed action → inbox → confirm/edit/dismiss → active action → completion → evidence`

Each proposal carries its originating conversation and any related goal. Confirming, editing,
dismissing, completing, pausing, or superseding an action is explicit and stored locally.
Duplicate or evolving actions are reconciled rather than blindly appended.

Future integrations use the same inbox. Their extracted commitments never bypass confirmation.

## Data and privacy boundaries

- The phone remains authoritative for conversations, profile, memory, goals, actions, evidence,
  response feedback, and recovery state.
- Composing, browsing, searching, editing, confirming, and completing are local operations.
- Deliberate submission is the only coaching egress boundary.
- Submitted context remains bounded, relevant, and manifested without logging content.
- Backup passphrases are never stored or recoverable by Taisa; users are told to keep them in a
  separate password manager.
- Feedback and imported data are local by default.

## Error and recovery behavior

- A failed provider request leaves the local message and exact request IDs retryable.
- A failed transcription retains the app-owned recording for explicit retry or abandonment.
- New capture never silently resumes old failed work; History exposes explicit Resume.
- Cost, validation, and privacy rejection happen before provider invocation whenever possible.
- The UI explains the safe next action without revealing provider payloads or private content in
  logs.

## Execution order and gates

1. Finish reliable-loop device QA and commit current QA fixes.
2. Scope and build career-scope guardrails with evaluation fixtures.
3. Design and build the optional local feedback control.
4. Produce the navigation design handoff, then implement Today-first information architecture.
5. Build the proposed action inbox.
6. Reassess the MVP against observed use before promoting any integration.

Platform behavior precedes Product surfaces. Baah approves Scope, Plan, device QA, and Ship at
the existing workflow gates.

## Success criteria

- A user can complete text and voice coaching journeys and resume them after interruption.
- Taisa uses relevant longitudinal context without unrelated context leakage.
- Off-topic prompts receive a brief answer and an appropriate work bridge without derailing
  durable career memory.
- The user can explain why an action or memory was proposed and controls whether it persists.
- Response feedback can be captured without interrupting conversation or exporting private
  content.
- Today provides a clear next focus; Conversations, Progress, Actions, and You have distinct
  responsibilities.
- Provider and transcription costs remain bounded and visible operationally.

## Explicitly out of MVP scope

- Granola, Notion, Google Meet, calendar, email, and document ingestion;
- automatic background analysis of the whole archive;
- cloud-authoritative personal history;
- automatic activation of AI-generated commitments;
- provider-console-owned prompts or evaluation logic;
- broad general-assistant behavior;
- navigation polish that does not improve the priority journey.

Integrations remain in `docs/backlog.md`. When promoted, each must define consent, minimum data
selection, source provenance, revocation, deletion, synchronization, and how extracted items enter
the proposed inbox.
