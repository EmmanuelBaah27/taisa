# Chat Action Bar Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the approved Figma Reply, recording, and paused action-bar experience into the latest chat-card-expansion runtime.

**Architecture:** Keep `VoiceComposer` as the presentation boundary and keep all recorder, transcription, persistence, and card-expansion behavior in the existing latest-build screen and services. Add a small pure Reply transition reducer so the ready-state button exits before recording begins, then restyle only the voice variants to the approved Figma nodes.

**Tech Stack:** React Native, Expo, NativeWind, React Native Reanimated, TypeScript, Node assertions, Storybook.

**Spec:** Figma nodes `409:4274` and `409:4167`, applied to the latest local-first composer architecture.

## Global Constraints

- Preserve the latest local-first chat, streaming transcription, and chat-card expansion behavior.
- All circular action buttons are exactly 56px.
- Reply fades and scales out before `onStartVoice` runs; repeated taps during exit are ignored.
- Recording uses Keyboard, elapsed time, Pause, and Send.
- Paused uses Discard, Resume with elapsed time, and Send with an 8px right-side gap.
- Reuse existing icons and semantic NativeWind tokens; add no dependencies.

---

### Task 1: Sequence the Reply transition

**Files:**
- Create: `mobile/src/components/ui/voiceComposerTransition.ts`
- Create: `mobile/src/components/ui/__tests__/voiceComposerTransition.test.ts`
- Modify: `mobile/src/components/ui/VoiceComposer.tsx`
- Modify: `mobile/package.json`

**Interfaces:**
- Produces: `reduceVoiceComposerTransition(state, event)` with `idle`, `exiting`, and `recording` states.
- Consumes: existing `VoiceComposerProps.onStartVoice` callback.

- [x] Write assertions that Press enters `exiting`, repeated Press is ignored, and `exit-complete` enters `recording`.
- [x] Run the focused assertion and confirm it fails because the reducer does not exist.
- [x] Add the reducer and wire the ready Reply button to a 160ms opacity/scale exit whose completion invokes `onStartVoice` exactly once.
- [x] Run the focused assertion and confirm it passes.

### Task 2: Match the active and paused Figma action bars

**Files:**
- Modify: `mobile/src/components/ui/VoiceComposer.tsx`
- Modify: `mobile/src/components/ui/VoiceComposer.stories.tsx`

**Interfaces:**
- Consumes: existing `voiceState`, `durationSeconds`, and recorder callbacks.
- Produces: Figma-matched presentational variants with no recorder business logic.

- [x] Replace the inline waveform pill with the active layout: 56px Keyboard, elapsed time, 56px Pause, and 56px lime Send.
- [x] Replace the paused inline waveform pill with the paused layout: 56px Discard, 56px Resume pill with elapsed time, and 56px lime Send separated by 8px.
- [x] Keep the existing Recording and Paused Storybook fixtures as the visual verification surface.

### Task 3: Verify the integrated latest build

**Files:**
- Verify: `mobile/src/components/ui/VoiceComposer.tsx`
- Verify: `mobile/src/components/ui/__tests__/voiceComposerTransition.test.ts`

- [x] Run the focused transition assertion.
- [x] Run the voice-composer state tests, chat-card expansion tests, and mobile TypeScript check.
- [x] Run `npm run verify:design-system` and `git diff --check`.
- [x] Review the final diff for preservation of local-first, transcription, and card-expansion behavior.
- [ ] Restart Metro from `feature/chat-card-expansion` and reload the paired device.
