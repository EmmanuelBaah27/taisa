# Voice Button Morph Transition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Animation tasks:** Invoke the `motion` skill before writing any Reanimated code. It encodes the animation principles used in this project.

**Goal:** Replace the `slide_from_bottom` chat modal with a continuity morph transition — the lime VoiceButton pill visually expands into the chat screen on open and springs back to pill shape on close.

**Architecture:** The chat screen becomes a `transparentModal` that owns its own enter/exit animation via Reanimated 4. A new `MorphSurface` white `Animated.View` interpolates between pill dimensions (112×56, borderRadius 48) and full screen dimensions on a `progress` shared value. A `useMorphTransition` hook owns `progress` and `contentOpacity`, exposing `open()` and `close(onDone)`. The VoiceButton hides itself during the morph via a `chatMorphing` flag in `uiStore`.

**Tech Stack:** React Native Reanimated 4.1.1 (`useSharedValue`, `useAnimatedStyle`, `withSpring`, `withTiming`, `withDelay`, `runOnJS`, `interpolate`), Expo Router `transparentModal`, Zustand (`useUIStore`), `useSafeAreaInsets`, `useWindowDimensions`.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `mobile/src/hooks/useMorphTransition.ts` | Shared values + open/close animation sequencing |
| Create | `mobile/src/components/ui/MorphSurface.tsx` | White expanding surface, driven by progress prop |
| Modify | `mobile/src/stores/uiStore.ts` | Add `chatMorphing: boolean` + `setChatMorphing` |
| Modify | `mobile/src/components/ui/index.ts` | Export `MorphSurface` |
| Modify | `mobile/app/_layout.tsx` | Change chat/index to `transparentModal + animation: 'none'` |
| Modify | `mobile/src/components/VoiceButton.tsx` | Set `chatMorphing = true` on press; hide when morphing |
| Modify | `mobile/app/chat/index.tsx` | Transparent root, integrate morph, replace handleClose |

---

## Task 1: Add `chatMorphing` to uiStore

**Files:**
- Modify: `mobile/src/stores/uiStore.ts`

- [ ] **Open `mobile/src/stores/uiStore.ts`.** The file currently has `recordingPhase`, `isProcessing`, and `resetJournalFlow`. You will add `chatMorphing` alongside these.

- [ ] **Replace the entire file contents with:**

```typescript
import { create } from 'zustand';

type RecordingPhase = 'idle' | 'recording' | 'reviewing' | 'processing' | 'complete';

interface UIStore {
  recordingPhase: RecordingPhase;
  isProcessing: boolean;
  chatMorphing: boolean;

  setRecordingPhase: (phase: RecordingPhase) => void;
  setProcessing: (v: boolean) => void;
  setChatMorphing: (v: boolean) => void;
  resetJournalFlow: () => void;
}

export const useUIStore = create<UIStore>((set) => ({
  recordingPhase: 'idle',
  isProcessing: false,
  chatMorphing: false,

  setRecordingPhase: (phase) => set({ recordingPhase: phase }),
  setProcessing: (v) => set({ isProcessing: v }),
  setChatMorphing: (v) => set({ chatMorphing: v }),
  resetJournalFlow: () => set({ recordingPhase: 'idle', isProcessing: false }),
}));
```

- [ ] **Verify TypeScript compiles.** From `mobile/`:

```bash
npx tsc --noEmit
```

Expected: no errors related to `uiStore`.

- [ ] **Commit:**

```bash
git add mobile/src/stores/uiStore.ts
git commit -m "feat(uiStore): add chatMorphing flag for morph transition"
```

---

## Task 2: Create `useMorphTransition` hook

**Files:**
- Create: `mobile/src/hooks/useMorphTransition.ts`

- [ ] **Invoke the `motion` skill** before writing this code. It grounds animation decisions in the principles used in this project.

- [ ] **Create `mobile/src/hooks/useMorphTransition.ts`** with this exact content:

