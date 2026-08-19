# Taisa Design System

Living reference for all UI work. Update when a new component is added or a token changes.
Full token definitions and decision rules: `foundations.md` (root of repo).

---

## Status

| Layer | State |
|---|---|
| Styling | NativeWind (Tailwind CSS for React Native) — all screens |
| Tokens | Taisa DS light theme — `mobile/tailwind.config.js` + `mobile/global.css` |
| Typography | Inter — `Inter_400Regular`, `Inter_500Medium`, `Inter_600SemiBold`, and `Inter_700Bold` loaded via `expo-font` in `app/_layout.tsx` |
| Components | Primitives in `mobile/src/components/ui/` |

---

## How to use tokens

**Always use the semantic utility layer — never raw hex, never palette classes unless no semantic exists.**

```
1. Semantic utility first  — bg-background, text-foreground, bg-primary
2. Named palette fallback  — bg-lime-100 (only when no semantic alias covers the role)
3. Never                   — raw hex values
```

---

## Color tokens

### Semantic utilities (use these)

| Token | Class | Hex | Role |
|---|---|---|---|
| Page background | `bg-background` | `#ffffff` | Root screen background |
| Transparent page fade | `colors.backgroundTransparent` | `rgba(255,255,255,0)` | Native gradient edge paired with page background |
| Card surface | `bg-card` | `#ffffff` | Cards, panels, modals |
| Subtle fill | `bg-subtle` | `#f9f9f9` | Hover states, subtle sections |
| Muted fill | `bg-muted` | `#f3f3f3` | Input backgrounds, disabled |
| Primary text | `text-foreground` | `#060707` | Headings, body copy |
| Secondary text | `text-muted-foreground` | `#5f646a` | Labels, metadata |
| Tertiary text | `text-text-tertiary` | `#898989` | Placeholders, timestamps |
| Default border | `border-border` | `#e6e6e6` | Cards, inputs |
| Subtle border | `border-border-subtle` | `rgba(6,7,7,0.08)` | Hairline separators |
| Strong border | `border-border-strong` | `#dadada` | Elevated borders |
| Primary CTA bg | `bg-primary` | `#cdec1a` | Buttons, FAB, active indicators |
| Text on primary | `text-primary-foreground` | `#060707` | Text on lime buttons |
| Lime accent text | `text-lime-700` | `#778700` | Accent-colored text on light bg |
| Lime subtle bg | `bg-lime-100` | `#edfbca` | ThemeTag, subtle tints |

### Status utilities

| Status | Text/icon | Subtle bg |
|---|---|---|
| Success | `text-success` (`#04851a`) | `bg-success-subtle` (`#e7f9e9`) |
| Warning | `text-warning` (`#e46300`) | `bg-warning-subtle` (`#fcf2e8`) |
| Danger | `text-danger` (`#c60000`) | `bg-danger-subtle` (`#fff0ea`) |
| Info | `text-info` (`#0c79e6`) | `bg-info-subtle` (`#ebf5ff`) |

---

## Typography

Never use raw `text-sm font-semibold` combinations — use the composite utilities:

| Semantic weight | Inter registration |
|---|---|
| Regular (400) | `Inter_400Regular` |
| Medium (500) | `Inter_500Medium` |
| Semibold (600) | `Inter_600SemiBold` |
| Bold (700) | `Inter_700Bold` |

| Class | Size | Weight | Use for |
|---|---|---|---|
| `text-H1` | 24px / 32px lh | 600 | Page headings |
| `text-H2` | 22px / 28px lh | 600 | Section headings |
| `text-H3` | 20px / 26px lh | 600 | Sub-headings |
| `text-xlg-regular` | 18px / 26px lh | 400 | Large body |
| `text-lg-regular` | 18px / 26px lh | 400 | Body |
| `text-lg-medium` | 18px / 26px lh | 500 | Body emphasis |
| `text-lg-semibold` | 18px / 26px lh | 600 | Body strong |
| `text-base-regular` | 16px / 22px lh | 400 | **Base UI — default text size** |
| `text-base-medium` | 16px / 22px lh | 500 | UI emphasis |
| `text-base-semibold` | 16px / 22px lh | 600 | UI strong |
| `text-base-bold` | 16px / 22px lh | 700 | Strong compact emphasis where semibold is insufficient |
| `text-small-regular` | 14px / 20px lh | 400 | Small labels, metadata |
| `text-small-medium` | 14px / 20px lh | 500 | Small emphasis |
| `text-small-semibold` | 14px / 20px lh | 600 | Small strong |
| `text-caption-regular` | 12px / 16px lh | 400 | Timestamps, micro labels |
| `text-caption-medium` | 12px / 16px lh | 500 | Caption emphasis |
| `text-caption-semibold` | 12px / 16px lh | 600 | Caption strong |

