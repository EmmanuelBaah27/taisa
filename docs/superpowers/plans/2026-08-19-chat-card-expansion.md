# Chat Card Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand a selected Chats row into the Figma conversation view, then reverse that morph into the same stable card when the historical chat closes.

**Architecture:** A pure transition module validates the measured list-row frame, list scroll offset, and source viewport. `ChatListRow` measures itself before navigation and the Chats screen passes that source snapshot through route parameters; the canonical chat route uses it for paired entry and exit transforms. The Chats screen restores the captured offset before refreshing, while existing chat data and recorder ownership remain in `app/chat/index.tsx` and design-system surfaces own the Figma presentation.

**Tech Stack:** Expo SDK 54, Expo Router 6, React Native 0.81, TypeScript 5.9, NativeWind 4, React Native Reanimated 4, Jest 29.

**Spec:** `docs/features/chat-card-expansion.md`

**Status:** Ship approved — pending merge

## Global Constraints

- Work only on `feature/chat-card-expansion`, based on verified `feature/current-experience` head `c281533`.
- Reuse semantic design tokens and existing UI primitives; do not add dependencies or raw hex values.
- Keep conversation, recording, and persistence behavior unchanged.
- Opening expands from the selected Chats row; closing returns to the same captured row frame before route dismissal.
- Preserve the captured Chats-list scroll offset until the reverse morph and route dismissal finish.
- Reduced motion disables both entry and exit animation.
- Do not add `StyleSheet.create()` to changed UI files.

---

### Task 1: Transition geometry contract

**Files:**
- Create: `mobile/src/navigation/chatCardExpansion.ts`
- Create: `mobile/src/navigation/__tests__/chatCardExpansion.test.ts`

**Interfaces:**
- Produces: `ChatCardFrame`, `parseChatCardFrame(params)`, and `getChatCardInitialTransform(frame, viewport)`.

- [ ] **Step 1: Write failing tests** proving valid numeric route values are parsed, malformed or non-positive frames return `null`, and a 361×72 card at `(16, 140)` in a 393×852 viewport yields the hand-calculated scale and center-offset transform.
- [ ] **Step 2: Run** `cd mobile && npm test -- --runInBand src/navigation/__tests__/chatCardExpansion.test.ts`; expect failure because the module is missing.
- [ ] **Step 3: Implement** the typed parser and pure transform calculation, clamping scales to `(0, 1]` and returning `null` when no usable frame exists.
- [ ] **Step 4: Re-run the focused test** and expect PASS.

### Task 2: Measure the selected Chats row and route to canonical chat

**Files:**
- Modify: `mobile/src/components/ui/ChatListRow.tsx`
- Modify: `mobile/app/(tabs)/logs.tsx`
- Modify: `mobile/src/navigation/chatConversationRoute.ts`
- Modify: `mobile/src/navigation/__tests__/conversationResume.test.ts`
- Modify: `mobile/src/components/ui/__tests__/ChatHistoryPrimitives.test.ts`

**Interfaces:**
- Consumes: `ChatCardFrame`.
- Produces: `ChatListRow.onOpen(frame)` and `chatConversationRoute(conversationId, frame)` route parameters.

- [ ] **Step 1: Write failing tests** proving the conversation route includes the measured frame and Chats rows expose a measured-open callback without using the legacy thread route.
- [ ] **Step 2: Run the two focused test files** and verify they fail for the missing contract.
- [ ] **Step 3: Add a row ref and `measureInWindow` press handler**, falling back to an unmeasured open if native measurement is unavailable.
- [ ] **Step 4: Route Chats items through `/chat`** with the conversation ID and serialized frame.
- [ ] **Step 5: Re-run the focused tests** and expect PASS.

### Task 3: Figma conversation shell and expansion

**Files:**
- Modify: `mobile/src/components/ui/ChatNavBar.tsx`
- Modify: `mobile/src/components/ui/ChatSurfaces.tsx`
- Modify: `mobile/src/components/ui/__tests__/ChatSurfaces.test.ts`
- Modify: `mobile/app/chat/index.tsx`
- Modify: `mobile/src/hooks/useMorphTransition.ts`
- Modify: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`
- Modify: `mobile/app/_layout.tsx`
- Modify: `docs/design-system.md`

**Interfaces:**
- Consumes: parsed `ChatCardFrame`, viewport size, reduced-motion preference, and current conversation title.
- Produces: Figma-aligned `ChatScreenShell` with an optional source transform and safe close handling.

- [ ] **Step 1: Write failing tests** for a title-bearing floating header, neutral 32px user bubble, unboxed assistant content, entry-only animation, no drag-to-dismiss, and no recording stack slide transition.
- [ ] **Step 2: Run focused Chat surfaces and navigation tests** and confirm the expected failures.
- [ ] **Step 3: Update the design-system surfaces** to match the Figma header, conversation spacing, gradients, and reply dock while keeping state and business logic outside UI components.
- [ ] **Step 4: Replace the screen-height morph hook** with entry-only interpolation from the parsed card transform; bypass it for reduced motion or missing geometry.
- [ ] **Step 5: Make close immediate**, remove drag-to-dismiss coordination and delayed route closing, and remove the recording route’s `slide_from_bottom` override.
- [ ] **Step 6: Re-run focused tests,** then run `cd mobile && npm run typecheck && npm run verify:design-system`.

### Task 4: Review and verification

**Files:**
- Modify: `docs/workflow.md`
- Modify: `docs/superpowers/plans/2026-08-19-chat-card-expansion.md`

- [ ] **Step 1: Run** `cd mobile && npm test -- --runInBand`.
- [ ] **Step 2: Run** `cd mobile && npm run typecheck && npm run verify:design-system`.
- [ ] **Step 3: Run** `git diff --check` and review the changed files for DS compliance, recorder cleanup preservation, and unrelated changes.
- [ ] **Step 4: Mark the plan Review + QA** and report the exact device checks: card-origin expansion, immediate close from idle chat, immediate close while recording, keyboard avoidance, reduced motion, and conversation resume.

### Task 5: Reverse morph QA revision

**Files:**
- Modify: `mobile/src/navigation/chatCardExpansion.ts`
- Modify: `mobile/src/navigation/chatConversationRoute.ts`
- Modify: `mobile/app/(tabs)/logs.tsx`
- Modify: `mobile/src/hooks/useMorphTransition.ts`
- Modify: `mobile/app/chat/index.tsx`
- Modify: focused navigation tests and `docs/design-system.md`

- [x] Capture and validate the source list scroll offset with the card frame.
- [x] Preserve and restore the Chats scroll offset before its post-close refresh.
- [x] Animate the chat surface back to the source transform and pop only after completion.
- [x] Keep deep-link, fresh-capture, invalid-geometry, and reduced-motion exits immediate.
- [x] Re-run full mobile and workflow verification before returning to device QA.

### Task 6: White-shell content reveal QA revision

- [x] Keep the shell transform separate from header, messages, and composer content.
- [x] Stagger the content reveal until the white shell is nearly full-screen.
- [x] Hide content as closing begins, before it can appear compressed.
- [x] Position the initial historical conversation at the bottom without animation while content is hidden.
- [x] Re-run full mobile and workflow verification before returning to device QA.
