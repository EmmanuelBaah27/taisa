# Recording Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the approved Figma recording-start page for fresh voice capture without changing Taisa's local-first recorder or submission ownership.

**Architecture:** Add business-free DS primitives for the animated voice mark and active-recording layout, composed from the approved `SecondaryIconButton` and an extended 56px primary icon size on `Button`. `ChatScreen` conditionally selects this presentation only for an empty fresh voice recording/paused state and routes every control to existing handlers.

**Tech Stack:** React Native, Expo Router, NativeWind, React Native Animated, React Native SVG, Jest, Storybook, TypeScript.

**Spec:** `docs/features/recording-page.md`

## Global Constraints

- Preserve one recording owner in `mobile/app/chat/index.tsx`; `/recording` remains a redirect.
- Use DS primitives only for visual controls; add no `StyleSheet.create()`.
- Keep the exact Figma geometry: 56px actions, 24px icons, 16px page inset, centered title/greeting, and paired bottom control groups.
- Reproduce the supplied 2-second looping voice-mark motion and respect reduce motion.
- Do not introduce network, transcription, persistence, or coaching changes.

---

### Task 1: Extend primary icon sizing and build the voice mark

**Files:**
- Modify: `mobile/src/components/ui/Button.tsx`
- Modify: `mobile/src/components/ui/Button.stories.tsx`
- Create: `mobile/src/components/ui/RecordingVoiceMark.tsx`
- Create: `mobile/src/components/ui/RecordingVoiceMark.stories.tsx`
- Create: `mobile/src/components/ui/__tests__/RecordingPagePrimitives.test.ts`

**Interfaces:**
- Produces: `ButtonSize = 'icon-lg'`, `RecordingVoiceMark`, and exact recording-motion constants.

- [x] Write failing tests for the 56px primary icon action and 2-second voice-mark path/motion contract.
- [x] Run the focused test and confirm the missing contracts fail.
- [x] Implement the minimal DS primitives and Storybook states.
- [x] Re-run the focused test and confirm it passes.

### Task 2: Build the active recording surface

**Files:**
- Create: `mobile/src/components/ui/ActiveRecordingSurface.tsx`
- Create: `mobile/src/components/ui/ActiveRecordingSurface.stories.tsx`
- Modify: `mobile/src/components/ui/__tests__/RecordingPagePrimitives.test.ts`
- Modify: `mobile/src/components/ui/index.ts`
- Modify: `docs/design-system.md`

**Interfaces:**
- Consumes: `SecondaryIconButton`, `Button`, `RecordingVoiceMark`.
- Produces: `ActiveRecordingSurfaceProps` with safe-area insets, title, greeting, duration, paused/disabled state, and close/keyboard/pause/send callbacks.

- [x] Write a failing composition test for all four controls, timer formatting, and paused labeling.
- [x] Implement the Figma layout as a typed business-free component.
- [x] Add recording/paused stories, barrel exports, and DS documentation.
- [x] Run focused tests and design-system verification.

### Task 3: Select the recording presentation in ChatScreen

**Files:**
- Modify: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`
- Modify: `mobile/app/chat/index.tsx`
- Modify: `docs/workflow.md`

**Interfaces:**
- Consumes: existing recorder/composer state and handlers.
- Produces: Figma presentation only when the conversation is empty and voice capture is recording or paused.

- [x] Write a failing integration assertion that `ChatScreen` renders `ActiveRecordingSurface` and routes existing close, keyboard, pause/resume, and send handlers.
- [x] Add the narrow conditional presentation without changing recorder or submission functions.
- [x] Run focused navigation, state, component, and DS checks.
- [x] Run mobile type-check and confirm no changed-file diagnostic beyond the approved shared-types baseline.

## Verification evidence

- Focused component, navigation, voice-state, stop-session, and submission-lease tests: 48 passed, 0 failed.
- Design-system verification: passed with 25 catalog modules.
- Mobile type-check: approved `@taisa/shared` baseline failures remain; no recording-page changed-file diagnostic is present.
- Legacy route test confirms `/recording` remains a redirect with no direct `/entries` or `/analyze` calls.
