# Recording Page

## What is it?

The Figma recording-start experience applied to Taisa's fresh local-first voice capture inside `/chat`. The legacy `/recording` route remains a compatibility redirect so recording, cleanup, transcription, and submission continue to have one owner.

## Why now?

The secondary icon action is ready. Building the containing page now proves the primitive in context and brings the primary voice-entry surface in line with the approved Figma direction.

## Acceptance criteria

- [x] Fresh voice capture renders the Figma full-screen white recording layout.
- [x] The top bar shows a secondary close action and centered `New chat` title.
- [x] The empty state shows the animated Taisa voice mark and a neutral greeting.
- [x] The bottom bar shows keyboard, timer, pause/resume, and send controls in the Figma arrangement.
- [x] Close safely cleans up; keyboard preserves the existing voice-draft rules; pause/resume and send use the existing recorder/submission lifecycle.
- [x] Existing conversation, text, transcript-review, processing, and error surfaces continue using the current chat experience.
- [x] The legacy `/recording` route remains a local-first redirect and no legacy API pipeline returns.

## Platform dependencies

The existing local-first `ChatScreen`, `useVoiceRecorder`, recording stop session, and submission lease are already in Build/Review and remain unchanged owners of behavior.

## Out of scope

- Changing transcription or coaching policy.
- Adding a stored display-name field; the greeting remains neutral.
- Redesigning populated conversations or transcript review.
- Reintroducing a standalone recording pipeline.