```typescript
import {
  useSharedValue,
  withSpring,
  withTiming,
  withDelay,
  runOnJS,
  SharedValue,
} from 'react-native-reanimated';

const SPRING_OPEN = { damping: 28, stiffness: 260 };
const SPRING_CLOSE = { damping: 32, stiffness: 300 };

export interface MorphTransition {
  progress: SharedValue<number>;
  contentOpacity: SharedValue<number>;
  open: () => void;
  close: (onDone: () => void) => void;
}

export function useMorphTransition(): MorphTransition {
  const progress = useSharedValue(0);
  const contentOpacity = useSharedValue(0);

  function open() {
    progress.value = withSpring(1, SPRING_OPEN);
    contentOpacity.value = withDelay(60, withTiming(1, { duration: 180 }));
  }

  function close(onDone: () => void) {
    contentOpacity.value = withTiming(0, { duration: 140 }, () => {
      progress.value = withSpring(0, SPRING_CLOSE, () => {
        runOnJS(onDone)();
      });
    });
  }

  return { progress, contentOpacity, open, close };
}
```

- [ ] **Verify TypeScript compiles:**

```bash
npx tsc --noEmit
```

Expected: no errors in `useMorphTransition.ts`.

- [ ] **Commit:**

```bash
git add mobile/src/hooks/useMorphTransition.ts
git commit -m "feat: add useMorphTransition hook for pill expand animation"
```

---

## Task 3: Create `MorphSurface` component

**Files:**
- Create: `mobile/src/components/ui/MorphSurface.tsx`

The `MorphSurface` is a white `Animated.View` that sits behind the chat content. It starts at the VoiceButton pill's exact dimensions and position, then interpolates to full screen as `progress` goes from 0 to 1. The constants below are derived from `VoiceButton.tsx` — if the button's padding or icon size ever changes, update them here too.

- [ ] **Create `mobile/src/components/ui/MorphSurface.tsx`:**

```typescript
import Animated, {
  useAnimatedStyle,
  interpolate,
  SharedValue,
} from 'react-native-reanimated';
import { useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

// Must match VoiceButton.tsx exactly:
//   paddingHorizontal: 44 (×2 = 88) + icon width 24 = 112
//   paddingVertical: 16 (×2 = 32) + icon height 24 = 56
//   borderRadius: 48
//   bottom: insets.bottom + 16
const PILL_W = 112;
const PILL_H = 56;
const PILL_RADIUS = 48;

interface MorphSurfaceProps {
  progress: SharedValue<number>;
}

export function MorphSurface({ progress }: MorphSurfaceProps) {
  const insets = useSafeAreaInsets();
  const { width: screenW, height: screenH } = useWindowDimensions();

  const style = useAnimatedStyle(() => ({
    position: 'absolute',
    backgroundColor: '#ffffff',
    width: interpolate(progress.value, [0, 1], [PILL_W, screenW]),
    height: interpolate(progress.value, [0, 1], [PILL_H, screenH]),
    borderRadius: interpolate(progress.value, [0, 1], [PILL_RADIUS, 0]),
    bottom: interpolate(progress.value, [0, 1], [insets.bottom + 16, 0]),
    left: interpolate(progress.value, [0, 1], [(screenW - PILL_W) / 2, 0]),
  }));

  return <Animated.View style={style} />;
}
```

- [ ] **Export from the barrel. Open `mobile/src/components/ui/index.ts` and add at the end:**

```typescript
export { MorphSurface } from './MorphSurface';
export type { } from './MorphSurface';
```

(The type export is a no-op here since `MorphSurfaceProps` uses an internal `SharedValue` — keep it for consistency with the barrel pattern.)

- [ ] **Verify TypeScript compiles:**

```bash
npx tsc --noEmit
```

Expected: no errors in `MorphSurface.tsx`.

- [ ] **Commit:**

```bash
git add mobile/src/components/ui/MorphSurface.tsx mobile/src/components/ui/index.ts
git commit -m "feat: add MorphSurface component for pill expand transition"
```

---

## Task 4: Update navigation — chat becomes `transparentModal`

**Files:**
- Modify: `mobile/app/_layout.tsx`

