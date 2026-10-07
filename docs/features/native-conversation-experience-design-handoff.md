# Design Handoff — Native Conversation Experience

**Scope doc:** `docs/features/native-conversation-experience.md`
**Design source:** Visual Companion `Persistent dock` direction plus Baah's approved interaction decisions from 2026-10-07
**Precision:** Directional. Implementation latitude applies to exact SwiftUI spacing, materials, and motion. Device QA is the visual and interaction sign-off.
**Status:** Draft — awaiting Baah confirmation
**Last updated:** 2026-10-07

## Experience intent

Conversation is Taisa's persistent primary action, not a destination-specific feature. Home, Conversations, and You retain their own content hierarchy while sharing one bottom-loaded `Talk to Taisa` dock above primary navigation. Tapping the dock is the deliberate microphone action: a full-screen conversation opens and begins listening. Inside that screen the global dock disappears and the conversation's own voice or text composer owns the bottom edge.

The interaction rhythm follows the strongest current React Native behavior without reproducing its implementation: voice begins from an explicit entry action; pause, resume, keyboard replacement, and Send remain stable; only Send submits; destructive changes explain what will be lost; and a completed response returns to a calm Reply action rather than reopening the microphone.

## Layout intent

### Primary app shell

- Three primary destinations: Home, Conversations, and You.
- One persistent Talk to Taisa dock sits above the primary navigation in every destination state.
- Destination content reserves safe-area and dock clearance so the final row remains reachable.
- The dock presents one high-emphasis voice action and an explicit keyboard affordance. Both open a new conversation; voice begins recording, while keyboard opens an empty focused text composer.
- Presenting a conversation removes both the global dock and primary navigation from the active surface.

### Conversations — populated

- The navigation title is `Conversations`.
- A visible Drafts section appears first only when drafts exist.
- Draft rows communicate input kind, recoverable state when applicable, local title or preview, and last-updated time without exposing private text in accessibility summaries beyond what is already visible.
- Completed conversations follow in reverse chronological order.
- Tapping a draft resumes the exact identity. Tapping a completed conversation opens its history at the latest message.
- Draft swipe action: Discard, with confirmation. Completed-conversation overflow actions: Rename and Delete, with deletion confirmation.

### Conversations — empty

- The screen explains that completed conversations and saved drafts will appear here.
- The global dock remains the primary creation action; do not add a competing New conversation button.

### New voice conversation

- Full-screen presentation with a close action, a local fallback title, conversation content region, and bottom composer.
- Initial explicit dock tap starts recording as the screen settles.
- Recording state exposes Keyboard, elapsed time, Pause, and Send with stable geometry.
- Paused state exposes Discard, Resume with elapsed time, and Send.
- Keyboard request from either voice state opens a native destructive confirmation. Cancel restores the exact voice state; Switch discards audio and opens an empty focused text composer.
- Send moves through transcription and coaching status in the same screen. No intermediate transcript-approval page appears for a clear transcript.

### Text conversation

- The composer opens focused with a multiline field and Send action.
- Empty text can return to voice. Once non-whitespace text exists, the voice affordance becomes Send and cannot silently replace the draft.
- Keyboard avoidance keeps the latest message and active controls reachable.

### Waiting and continuing

- After Taisa replies, the composer becomes a calm `Reply` control and does not record automatically.
- Tapping Reply starts the next voice turn. Choosing keyboard starts a text turn.
- Historical conversations use the same screen and same Reply contract; there is no separate read-only history view.

### Dismissal, drafts, and recovery

- Closing or dismissing with no unsent input exits immediately and creates nothing.
- Closing or dismissing with unsent input opens a native choice: Save draft, Discard, or Cancel.
- Saved voice drafts reopen paused. Saved text drafts restore exact text and focus only after the user enters the composer.
- Automatically recovered drafts use the same rows and resume behavior, with a concise recovered-state label.
- Transcription and coaching failures replace progress with Retry, Save draft, and Discard actions. The user is never trapped on the screen.

### Transcript correction

- A sent voice message exposes a semantic correction action.
- Correction opens an editor seeded with the accepted transcript and clearly states that updating it will regenerate Taisa's affected reply.
- The corrected exchange replaces the old one in the visible timeline. Provenance remains internal and is not presented as duplicate messages.

## Component inventory