---

## Border radius

| Class | Value | Use for |
|---|---|---|
| `rounded-1` | 4px | Badges, chips |
| `rounded-2` | 8px | Inputs, small buttons |
| `rounded-3` | 12px | Cards, modals |
| `rounded-4` | 16px | Larger panels, sheets |
| `rounded-full` | 9999px | Pills, FAB, avatars |

---

## Components (`mobile/src/components/ui/`)

| Component | Props | Notes |
|---|---|---|
| `Button` | `variant`, `size`, `label`, `icon`, `loading`, `disabled` | Six variants; three sizes |
| `Badge` | `color`, `appearance`, `size`, `icon`, `onDismiss` | Eight colors; three appearances |
| `Card` | `surface`, `className`, `style` | Two surfaces (default / elevated) |
| `Input` | `size`, `error`, `...TextInputProps` | Two sizes; error state |
| `Icon` | `name`, `size`, `color` | 1906 icons — `round-outlined-radius-2-stroke-1.5` style via `react-native-svg` |
| `BottomNavBar` | _(none)_ | Figma-state app navigation: 240×60 for Home/Chats and 220×60 for Me; all three tab identities remain mounted above a content-free moving glass capsule; each icon has one direct visual-position value, independent from its animated hit frame, and follows the same non-oscillating 260ms curve as the capsule; the incoming full label fades and scales outward from the icon-facing edge over 160ms (never width-clipped), while the outgoing label fades in place over 80ms before resetting invisibly; the 6% grey fill begins returning at 120ms and completes with arrival; navigation mounting waits until the 260ms travel completes so route rendering cannot interrupt it; no tab icon is hidden or exchanged; the glass shell and selected capsule rise uniformly to 1.12 over 70ms, hold for 100ms, then return over 90ms, while the icon-and-label layer remains unscaled so glyphs stay crisp; Me preserves the Navii avatar; native iOS glass with material-blur fallback |
| `SelectedNavigationItem` | `label`, `leadingVisual`, `width`, `onPress`, `onPressIn?`, `onPressOut?` | Selected tab primitive from Figma node 454:738: 48px high, 16px horizontal padding, 24px visual, 8px gap, Inter Medium 16/24, and 6% black fill |
| `InactiveNavigationItem` | `accessibilityLabel`, `icon`, `leadingVisual?`, `onPress`, `onPressIn?`, `onPressOut?` | Inactive tab primitive from Figma node 453:723: 56×48px, 16px horizontal padding, 24px Neutral/400 icon, no fill; optional leading visual preserves the Navii profile avatar |
| `PersistentNavigationCapsule` | `label`, `leadingVisual`, `frame`, `phase`, `surfaceOnly?`, `animatedContainerStyle?`, `animatedContentStyle?`, `animatedFillStyle?`, `animatedLabelStyle?`, `outgoingLabel?`, `animatedOutgoingLabelStyle?` | Business-free selected navigation surface: one clipped, absolutely positioned 48px capsule whose `phase` renders the exact 6% fill at rest and clear glass while travelling/settling; `surfaceOnly` lets persistent tab content render above it without duplicated icons; native glass views are never nested |
| `VoiceButton` | `onPress?` | State-owning wrapper for the central CTA; fresh entry opens voice mode with one automatic recorder start |
| `VoiceEntryButton` | `bottomInset`, `hidden`, `onPress` | Presentational 104×56 lime CTA positioned 12px above `BottomNavBar`, with the Figma glow and accessible voice label |
| `WorkspaceHeader` | `subtitle: string` | Screen-level header; workspace name from `careerStore.profile.currentCompany`; contextual subtitle |
| `ChatNavBar` | `title`, `topInset`, `onClose` | Figma chat header: floating 56px caret-down control on the left and truncated conversation title centred independently of side slots |
| `RecordingGlow` | `amplitude: number` | Amplitude-reactive lime glow anchored to screen bottom; 0 = very faint, 10 = full brightness; uses `expo-linear-gradient` + `Animated` with `useNativeDriver` |
| `LiveTranscriptionText` | `transcript: string` | Centred text area; shows grey "What's on your mind?" when empty, switches to `text-lime-700` when transcript streams in |
| `TaisaReplyCard` | `appearance`, `responseId`, `content`, local reaction state and callbacks | Assistant reply with `card` and Figma-aligned unboxed `plain` presentation; local Helpful / Not helpful controls remain available and sharing requires a separate preview action |
| `ChatListRow` | `title`, `preview`, `needsAttention`, `onPress` | Accessible, borderless Chats index row; attention is explicit and never inferred from message copy |
| `ThreadMessage` | `role`, `content`, `inputType` | User messages use a neutral right-aligned bubble; assistant messages remain unboxed |
| `VoiceComposer` | `mode`, `voiceState`, `durationSeconds`, `amplitude`, draft state and callbacks | Bottom-loaded active voice/text composer with a voice-ready Reply control, speech-responsive Pause/Resume cradle, and stable Send position |
| `VoiceDraftStrip` | `label`, `preview`, `onOpen`, `onDelete` | Compact representation of the inactive input; deletion remains an isolated tap target |
| `TranscriptCorrectionCard` | `value`, `disabled`, `onChangeText`, `onCancel`, `onSubmit` | Presentational transcript correction editor with Cancel and Update response actions |
| `ChatScreenShell` | `topInset`, `title`, `animatedStyle`, `onClose`, `footer` | Keyboard-safe full-screen shell with entry-only card expansion, floating conversation header, and footer slot; close is immediate and has no reverse motion |
| `ChatConversationSurface` | messages, active request state, reaction state, error/proposal/transcript callbacks | Scrollable conversation rendering composed from typed chat surfaces |
| `ChatMessageBubble` | `content`, `editable`, `showCorrectionHint`, `onEdit` | User turn bubble with a semantic transcript-correction action |
| `PendingTranscriptBubble` | `transcript` | Optimistic voice transcript shown while coaching is pending |
| `ChatProcessingBubble` | _(none)_ | Assistant thinking interstitial |
| `ChatErrorPanel` | message and recovery callbacks | Tokenized error feedback with keyboard, retry, and voice-discard actions |
| `PendingProposalCard` | `proposal`, `disabled`, `onConfirm`, `onResolve` | Memory confirmation or explicit conflict-resolution choices |
| `ChatComposerDock` | `phase`, `bottomInset`, `children` | Safe-area composer slot or transcribing/processing status |
| `ChatSurfaces` | typed chat surface exports | Module grouping the conversation, composer, pending, processing, error, and proposal presentation primitives |
| `CubeRefractionOverlay` | shared `amplitude`, shared `cubeSize` | Native Skia recording effect; verify in the real recording screen on device |
| `GlowDevSheet` | controls, visibility, dismiss callback | Development-only native tuning surface; verify on device |
| `NaviiAvatar` | `seed`, `size` | Deterministic generated avatar presentation |

