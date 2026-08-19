# Shared Chat and Recording Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make active and paused voice recording render as states of the canonical Taisa chat page so chat and recording share one header, title, margins, safe-area behavior, and footer geometry.

**Architecture:** Keep `ChatScreenShell` mounted for every chat state and let `app/chat/index.tsx` choose the shell’s content and footer. Split the existing standalone `ActiveRecordingSurface` into business-logic-free recording content and action-bar components, while preserving context-sensitive cancellation in the screen orchestrator.

**Tech Stack:** React Native 0.81, Expo SDK 54, Expo Router 6, NativeWind 4, TypeScript 5.9, Jest 29, React Native Reanimated 4, React Native Skia 2.

**Spec:** `docs/superpowers/specs/2026-08-19-shared-chat-recording-shell-design.md`

**Status:** Awaiting Baah plan approval

## Global Constraints

- The page title is `Taisa` in empty, recording, paused, and conversation states.
- The canonical `ChatScreenShell` remains mounted across recording state changes.
- Existing-chat Cancel discards recording and returns to Reply; standalone Cancel discards recording and closes the Taisa page.
- Close, Cancel, and Keyboard remain available during recorder acquisition; Pause/Resume and Send remain disabled.
- Keep the Taisa mark static and preserve the existing raw-amplitude timestamp glow.
- Preserve reverse card morph, reduced motion, recording cleanup, transcription, and persistence behavior.
- All circular action buttons remain exactly 56px.
- Use NativeWind and semantic theme tokens; add no dependencies, raw colors, or `StyleSheet.create()`.

---

### Task 1: Split recording presentation into content and footer units

**Files:**
- Modify: `mobile/src/components/ui/ActiveRecordingSurface.tsx`
- Modify: `mobile/src/components/ui/index.ts`
- Modify: `mobile/src/components/ui/ActiveRecordingSurface.stories.tsx`
- Modify: `mobile/src/components/ui/__tests__/RecordingPagePrimitives.test.ts`

**Interfaces:**
- Produces: `ActiveRecordingContentProps { greeting: string }` and `ActiveRecordingContent`.
- Produces: `ActiveRecordingActionBarProps` and `ActiveRecordingActionBar` with duration, amplitude, paused state, global/action disabled states, cancel label, bottom inset, and callbacks.
- Removes: page-shell responsibility from `ActiveRecordingSurface`; screen code will stop consuming the full-page component in Task 2.

- [ ] **Step 1: Write failing composition tests**

Add tests that call the new presentational functions directly and assert their boundaries:

```tsx
const content = ActiveRecordingContent({ greeting: 'How’s it going?' });
expect(findElementsByType(content.props.children, RecordingVoiceMark)).toHaveLength(1);
expect(textContent(content)).toContain('How’s it going?');

const bar = ActiveRecordingActionBar({
  bottomInset: 34,
  durationSeconds: 4,
  amplitudeLevel: 0.4,
  paused: false,
  disabled: false,
  recordingActionDisabled: true,
  cancelLabel: 'Cancel recording and close',
  onCancel: jest.fn(),
  onKeyboard: jest.fn(),
  onPauseResume: jest.fn(),
  onSend: jest.fn(),
});
expect(actionByLabel(bar, 'Cancel recording and close').props.disabled).toBe(false);
expect(actionByLabel(bar, 'Switch to keyboard').props.disabled).toBe(false);
expect(actionByLabel(bar, 'Pause recording').props.disabled).toBe(true);
expect(actionByLabel(bar, 'Send recording').props.disabled).toBe(true);
```

Assert that neither component accepts `topInset`, `title`, or `onClose`, and that the content still renders the static `RecordingVoiceMark` while the bar still renders `VoiceReactiveTimestamp`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd mobile
npm test -- --runInBand src/components/ui/__tests__/RecordingPagePrimitives.test.ts
```

Expected: FAIL because `ActiveRecordingContent` and `ActiveRecordingActionBar` are not exported.

- [ ] **Step 3: Implement the two focused components**

Replace the full-page component boundary with typed presentation units:

```tsx
export interface ActiveRecordingContentProps {
  greeting: string;
}

