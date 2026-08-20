# Glass Elevation and Keyboard Surface

**Tier:** Standard
**Track:** Product / Design System
**Stage:** Plan
**Design source:** Baah’s iOS reference photos and canonical preview screenshots, 20 August 2026

## What is it?

A QA refinement of the existing native-glass controls, bottom navigation, text composer, keyboard-safe chat shell, and Chats page header spacing. The revision preserves established component geometry while making floating surfaces read as softly elevated on white and removing transparent gaps around the iOS keyboard.

## Why now?

The canonical preview exposes three connected visual defects: glass buttons and the navbar lose their elevation against white pages, keyboard avoidance reveals the transparent modal’s dark host background, and the first Chats date badge intersects the page-header fade. The latest capsule optical offset also leaves unequal vertical padding.

## Acceptance criteria

- [ ] The bottom navbar keeps its current width, height, item layout, color, and native glass material while showing a broad, soft neutral shadow on white pages.
- [ ] The selected navbar capsule has equal top and bottom padding inside the 60-point shell.
- [ ] The typing composer keeps its current footprint and receives a white elevated surface with a soft neutral ambient shadow.
- [ ] Native and fallback glass buttons retain their geometry and press behavior while receiving visible, unclipped elevation.
- [ ] Opening the iOS keyboard never reveals black or transparent strips behind or beside the keyboard.
- [ ] The first Chats date badge begins below the page-header fade and remains sticky without gaining a section-wide background.
- [ ] Reduced-transparency and non-native-glass fallbacks remain supported.

## Platform dependencies

None. The existing Expo Glass Effect, Reanimated, NativeWind, and React Native keyboard APIs are sufficient.

## Out of scope

- Navbar size, horizontal item positions, icons, labels, colors, or navigation motion.
- Composer field dimensions, copy, send behavior, or keyboard behavior outside the canonical chat route.
- New blur materials or dark-theme tokens.
- Changes to chat data, transcription, recording, or backend behavior.

## Design handoff

| Element | Verdict | File / change |
|---|---|---|
| Navbar glass shell | Modify | `mobile/src/components/ui/BottomNavBar.tsx` and `mobile/src/navigation/bottomNavigation.ts` — broader neutral elevation only |
| Selected capsule | Modify | `mobile/src/components/ui/BottomNavBar.tsx` — remove vertical optical offset and restore 6/6 centering |
| Shared glass buttons | Modify | `mobile/src/components/ui/LiquidGlassButtonSurface.tsx` — separate unclipped elevation caster from clipped glass content |
| Text composer | Modify | `mobile/src/components/ui/VoiceComposer.tsx` — elevated white rounded field, unchanged geometry |
| Keyboard-safe page | Modify | `mobile/src/components/ui/ChatSurfaces.tsx` — opaque semantic background on the outer keyboard-avoiding shell |
| Chats first date | Modify | `mobile/app/(tabs)/chats.tsx` — tokenized top clearance before the first sticky header |

**Token gaps:** None. Use the existing background, border, and neutral shadow roles; exact opacity/radius values are component motion tokens covered by device QA.

**Backend implications:** None.