The system `slide_from_bottom` animation is replaced entirely. Setting `animation: 'none'` and `presentation: 'transparentModal'` lets the chat screen own its own enter/exit — the tab layout stays visible underneath until the MorphSurface covers it.

- [ ] **Open `mobile/app/_layout.tsx`. Find the `chat/index` Stack.Screen entry:**

```tsx
<Stack.Screen
  name="chat/index"
  options={{ presentation: 'fullScreenModal', animation: 'slide_from_bottom' }}
/>
```

- [ ] **Replace it with:**

```tsx
<Stack.Screen
  name="chat/index"
  options={{ presentation: 'transparentModal', animation: 'none' }}
/>
```

- [ ] **Verify TypeScript compiles:**

```bash
npx tsc --noEmit
```

- [ ] **Commit:**

```bash
git add mobile/app/_layout.tsx
git commit -m "feat: set chat/index to transparentModal for morph transition"
```

---

## Task 5: Update `VoiceButton` — hide during morph, set flag on press

**Files:**
- Modify: `mobile/src/components/VoiceButton.tsx`

Two changes: (1) read `chatMorphing` from `uiStore` and apply `opacity: 0` on the outer view when true — this hides the lime pill while the white MorphSurface is in flight. (2) call `setChatMorphing(true)` before `router.push` so the lime pill disappears at the same moment the white surface appears on top of it.

- [ ] **Open `mobile/src/components/VoiceButton.tsx`. Replace the entire file:**

```typescript
import { Pressable } from 'react-native';
import { router } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSpring,
} from 'react-native-reanimated';
import { Icon } from './ui/Icon';
import { colors } from '../constants/theme';
import { useUIStore } from '../stores/uiStore';

interface VoiceButtonProps {
  onPress?: () => void;
}

export function VoiceButton({ onPress }: VoiceButtonProps) {
  const insets = useSafeAreaInsets();
  const { chatMorphing, setChatMorphing } = useUIStore();

  const handlePress = onPress ?? (() => {
    setChatMorphing(true);
    router.push('/chat');
  });

  const scale = useSharedValue(1);

  const animStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Animated.View
      style={[
        {
          position: 'absolute',
          bottom: insets.bottom + 16,
          left: 0,
          right: 0,
          alignItems: 'center',
          zIndex: 50,
          opacity: chatMorphing ? 0 : 1,
        },
        animStyle,
      ]}
    >
      <Pressable
        onPress={handlePress}
        onPressIn={() => { scale.value = withTiming(0.95, { duration: 80 }); }}
        onPressOut={() => { scale.value = withSpring(1, { damping: 20, stiffness: 300 }); }}
        style={{
          backgroundColor: '#cdec1a',
          paddingVertical: 16,
          paddingHorizontal: 44,
          borderRadius: 48,
          shadowColor: colors.accent,
          shadowOffset: { width: 0, height: 0 },
          shadowOpacity: 0.6,
          shadowRadius: 24,
          elevation: 10,
        }}
      >
        <Icon name="IconVoiceMid" size={24} color="#060707" />
      </Pressable>
    </Animated.View>
  );
}
```

- [ ] **Verify TypeScript compiles:**

```bash
npx tsc --noEmit
```

- [ ] **Commit:**

```bash
git add mobile/src/components/VoiceButton.tsx
git commit -m "feat(VoiceButton): hide during morph, set chatMorphing on press"
```

---

## Task 6: Update `chat/index.tsx` — transparent root, morph integration

**Files:**
- Modify: `mobile/app/chat/index.tsx`

Three structural changes: (1) root `View` becomes transparent — `MorphSurface` provides the white background. (2) All existing chat UI is wrapped in a Reanimated `Animated.View` driven by `contentOpacity`. (3) `handleClose` calls `close(onDone)` instead of `router.back()` directly, so the reverse morph plays before navigation.

- [ ] **Open `mobile/app/chat/index.tsx`. Replace the import block at the top with:**