export function ActiveRecordingContent({ greeting }: ActiveRecordingContentProps) {
  return (
    <View className="flex-1 items-center justify-center gap-6">
      <RecordingVoiceMark />
      <Text className="font-sans text-center text-muted-foreground" style={GREETING_TEXT_STYLE}>
        {greeting}
      </Text>
    </View>
  );
}
```

Define `ActiveRecordingActionBarProps` with:

```ts
bottomInset: number;
durationSeconds: number;
amplitudeLevel: number;
paused: boolean;
disabled?: boolean;
recordingActionDisabled?: boolean;
cancelLabel: string;
onCancel(): void;
onKeyboard(): void;
onPauseResume(): void;
onSend(): void;
```

Render the existing control arrangement inside a footer-width container using the same `px-4` horizontal margin and `Math.max(bottomInset, 20) + 20` bottom spacing contract. Apply `recordingActionDisabled` only to Pause/Resume and Send.

- [ ] **Step 4: Update exports and Storybook**

Export both components and prop types from `mobile/src/components/ui/index.ts`. Replace the old full-page story with content and action-bar fixtures for Recording, Paused, and Acquiring states. Keep the 393px device-width decorator so visual comparison remains available.

- [ ] **Step 5: Run the focused test and verify GREEN**

Run the Task 1 test command. Expected: PASS, including the existing 56px, static mark, and timestamp glow assertions.

- [ ] **Step 6: Commit Task 1**

```bash
git add mobile/src/components/ui/ActiveRecordingSurface.tsx \
  mobile/src/components/ui/ActiveRecordingSurface.stories.tsx \
  mobile/src/components/ui/__tests__/RecordingPagePrimitives.test.ts \
  mobile/src/components/ui/index.ts
git commit -m "refactor(ds): split recording content and action bar"
```

---

### Task 2: Keep the canonical chat shell mounted during recording

**Files:**
- Modify: `mobile/app/chat/index.tsx`
- Modify: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`
- Modify: `mobile/src/components/ui/__tests__/ChatSurfaces.test.ts`

**Interfaces:**
- Consumes: `ActiveRecordingContent` and `ActiveRecordingActionBar` from Task 1.
- Preserves: `ChatScreenShellProps`, `ChatNavBar`, morph styles, recorder handlers, and cleanup ownership.
- Produces: one `ChatScreenShell` return path whose content/footer change by state.

- [ ] **Step 1: Write failing shell-unification tests**

Update source-contract tests to prove that recording no longer causes an early full-page return:

```ts
expect(chatScreen).not.toMatch(/if \(showActiveRecordingSurface\)[\s\S]*return \(/);
expect(chatScreen).toMatch(/<ChatScreenShell[\s\S]*title="Taisa"/);
expect(chatScreen).toMatch(/showActiveRecordingSurface[\s\S]*<ActiveRecordingContent/);
expect(chatScreen).toMatch(/showActiveRecordingSurface[\s\S]*<ActiveRecordingActionBar/);
expect(chatScreen).not.toMatch(/title="New chat"/);
```

Extend `ChatSurfaces.test.ts` to assert `ChatScreenShell` owns exactly one `ChatNavBar` and one footer slot independent of which nodes are supplied.

- [ ] **Step 2: Run the shell tests and verify RED**

Run:

```bash
cd mobile
npm test -- --runInBand \
  src/navigation/__tests__/localCaptureRoutes.test.ts \
  src/components/ui/__tests__/ChatSurfaces.test.ts
```

Expected: FAIL because the current screen returns `ActiveRecordingSurface` before `ChatScreenShell`.

- [ ] **Step 3: Build content and footer variables in the screen**

Replace the early return with explicit rendered-state variables:

```tsx
const chatContent = showActiveRecordingSurface ? (
  <ActiveRecordingContent greeting="How’s it going?" />
) : (
  <ChatConversationSurface {...conversationProps} />
);

const chatFooter = showActiveRecordingSurface ? (
  <ActiveRecordingActionBar {...recordingBarProps} />
) : (
  <ChatComposerDock phase={phase} bottomInset={insets.bottom}>
    <VoiceComposer {...composerProps} />
  </ChatComposerDock>
);
```