| Element | Verdict | SwiftUI / Taisa owner |
|---|---|---|
| App lifecycle and recovery gate | Reuse | `apple/TaisaApp/App/AppRootView.swift` |
| Primary destination shell | New | Feature-level `PrimaryAppShell` using native SwiftUI destination selection and safe-area composition |
| Home destination | Modify | Existing `HomeView`; remove generic recent-conversation browsing when the dedicated Conversations destination is live, while preserving local Home queries needed by approved Home scope until that integration is reconciled |
| Global Talk to Taisa dock | New, shared DS | `TaisaDesignSystem/ConversationEntryDock` because it appears on three primary destinations and owns no business logic |
| Primary navigation presentation | New, shared DS | `TaisaDesignSystem/PrimaryNavigation` with Home, Conversations, and You identities; route state remains in the app shell |
| Conversations screen | New, feature-local | `apple/TaisaApp/Conversations/ConversationsView.swift` |
| Conversations state model | New | `TaisaConversations/ConversationsModel` with loading, empty, content, failure, and recovery-required states |
| Draft row | New, feature-local | `DraftRow`; promote only if another screen adopts the same pattern |
| Completed conversation row | Modify | Adapt existing `ConversationRow` into the Conversations feature; avoid maintaining separate row behavior in Home |
| Empty/loading/failure states | Reuse | SwiftUI `ContentUnavailableView`, `ProgressView`, and existing recovery route |
| Row actions | Reuse | SwiftUI `swipeActions`, `Menu`, `confirmationDialog`, and `alert` as appropriate |
| Full-screen conversation shell | New, feature-local | `ConversationView` with standard SwiftUI presentation, safe-area, scroll positioning, and keyboard avoidance |
| Conversation header | New, feature-local | Title, close action, and rename entry; standard controls first |
| Message timeline | New, feature-local | Typed user and assistant message views; extract only proven repeated presentation |
| Voice composer controls | New, shared DS | `TaisaDesignSystem/VoiceComposerControls`; presentational recording/paused/waiting controls backed by typed callbacks |
| Text composer | New, shared DS | `TaisaDesignSystem/TextComposer`; presentational multiline input and send/voice affordance |
| Progress and failure composer states | New, shared DS | `ConversationProgressState` and `ConversationFailureActions`; shared across new, draft, and historical conversations |
| Destructive input confirmation | Reuse | Native `confirmationDialog`; feature owns copy and intent |
| Draft save/discard confirmation | Reuse | Native `confirmationDialog`; feature owns copy and intent |
| Transcript correction editor | New, feature-local | `TranscriptCorrectionView`; editor and regeneration explanation |
| Existing typography, color, spacing, and button primitives | Reuse/Modify | `TaisaText`, `TaisaButton`, `TaisaTypography`, `TaisaColor`, and `TaisaSpacing` |

## Component-state contract

| Surface | Required states |
|---|---|
| Global dock | voice-ready, keyboard entry, disabled during presentation transition |
| Conversations | loading, empty, populated, refreshing, retryable failure, recovery required |
| Draft row | voice paused, text saved, recovered, retryable transcription, retryable coaching |
| Voice composer | preparing microphone, recording, paused, transcribing, coaching, waiting for Reply, permission denied, retryable failure |
| Text composer | empty, focused, drafting, sending, retryable failure |
| Conversation | new, draft resumed, historical, correction editing, deleting, renaming |

## Token coverage

The native token set is sufficient for the current functionality-first Home but not for the approved conversation surfaces.

Required additions before Product screen composition:

- semantic surface roles for raised composer/dock surfaces and subtle selected or pressed states;
- destructive and warning semantic colors for discard, delete, and recoverable failure actions;
- spacing below `compact` only if native control composition cannot express tight icon/text relationships without a raw value;
- reusable corner-radius roles for dock/composer containers and circular controls;
- elevation/material guidance for a dock above scroll content, including reduced-transparency behavior;
- motion roles for dock-to-conversation presentation and Reply-to-recording state change, with reduced-motion fallbacks.

Exact token values are a Plan-stage DS foundation task derived from the directional visual. No screen may introduce raw visual values to bypass these gaps.

## Platform implications

- `ConversationRecord` currently contains only identity, title, and timestamps. The approved UI requires lifecycle status, title authority/refinement state, draft input kind, last activity, and recoverable attention state through a Product-facing projection.
- Current repositories expose entity-by-ID CRUD and message creation. Conversations needs deterministic draft and history queries, rename, confirmed delete/discard, and one atomic resume snapshot without exposing GRDB to SwiftUI.
- Draft persistence must represent text exactly and voice by encrypted app-owned audio reference plus durable turn checkpoint; it must not store raw audio in database export.
- The existing `VoiceSessionCoordinator` remains the only native voice lifecycle owner. Product needs a stable adapter for new entry, resume, pause, send, retry, save draft, discard, correction, and explicit Reply.
- Text turns need equivalent checkpoint, idempotency, retry, and reconciliation semantics without duplicating voice orchestration.
- The first coaching response contract must carry an optional short title suggestion. Local fallback title creation must not wait for the gateway, and manual rename must set an authority state that prevents later overwrite.
- Transcript correction requires a revision/provenance contract and deterministic assistant-response supersession rather than appending a duplicate visible turn.
- Home currently owns a generic recent-conversations section. Introducing the approved dedicated Conversations destination requires a deliberate integration step so temporary Home behavior does not become a second history surface.

## Accessibility and adaptability

- Every dock and composer action has a visible or explicit accessibility label describing whether it starts recording, switches input, sends, saves, retries, or destroys content.
- VoiceOver announcements cover microphone readiness, recording/paused transitions, transcription, coaching, failure, draft saved, and reply ready without announcing live amplitude.
- Confirmation focus returns to the initiating control on cancel.
- Draft type, recovered status, and retry-needed status are communicated with text, not color alone.
- Dynamic Type preserves message content and destructive-action comprehension without hiding Send or close actions.
- Reduced Motion replaces spatial morphs with immediate presentation or restrained opacity while preserving state ordering.
- iPad uses adaptable readable width and native presentation rather than a separate information architecture.

## Open questions

None blocking. Exact material, motion curve, and compact spacing values remain implementation latitude within the token foundation and require device QA.

## Ready for plan

The directional design, required states, shared-component boundaries, token gaps, and Platform implications are explicit. After Baah confirms this brief, Platform and Product implementation planning can begin without reopening the approved Scope.
