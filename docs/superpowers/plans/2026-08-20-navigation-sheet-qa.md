# Navigation and Sheet QA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct main-page header/date behavior, remove intermediate-page end-to-end navigation, optically center the selected capsule, and make all recording/input-destructive exits use native confirmation with viscous sheet motion.

**Architecture:** Keep the route-authoritative native scroll pager for adjacent gestures, but use a direct destination settlement for non-adjacent tab taps. Replace the frosted header with a fixed white title surface and visible gradient edge; the Chats list owns border-only sticky date badges below it. Centralize destructive recording/input confirmation behind a platform presenter using native `ActionSheetIOS`, while the chat screen owns resistant drag progress and post-confirmation dismissal sequencing.

**Tech Stack:** Expo SDK 54, React Native, Expo Router, Reanimated 4, React Native Gesture Handler, NativeWind, Jest.

**Spec:** Approved in the 2026-08-20 QA conversation.

## Global Constraints

- Preserve native Liquid Glass button and navbar materials.
- Preserve the navbar shell, capsule, icon, label, and hit-target sizes.
- No frosted page-header blur.
- Never discard a recording, voice draft, or active voice submission through a drag/cancel action without native confirmation.
- Conversation dismissal without destructive input remains available.
- Do not expose Home during a Chats-to-You or You-to-Chats tab tap.

---

### Task 1: Header and sticky date presentation

**Files:**
- Modify: `mobile/src/components/ui/PageHeaderSurface.tsx`
- Modify: `mobile/src/components/WorkspaceHeader.tsx`
- Modify: `mobile/app/(tabs)/chats.tsx`
- Modify: `mobile/app/(tabs)/index.tsx`
- Modify: `mobile/app/(tabs)/you.tsx`
- Test: `mobile/src/components/ui/__tests__/PageHeaderSurface.test.ts`
- Test: `mobile/src/navigation/__tests__/chatListSpacing.test.ts`

**Interfaces:**
- Produces: `PageHeaderSurface` as a non-frosted fixed white header with a visible bottom gradient.
- Produces: Chats sticky date badge with white fill, Neutral/200 border, and no full-width section background.

- [ ] Write failing source-contract tests for no `BlurView`, visible gradient, and border-only date badge.
- [ ] Run the focused tests and confirm the new assertions fail.
- [ ] Implement the header and date presentation without changing title typography or safe-area geometry.
- [ ] Run the focused tests and TypeScript.
- [ ] Commit `fix(ds): refine page header and sticky dates`.

### Task 2: Direct end-to-end navigation and optical capsule alignment

**Files:**
- Modify: `mobile/src/navigation/InteractiveMainNavigator.tsx`
- Modify: `mobile/src/navigation/MainNavigationInteractionContext.tsx`
- Modify: `mobile/src/components/ui/BottomNavBar.tsx`
- Test: `mobile/src/navigation/__tests__/InteractiveMainNavigator.test.tsx`
- Test: `mobile/src/navigation/__tests__/bottomNavigation.test.ts`

**Interfaces:**
- Produces: non-adjacent tab taps that directly settle the native scroll view at the destination without traversing the middle page.
- Produces: selected surface and selected content with the same 2-point downward optical offset.

- [ ] Write failing tests for direct non-adjacent settlement and shared optical offset.
- [ ] Run the focused tests and confirm failure.
- [ ] Implement the direct route path while preserving adjacent animated paging and swipe-driven capsule progress.
- [ ] Apply the optical offset without changing 60/48-point heights.
- [ ] Run focused navigation tests and TypeScript.
- [ ] Commit `fix: refine direct tab transitions`.

### Task 3: Native destructive recording/input confirmations

**Files:**
- Create: `mobile/src/services/destructiveInputConfirmation.ts`
- Modify: `mobile/app/chat/index.tsx`
- Remove: `mobile/src/components/ui/RecordingDiscardSheet.tsx`
- Remove: `mobile/src/components/ui/RecordingDiscardSheet.stories.tsx`
- Modify: `mobile/src/components/ui/index.ts`
- Modify: `docs/design-system.md`
- Test: `mobile/src/services/__tests__/destructiveInputConfirmation.test.ts`
- Test: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`

**Interfaces:**
- Produces: `confirmDestructiveInput(intent): Promise<boolean>` using native `ActionSheetIOS` on iOS and an alert fallback elsewhere.
- Consumes intents: cancel recording, switch to keyboard, delete voice draft, discard failed/active voice submission.

- [ ] Write failing tests for intent copy, cancel index, destructive index, and chat-screen ownership.
- [ ] Run focused tests and confirm failure.
- [ ] Implement the presenter and route every recording/input destructive action through it.
- [ ] Remove the custom discard modal and its catalog ownership.
- [ ] Run focused service/chat tests, TypeScript, and design-system verification.
- [ ] Commit `fix: use native destructive input confirmations`.

### Task 4: Viscous drag and confirmed dismissal sequencing

**Files:**
- Modify: `mobile/src/navigation/chatCardExpansion.ts`
- Modify: `mobile/app/chat/index.tsx`
- Test: `mobile/src/navigation/__tests__/chatCardExpansion.test.ts`
- Test: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`

**Interfaces:**
- Produces: `getResistedChatSheetTranslation(translationY)` at 0.55 resistance.
- Produces: slower close timing and damped spring constants.
- Consumes: `confirmDestructiveInput` before any drag-triggered destructive close.

- [ ] Write failing tests for resistance, slower dismissal timing, and destructive drag confirmation.
- [ ] Run focused tests and confirm failure.
- [ ] Implement resistant drag, settle-back-before-confirm, and confirm-then-close sequencing.
- [ ] Preserve immediate non-destructive conversation dismissal after threshold.
- [ ] Run focused gesture/chat tests and TypeScript.
- [ ] Commit `fix: add weight to chat sheet dismissal`.

### Task 5: Full verification and canonical preview publication

**Files:**
- Modify: `docs/design-system.md` only if implementation contracts changed.

- [ ] Run `npm test -- --runInBand` in `mobile/`.
- [ ] Run `npm run typecheck`, `npm run verify:design-system`, and `npm run verify:button-surfaces`.
- [ ] Run `git diff --check` and review the complete diff.
- [ ] Push `preview/taisa`, fetch, and confirm local and remote SHAs match.
- [ ] Reload the canonical Metro runtime and inspect device logs for native or worklet failures.
- [ ] Hand off the exact revision for Baah device QA.