**Extraction rule:** pattern appears in 2+ places → extract to `ui/`. Do not extract speculatively.
**DS compliance:** no `StyleSheet.create()`, no raw hex, import tokens from Tailwind classes only.
## Voice composer

`VoiceComposer` is the bottom-loaded mixed-input control used by coaching conversations. The
waveform is its sole voice symbol across primary entry, mode switching, saved drafts, and Reply;
the text field contains no voice icon. In text mode, a separate soft-grey waveform control starts
recording when no draft exists, or includes the saved duration and opens draft actions when one
does. A stopped draft opens with Delete, Resume, and Send. Failed submitted audio hides the
editable composer and leaves only the conversation-level retry and discard actions.

When a conversation prefers voice, the idle composer is one soft-grey, full-width `Reply` control
with a black waveform icon. Its accessible label is `Reply by voice, starts recording`; it starts
recording only after that explicit tap. The control is unavailable only while a submission is in
progress, so offline recording remains available.

> **BTS:** Preferred input mode is local conversation state, not a microphone permission state.
> Persisting it lets an answered voice turn return to a calm, intentional Reply control after a
> restart without ever reopening the microphone on its own.

The central `VoiceButton` is the distinct voice-first entry point. It creates a one-shot entry
intent: the newly opened capture starts its first recording automatically when microphone
permission permits. Consuming that intent clears it. Subsequent completed responses reset only to
the calm voice-ready `Reply` state and never enqueue or trigger another automatic start.

## Chat surfaces

`app/chat/index.tsx` owns conversation state, recorder lifecycle, persistence calls, and entry
animation orchestration. Visual rendering belongs to the exported typed chat surfaces above; the screen does
not construct React Native visual primitives or define a `StyleSheet`. Static color roles use
NativeWind semantic utilities. Native APIs that require color values (icons, shadows, gradients)
use `constants/theme.ts`, including `backgroundTransparent` for the conversation fade.

Chats history opens the canonical chat route with the selected row's measured viewport frame. The
screen expands from that frame over the shared 380ms ease-out curve, or appears immediately when
measurement is unavailable or reduced motion is enabled. Closing from either chat or recording is
always immediate: there is no reverse collapse, slide-down, or drag-to-dismiss transition.