Render one shell:

```tsx
return (
  <ChatScreenShell
    topInset={insets.top}
    title="Taisa"
    animatedStyle={slideStyle}
    contentAnimatedStyle={contentStyle}
    onClose={handleClose}
    footer={chatFooter}
  >
    {chatContent}
  </ChatScreenShell>
);
```

Do not change `slideStyle`, `contentStyle`, `close`, `revealContent`, or recorder ownership.

- [ ] **Step 4: Preserve initial content reveal behavior**

When recording content is shown without hydrated conversation messages, ensure the existing morph content layer becomes visible without waiting for `ChatConversationSurface.onContentSizeChange`. Use the existing `revealContent()` entry point in a narrowly scoped effect keyed to `showActiveRecordingSurface`:

```tsx
useEffect(() => {
  if (showActiveRecordingSurface) requestAnimationFrame(revealContent);
}, [showActiveRecordingSurface, revealContent]);
```

If `revealContent` is not referentially stable, key only on the boolean and document the intentional hook suppression rather than changing morph behavior.

- [ ] **Step 5: Run the shell tests and verify GREEN**

Run the Task 2 test command. Expected: PASS with a single shell contract and title `Taisa`.

- [ ] **Step 6: Commit Task 2**

```bash
git add mobile/app/chat/index.tsx \
  mobile/src/navigation/__tests__/localCaptureRoutes.test.ts \
  mobile/src/components/ui/__tests__/ChatSurfaces.test.ts
git commit -m "refactor: render recording inside chat shell"
```

---

### Task 3: Preserve the two cancellation destinations

**Files:**
- Modify: `mobile/app/chat/index.tsx`
- Modify: `mobile/src/navigation/chatConversationRoute.ts`
- Modify: `mobile/src/navigation/__tests__/conversationResume.test.ts`
- Modify: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`

**Interfaces:**
- Consumes: `initialConversationIdRef.current` and the existing `voiceCancelDestination` context decision.
- Produces: `voiceCancelAccessibilityLabel(initialConversationId: string | null): string`.
- Preserves: `handleCancelVoice`, `stopActiveRecordingAndDiscard`, `discardPendingRecording`, and `handleClose` cleanup behavior.

- [ ] **Step 1: Write failing pure behavior tests**

Add assertions beside `voiceCancelDestination`:

```ts
expect(voiceCancelDestination('conversation-1')).toBe('reply');
expect(voiceCancelDestination(null)).toBe('close');
expect(voiceCancelAccessibilityLabel('conversation-1'))
  .toBe('Cancel recording and return to chat');
expect(voiceCancelAccessibilityLabel(null))
  .toBe('Cancel recording and close');
```

Update the screen source test to prove the label is passed into `ActiveRecordingActionBar` and `handleCancelVoice` still branches through `voiceCancelDestination`.

- [ ] **Step 2: Run cancellation tests and verify RED**

Run:

```bash
cd mobile
npm test -- --runInBand \
  src/navigation/__tests__/conversationResume.test.ts \
  src/navigation/__tests__/localCaptureRoutes.test.ts
