# Voice Button → Chat Morph Transition

**Date:** 2026-05-24
**Status:** Approved — ready for implementation

---

## Problem

The current transition from the VoiceButton to the chat screen is a system `slide_from_bottom` animation. It has no continuity with the button — the two UI states feel disconnected. The button disappears and a modal slides up from underneath.

## Goal

A continuity (morph) transition where the VoiceButton pill visually expands into the chat screen and collapses back into it on close. The user should feel like the chat surface unfolds from the button and folds back into it.

---

## Decision Record

| Question | Decision |
|---|---|
| Morph shape | Pill expands — width, height, borderRadius all animate simultaneously |
| Expanding element colour | White (`#ffffff`) — matches chat background, cleaner than lime-to-white crossfade |
| Close behaviour | Full reverse morph — surface springs back to pill position before `router.back()` |
| Implementation approach | TransparentModal + Reanimated 4 (no new libraries, stays in Expo managed workflow) |

---

## Architecture

### Navigation change

`chat/index` in `app/_layout.tsx` changes from:

```
presentation: 'fullScreenModal', animation: 'slide_from_bottom'
```

to:

```
presentation: 'transparentModal', animation: 'none'
```

The system animation is disabled entirely. The chat screen owns its own enter/exit animation.

### Component layers (opening)

```
Tab layout (always visible beneath transparentModal)
  └── VoiceButton (lime pill, fades out via chatMorphing flag)

Chat screen (transparentModal, transparent background)
  ├── MorphSurface — white Animated.View, expands from pill → full screen
  └── Chat content — ChatNavBar + ScrollView + input zone, fades in on top
```

### New files

| File | Purpose |
|---|---|
| `mobile/src/hooks/useMorphTransition.ts` | Owns `progress` + `contentOpacity` shared values; exposes `open()` and `close(onDone)` |
| `mobile/src/components/ui/MorphSurface.tsx` | White `Animated.View` driven by `progress` prop; interpolates all layout properties |

### Edited files

| File | Change |
|---|---|
| `mobile/app/_layout.tsx` | `chat/index` screen options: `transparentModal + animation: 'none'` |
| `mobile/src/stores/uiStore.ts` | Add `chatMorphing: boolean` + setter |
| `mobile/src/components/VoiceButton.tsx` | Read `chatMorphing` from `uiStore`; apply `opacity: 0` when true |
| `mobile/app/chat/index.tsx` | Integrate `useMorphTransition`; replace `handleClose` with morph-aware version |

---

## Pill Measurements

Derived from `VoiceButton.tsx` — must match exactly for seamless handoff.

| Constant | Value | Source |
|---|---|---|
| `PILL_W` | `112` | icon `24` + `paddingHorizontal 44 × 2` |
| `PILL_H` | `56` | icon `24` + `paddingVertical 16 × 2` |
| `PILL_RADIUS` | `48` | `borderRadius` in VoiceButton |
| `PILL_BOTTOM` | `insets.bottom + 16` | VoiceButton bottom offset |
| `PILL_LEFT` | `(screenW - 112) / 2` | horizontally centred |

---

## Interpolation Map

`MorphSurface` interpolates these properties linearly against `progress` (0 = pill, 1 = full screen):

| Property | progress = 0 | progress = 1 |
|---|---|---|
| `width` | `PILL_W` | `screenWidth` |
| `height` | `PILL_H` | `screenHeight` |
| `borderRadius` | `PILL_RADIUS` (48) | `0` |
| `bottom` | `insets.bottom + 16` | `0` |
| `left` | `(screenW - PILL_W) / 2` | `0` |

Expansion is asymmetric by design: the surface expands mostly upward (pill starts near the bottom), and equally left/right (pill is centred).

---

## Animation Sequences

### Opening

1. `chat/index` mounts. `MorphSurface` renders at pill dimensions and position (progress = 0). White pill immediately covers the lime button.
2. `open()` fires in `useEffect` on mount.
3. `progress` springs from 0 → 1. Surface expands to fill screen.
4. After 60ms, `contentOpacity` fades from 0 → 1 over 180ms. Chat content appears as surface settles.
5. `uiStore.chatMorphing` is set to `true` on press (VoiceButton fades out).

### Closing

1. User taps caret-down in `ChatNavBar`. `handleClose()` fires.
2. `contentOpacity` fades 1 → 0 over 140ms.
3. On complete: `progress` springs from 1 → 0. Surface shrinks back to pill shape and position.
4. On complete: `runOnJS(router.back)()`. Screen unmounts.
5. `uiStore.chatMorphing` set to `false` immediately before `router.back()` fires (same `runOnJS` callback, before the back call). Lime button reappears as the screen unmounts.

---

## Spring Configuration

| Event | Config | Character |
|---|---|---|
| Surface open | `{ damping: 28, stiffness: 260 }` | Quick with a slight overshoot — feels alive |
| Content in | `withDelay(60, withTiming(1, { duration: 180 }))` | Fades in as surface settles |
| Content out | `withTiming(0, { duration: 140 })` | Snappy |
| Surface close | `{ damping: 32, stiffness: 300 }` | Crisper — snaps back with intent |

---

## Constraints

- **No new libraries.** Reanimated 4.1.1 already installed. All animation via `useAnimatedStyle` + `useSharedValue`.
- **Expo managed workflow.** `transparentModal` is supported by Expo Router without any native changes.
- **NativeWind / no StyleSheet.** `MorphSurface` uses inline style object from `useAnimatedStyle` (required by Reanimated) — this is the accepted exception per the DS constraint.
- **Pill constants are hardcoded** from `useSafeAreaInsets` + `useWindowDimensions`. If `VoiceButton` padding or size changes, `PILL_W`/`PILL_H`/`PILL_RADIUS` in `MorphSurface` must be updated to match.

---

## Out of Scope

- Text input mode in the chat (separate design session per `chat/index.tsx` comment)
- RecordingGlow morph (glow renders on top of MorphSurface after content fades in — no change needed)
- Haptic feedback on open/close (can be added later with one line)
