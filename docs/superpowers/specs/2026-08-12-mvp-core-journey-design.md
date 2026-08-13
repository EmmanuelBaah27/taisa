# Taisa MVP Core Journey Design

**Date:** 2026-08-12

**Status:** Approved and MECE-reviewed

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
2. Voice is sent for transcription and coaching only after deliberate submission.
3. The transcript appears as the sent user message and remains correctable afterward; correction
   visibly regenerates coaching instead of silently rewriting history.
4. Deliberate coaching submission sends only bounded relevant context to the configured
   provider.
5. Taisa applies safety, relevance, and context-sufficiency checks before choosing a coaching
   stance or proposing any durable outcome.
6. Taisa responds, connects only supported history, and may propose memories or commitments.
7. The user confirms consequential memory changes and reviews proposed commitments.
8. Conversations, decisions, actions, and evidence persist locally and remain resumable.
9. Home answers: **What should I focus on today?**

## MVP workstreams

### 1. Input, submission, and recovery

Complete the device QA and recovery boundaries already represented in
`docs/features/local-first-cutover-qa.md`:

- text and voice submission;
- voice-first capture with pause/resume, keyboard switching, mixed voice/text drafts, and
  post-send transcript correction;
- immediate Recents refresh;
- force-quit/restart continuity;
- encrypted export/restore and key-loss recovery;
- keyboard, Face ID, and interrupted-request recovery;
- strict per-request and cumulative cost ceilings.

Small UX issues that obstruct the journey are fixed during this workstream. Pure polish that
does not affect comprehension, control, privacy, or task completion is deferred.

### 2. Response decisioning

Every deliberate coaching submission follows one ordered decision pipeline in the same bounded
provider call:

1. **Safety:** apply applicable safety behavior before career steering.
2. **Relevance:** decide whether Taisa should coach fully, bridge briefly, or remain concise.
3. **Context sufficiency:** decide whether the supplied turn and bounded context support a
   responsible answer.
4. **Coaching stance:** only then choose Mirror, Nudge, Challenge, or Direct.

The three relevance levels are mutually exclusive:

1. **Career-relevant:** the primary subject is the user's work, career, professional decisions,
   workplace relationships, goals, actions, or evidence. Engage fully using bounded context.
2. **Adjacent personal context:** the primary subject is personal, but the user has stated a
   concrete effect on their work, wellbeing at work, professional decisions, relationships, or
   goals. Respond briefly and use only that explicit bridge.
3. **Outside Taisa's scope:** neither condition above is met. Provide a concise acknowledgement,
   avoid an extended general-assistant exchange, and optionally ask how it connects to work.

Context sufficiency is a separate axis from relevance:

1. **Sufficient:** the response can be grounded without inventing a material fact. Respond within
   the selected relevance behavior.
2. **Partially sufficient:** a useful bounded response is possible. Answer only the supported
   portion and state the material limitation.
3. **Insufficient:** a missing referent, event, participant, purpose, or source is necessary to
   answer. State what is unknown and ask one neutral clarifying question.

Words such as “this,” “that meeting,” “the video,” or “what happened earlier” never authorize
Taisa to invent the referenced object, its purpose, its participants, or the user's emotional
meaning. If clarification is necessary, Taisa must not offer advice or propose memory, evidence,
goals, or actions. A partially sufficient response may propose an outcome only when that proposal
is grounded entirely in the supported portion.

Off-topic material must not automatically become durable career memory, evidence, goals, or
actions. A user may still explicitly create a relevant commitment after Taisa makes the bridge.
The decision pipeline does not introduce background analysis or a second provider call.

### 3. Durable outcomes

Taisa may extract a possible memory, goal, action, or evidence item from a supported coaching
response, but it does not silently persist a consequential interpretation or activate a
commitment.

Flow:

`Conversation → proposed outcome → review → confirm/edit/dismiss → active record → later transition`