```

Expected: FAIL because `voiceCancelAccessibilityLabel` does not exist.

- [ ] **Step 3: Implement the pure label helper**

Add beside the existing destination function:

```ts
export function voiceCancelAccessibilityLabel(initialConversationId: string | null): string {
  return voiceCancelDestination(initialConversationId) === 'reply'
    ? 'Cancel recording and return to chat'
    : 'Cancel recording and close';
}
```

Pass the result to the recording action bar:

```tsx
cancelLabel={voiceCancelAccessibilityLabel(initialConversationIdRef.current)}
```

Do not move navigation or cleanup logic into the design-system component.

- [ ] **Step 4: Verify failed-start behavior in both contexts**

Extend source-contract assertions so the `startListening` catch still calls `handleCancelVoice`, then prove `handleCancelVoice` closes only for the `close` destination and otherwise restores voice mode:

```ts
expect(chatScreen).toMatch(/catch \{[\s\S]*await handleCancelVoice\(\)/);
expect(chatScreen).toMatch(/voiceCancelDestination\([^)]+\) === 'close'[\s\S]*handleClose\(\)/);
expect(chatScreen).toMatch(/setPhase\('idle'\)[\s\S]*restore-mode/);
```

- [ ] **Step 5: Run cancellation tests and verify GREEN**

Run the Task 3 test command. Expected: PASS for both destination and accessibility contracts.

- [ ] **Step 6: Commit Task 3**

```bash
git add mobile/app/chat/index.tsx \
  mobile/src/navigation/chatConversationRoute.ts \
  mobile/src/navigation/__tests__/conversationResume.test.ts \
  mobile/src/navigation/__tests__/localCaptureRoutes.test.ts
git commit -m "fix: preserve contextual recording cancellation"
```

---

### Task 4: Document and verify the unified page

**Files:**
- Modify: `docs/design-system.md`
- Modify: `docs/superpowers/specs/2026-08-19-shared-chat-recording-shell-design.md`
- Modify: `docs/superpowers/plans/2026-08-19-shared-chat-recording-shell.md`
- Verify: all files changed in Tasks 1–3

**Interfaces:**
- Documents: `ActiveRecordingContent`, `ActiveRecordingActionBar`, and their use inside `ChatScreenShell`.
- Produces: Review + QA handoff with automated evidence and a device checklist.

- [ ] **Step 1: Update design-system documentation**

Document that:

- `ChatScreenShell` is the only page-level shell for chat and recording states;
- `ActiveRecordingContent` owns the static center content;
- `ActiveRecordingActionBar` owns only recording controls and geometry;
- navigation and cancel destinations remain screen responsibilities;
- recording action buttons are 56px and acquisition disables only Pause/Resume and Send.

- [ ] **Step 2: Run the complete mobile verification matrix**

Run:

```bash
cd mobile
npm test -- --runInBand
npm run typecheck
npm run verify:design-system
git diff --check
```

Expected: all Jest suites pass, TypeScript exits 0, design-system verification passes, and `git diff --check` produces no output.

- [ ] **Step 3: Review the final diff against the spec**

Confirm explicitly:

- no early standalone recording-page return remains;
- every state displays the title `Taisa` through `ChatNavBar`;
- shared page/header/footer geometry has one implementation;
- the Taisa mark is static;
- timestamp glow values and worklet-crash correction are unchanged;
- Close/Cancel/Keyboard stay enabled during acquisition;
- Pause/Resume and Send stay disabled during acquisition;
- existing-chat and standalone Cancel take different destinations;
- reverse morph, reduced motion, transcription, and persistence code are unchanged.

- [ ] **Step 4: Update status for device QA**

Set the spec and plan status to `Review + QA — awaiting Baah device verification`. Record the automated command results. Do not mark Shipped.

- [ ] **Step 5: Commit documentation and evidence**

```bash
git add docs/design-system.md \
  docs/superpowers/specs/2026-08-19-shared-chat-recording-shell-design.md \
  docs/superpowers/plans/2026-08-19-shared-chat-recording-shell.md
git commit -m "docs: record shared chat recording shell QA"
```

- [ ] **Step 6: Reload the paired device and run visual QA**

Verify on the paired iPhone:

1. Open a historical chat and confirm title/header/margins.
2. Start recording and confirm the header does not jump or remount.
3. Compare footer margins, button size, and bottom spacing with Reply.
4. Pause and resume; confirm only content/footer state changes.
5. Cancel from the historical chat; confirm it returns to Reply.
6. Start main/new voice recording; confirm the title is `Taisa`.
7. Cancel main/new recording; confirm the Taisa page closes.
8. Deny or interrupt recorder acquisition; confirm Cancel and Keyboard remain usable while Pause/Send stay disabled.

Expected: Baah confirms the two states read as one page and both Cancel destinations are correct before Ship approval.