```typescript
import { useEffect, useRef, useState } from 'react';
import {
  View,
  ScrollView,
  Text,
  TouchableOpacity,
} from 'react-native';
import { router } from 'expo-router';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, { useAnimatedStyle } from 'react-native-reanimated';
import { useLiveTranscription } from '../../src/hooks/useLiveTranscription';
import { useMorphTransition } from '../../src/hooks/useMorphTransition';
import { useChatStore } from '../../src/stores/chatStore';
import { useUIStore } from '../../src/stores/uiStore';
import {
  ChatNavBar,
  MorphSurface,
  RecordingGlow,
  LiveTranscriptionText,
  TaisaReplyCard,
  Icon,
} from '../../src/components/ui';
import api from '../../src/services/api';
import type { ChatMessage } from '../../src/stores/threadStore';
```

- [ ] **Inside `ChatScreen`, add the morph hook and content style immediately after the existing hooks — after the `useSafeAreaInsets` and `useChatStore` lines:**

```typescript
const { setChatMorphing } = useUIStore();
const { progress, contentOpacity, open, close } = useMorphTransition();

const contentStyle = useAnimatedStyle(() => ({
  opacity: contentOpacity.value,
}));
```

- [ ] **Find the mount `useEffect` (the one that calls `loadSession` or `startListening`). Add `open()` as the very first line inside it:**

```typescript
useEffect(() => {
  open();
  if (activeSessionId) {
    loadSession(activeSessionId);
  } else {
    startListening();
  }
  return () => {
    clearTimeout(silenceTimerRef.current);
    clearTimeout(restartTimerRef.current);
  };
}, []);
```

- [ ] **Replace the existing `handleClose` function with:**

```typescript
function handleClose() {
  clearTimeout(silenceTimerRef.current);
  clearTimeout(restartTimerRef.current);
  stop().catch(() => {});
  close(() => {
    setChatMorphing(false);
    router.back();
  });
}
```

- [ ] **Replace the entire `return` block with:**

```tsx
const BACKGROUND_HEX = '#ffffff';
const BACKGROUND_TRANSPARENT = 'rgba(255,255,255,0)';

// (keep BACKGROUND_HEX and BACKGROUND_TRANSPARENT at the top of the file —
//  move them there if they aren't already)

return (
  <View style={{ flex: 1, backgroundColor: 'transparent' }}>
    <MorphSurface progress={progress} />

    <Animated.View style={[{ flex: 1 }, contentStyle]}>
      <ChatNavBar onClose={handleClose} />

      {/* Conversation scroll */}
      <View className="flex-1">
        <ScrollView
          ref={scrollRef}
          className="flex-1"
          contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 24 }}
          showsVerticalScrollIndicator={false}
        >
          {messages.map(msg =>
            msg.role === 'assistant' ? (
              <TaisaReplyCard key={msg.id} content={msg.content} />
            ) : (
              <View
                key={msg.id}
                className="self-end mb-3 bg-lime-100 rounded-3 px-4 py-3 max-w-xs"
              >
                <Text className="text-foreground text-base-regular">{msg.content}</Text>
              </View>
            )
          )}

          {phase === 'processing' && (
            <View className="items-start mb-3">
              <View className="bg-subtle rounded-3 px-4 py-3">
                <Text className="text-text-tertiary text-small-regular">Taisa is thinking…</Text>
              </View>
            </View>
          )}

          {phase === 'error' && (
            <View className="items-center py-4">
              <Text className="text-danger text-small-regular mb-3 text-center">{error}</Text>
              <TouchableOpacity
                onPress={handleRetry}
                className="bg-muted rounded-full px-6 py-3"
              >
                <Text className="text-foreground text-small-semibold">Try again</Text>
              </TouchableOpacity>
            </View>
          )}
        </ScrollView>

        <LinearGradient
          colors={[BACKGROUND_TRANSPARENT, BACKGROUND_HEX]}
          style={{
            position: 'absolute',
            bottom: 0,
            left: 0,
            right: 0,
            height: 48,
            pointerEvents: 'none',
          }}
        />
      </View>

      {isInputActive && (
        <View style={{ height: 200 }}>
          <LiveTranscriptionText transcript={transcript} />
          <View
            className="flex-row items-center justify-between px-5"
            style={{ paddingBottom: insets.bottom + 12 }}
          >
            <View className="w-10 h-10 rounded-full border border-border items-center justify-center opacity-40">
              <Icon name="IconKeyboard" size={20} color="#898989" />
            </View>
            <TouchableOpacity
              onPress={handleStop}
              disabled={!transcript.trim()}
              className="flex-row items-center gap-2 bg-background border border-border rounded-full px-4 py-2"
              style={{ opacity: transcript.trim() ? 1 : 0.4 }}
            >
              <Icon name="IconStopCircle" size={18} color="#060707" />
              <Text className="text-foreground text-small-semibold">Stop</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      <RecordingGlow amplitude={phase === 'listening' ? amplitude : 0} />
    </Animated.View>
  </View>
);
```