Action proposals appear in the proposed inbox and may then move through completion into evidence.
Each proposal carries its originating conversation and related records. Confirming, editing,
dismissing, completing, pausing, or superseding is explicit and stored locally. Duplicate or
evolving outcomes are reconciled rather than blindly appended. Future integrations use this same
review boundary and never bypass confirmation.

### 4. Feedback and evaluation

Each coaching response may expose one optional, replaceable primary reaction:

- Helpful
- Missed context
- Too generic
- Not relevant

Choosing another reaction replaces the earlier primary reaction; the private note may accompany
any selection. This keeps the categories mutually exclusive in storage while allowing nuance in
the note.

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

### 5. Navigation and retrieval

The initial navigation is replaced only after the core behavior above is stable. Proposed MVP
destinations are:

- **Today:** focus, open commitments, and the most relevant next step; recent conversations
  appear beneath.
- **Conversations:** searchable history, pending recovery states, and exact resume.
- **Progress:** goals, evidence, recurring patterns, and movement over time.
- **Actions:** the destination that displays the proposed inbox, active commitments, and completed
  actions; outcome creation and lifecycle rules remain owned by Durable outcomes.
- **You:** career context, coaching preferences, privacy, export/restore, and provider/cost
  visibility.

The persistent capture control remains available across primary destinations. Navigation owns
only discovery, presentation, and retrieval; it does not redefine coaching or outcome lifecycle
rules. Navigation labels and screen composition require a Product design handoff before
implementation.

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
- Recording begins automatically only after explicit voice entry. Switching inputs never submits.
  Only locally detected speech becomes a removable Voice Draft; silence, isolated noise, and
  sub-second non-speech are discarded.
- A conversation preserves its deliberately chosen input modality. After Taisa answers a voice
  turn, the composer returns to a non-recording **voice-ready** state: a soft-grey control with a
  black waveform icon and the label **Reply**. One tap begins the next recording. It never
  activates the microphone merely because Taisa finished responding. Switching to keyboard makes
  text the conversation's active modality until the user switches back.
- The whole voice-ready control is tappable and has the accessibility label “Reply by voice,
  starts recording.” While coaching is processing it is disabled; offline recording remains
  available because capture is local, while Send explains that a connection is required.
- The locally stored conversation modality changes only through an explicit voice/keyboard
  switch. It survives app restart and conversation resume. Failed voice submission retains the
  voice draft and voice modality; transcript correction returns to voice-ready after regenerated
  coaching. Cancelling a recording returns to voice-ready without changing the modality.
- The waveform is the only voice symbol across the primary record control, voice-mode switch, and
  Reply control. Text input contains no voice icon. In text mode, a plain grey waveform switches
  to voice and starts a new recording; when a valid draft exists, the same control includes its
  duration and opens the draft actions without recording.
- A valid stopped voice draft opens voice mode at **Delete / Resume / Send**. Resume continues the
  same draft; Send submits it; Delete returns to the default text entry with the keyboard active.
- Once a voice submission has been attempted, its recovery state permits only **Try again** or
  **Delete recording**. The user cannot append audio, resume recording, or type into that submitted
  turn. Deleting returns to the default text entry because nothing completed.
- New capture never silently resumes old failed work; History exposes explicit Resume.
- Cost, validation, and privacy rejection happen before provider invocation whenever possible.
- The UI explains the safe next action without revealing provider payloads or private content in
  logs.

## Execution order and gates

1. Finish input/submission/recovery device QA and commit current QA fixes.
2. Build the ordered response-decisioning contract with synthetic evaluation fixtures.
3. Complete durable-outcome review and the proposed action inbox.
4. Design and build the optional local feedback control.
5. Produce the navigation design handoff, then implement Today-first information architecture.
6. Reassess the MVP against observed use before promoting any integration.

Platform behavior precedes Product surfaces. Baah approves Scope, Plan, device QA, and Ship at
the existing workflow gates.

## Success criteria

- A user can complete text and voice coaching journeys and resume them after interruption.
- Taisa uses relevant longitudinal context without unrelated context leakage.
- Missing referents trigger a neutral clarification rather than invented context, emotion, advice,
  or durable proposals.
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
