# Shared Chat and Recording Shell Design

**Status:** Approved — implementation plan awaiting Baah approval

## Purpose

Chatting with Taisa and recording a voice reply are states of the same experience. They must use one page shell so their header, title, margins, safe-area handling, background, and footer geometry cannot drift apart.

## Experience contract

- The page title is always **Taisa**, including a brand-new recording with no conversation yet.
- The same header remains mounted across idle, recording, paused, and conversation states.
- Header margins, close button, title typography, safe-area spacing, and trailing balance space are identical in every state.
- Recording replaces only the page content and footer state. It does not mount a separately positioned page.
- The recording content keeps the static Taisa mark, greeting, raw-amplitude timestamp glow, and approved 56px controls.
- Chat and recording footers share the same horizontal margins, bottom inset, width, and alignment rules.
- The Taisa mark does not animate.

## Context-sensitive cancellation

Cancel always means “discard this recording and return to where recording began,” but its destination depends on the entry context:

- **Existing/open chat:** stop and discard the recording, then return to that chat’s Reply state.
- **Main/new voice recording:** stop and discard the recording, then close the Taisa page and return to the previous app surface.

The shared presentation component does not decide navigation. The chat screen supplies the correct cancel handler and context-specific accessibility label:

- `Cancel recording and return to chat`
- `Cancel recording and close`

Close remains available during recorder acquisition or failure. Pause and Send remain disabled until native recorder acquisition completes.

## Component architecture

### Shared page shell

`ChatScreenShell` owns the page frame for all chat states:

- keyboard avoidance;
- morph animation container;
- `ChatNavBar` with the title `Taisa`;
- content region;
- footer region.

It remains business-logic free and accepts rendered content and footer nodes.

### Recording content

The center portion of `ActiveRecordingSurface` becomes a presentational recording-content component. It owns only the static mark and greeting. It does not own a page background, safe-area header, absolute page footer, title, or navigation behavior.

### Recording action bar

The recording controls become a footer presentation component rendered through the same footer slot as `VoiceComposer`. It receives duration, amplitude, paused/disabled state, labels, and callbacks. It owns button arrangement but no recorder or navigation state.

### Screen orchestration

`app/chat/index.tsx` remains the state and routing owner. It selects:

- conversation content versus recording content;
- Reply/composer footer versus recording footer;
- the cancel destination based on whether an initial conversation exists;
- recorder acquisition guards and cleanup.

The screen no longer returns a separate full-screen recording page before rendering `ChatScreenShell`.

## State behavior

| State | Shared header | Content | Footer |
|---|---|---|---|
| Empty/Reply | Taisa | Empty conversation state | Reply control |
| Recording | Taisa | Static Taisa mark + greeting | Cancel, Keyboard, timestamp glow, Pause, Send |
| Paused | Taisa | Static Taisa mark + greeting | Cancel, Keyboard, timestamp, Resume, Send |
| Conversation | Taisa | Messages | Voice/text composer |
| Recorder acquisition | Taisa | Recording content | Cancel and Keyboard available; Pause and Send disabled |
| Recorder failure | Taisa | Existing error treatment | Context-appropriate exit and retry actions |

## Error and lifecycle behavior

- A failed standalone recording start closes the process through the existing main-recording cancel route.
- A failed recording start inside an open chat returns to Reply without closing the chat.
- Closing or cancelling always runs the existing owned-recording cleanup barrier.
- The shell does not remount during recording state changes, preventing header jumps and morph discontinuities.
- Existing reverse card morph and reduced-motion behavior remain unchanged.

## Design-system impact

- Reuse `ChatScreenShell`, `ChatNavBar`, `SecondaryIconButton`, `Button`, `RecordingVoiceMark`, and `VoiceReactiveTimestamp`.
- Refactor `ActiveRecordingSurface` into reusable content/footer presentation boundaries; do not introduce business logic.
- Keep NativeWind and semantic theme tokens. Do not add `StyleSheet.create()`, dependencies, or raw colors.
- Update Storybook stories and `docs/design-system.md` for the revised recording composition.

## Verification

- Component tests prove chat and recording render through one `ChatScreenShell` contract.
- Tests prove both contexts use the title `Taisa`.
- Tests prove existing-chat Cancel returns to Reply while standalone Cancel closes the page.
- Tests prove Close/Cancel/Keyboard remain available during recorder acquisition while Pause/Send remain disabled.
- Tests preserve the static mark and raw-amplitude timestamp glow contract.
- Mobile TypeScript, full mobile Jest suite, design-system verification, and `git diff --check` pass.
- Device QA compares chat and recording header margins, title alignment, button geometry, footer margins, state transitions, and both Cancel destinations.

## Out of scope

- Changing recording/transcription persistence.
- Changing the glow palette or amplitude mapping.
- Redesigning conversation messages or text entry.
- Changing card-morph timing or bottom navigation behavior.