- [ ] **Move the two `const` declarations to the top of the file (above the `ChatScreen` function) if not already there:**

```typescript
const BACKGROUND_HEX = '#ffffff';
const BACKGROUND_TRANSPARENT = 'rgba(255,255,255,0)';
```

- [ ] **Verify TypeScript compiles:**

```bash
npx tsc --noEmit
```

Expected: no errors.

- [ ] **Commit:**

```bash
git add mobile/app/chat/index.tsx
git commit -m "feat(chat): integrate morph transition — transparent root, MorphSurface, close animation"
```

---

## Task 7: Manual smoke test

No automated tests exist for the mobile UI. Verify the morph in the running app.

- [ ] **Start the app:**

```bash
# From repo root
npm run mobile
```

- [ ] **Test opening.** Tap the lime VoiceButton. Expected:
  - Lime pill disappears instantly (covered by white surface)
  - White surface expands from pill position upward and outward to fill the screen
  - Chat content (nav bar, input zone) fades in once the surface settles
  - No flash of the slide_from_bottom animation
  - No ghost lime pill visible at any point during expansion

- [ ] **Test closing.** Tap the caret-down in the ChatNavBar. Expected:
  - Chat content (nav bar, messages, input) fades out
  - White surface springs back to the pill position at the bottom of the screen
  - Screen unmounts; lime VoiceButton reappears in place of the white pill
  - No jump or flash

- [ ] **Test on a device with a large safe area** (e.g. iPhone with Dynamic Island / notch). Expected:
  - Pill position matches VoiceButton position exactly on first render
  - Full-screen surface reaches screen edges (bottom = 0, rounded corners absent)

- [ ] **Commit if any tweaks were made** to spring values or timing during testing:

```bash
git add -p
git commit -m "chore: tune morph spring values after device testing"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task that covers it |
|---|---|
| White expanding surface, not lime | Task 3 — `backgroundColor: '#ffffff'` in `MorphSurface` |
| Pill Expand morph (width/height/borderRadius all animate) | Task 3 — all 5 layout props interpolated |
| Opening: white pill covers lime instantly | Task 3 — MorphSurface renders at progress=0 before `open()` fires |
| `open()` called on mount | Task 6 — first line of mount `useEffect` |
| Reverse morph on close | Task 2 — `close(onDone)` chain; Task 6 — `handleClose` |
| `chatMorphing` hides VoiceButton | Task 1 + Task 5 |
| `setChatMorphing(true)` on press | Task 5 |
| `setChatMorphing(false)` before `router.back()` | Task 6 — inside `close` callback |
| `transparentModal + animation: 'none'` | Task 4 |
| Spring config: damping 28/stiffness 260 open, 32/300 close | Task 2 |
| Content fade: delay 60ms, 180ms in, 140ms out | Task 2 |
| No new libraries | All tasks — only Reanimated (already installed) |

**Placeholder scan:** All steps contain complete code. No TBDs. ✓

**Type consistency:** `MorphTransition` interface defined in Task 2 and used in Task 6 via destructuring — no mismatch. `SharedValue<number>` used consistently in Task 2 and Task 3. `setChatMorphing` defined in Task 1, used in Tasks 5 and 6. ✓
