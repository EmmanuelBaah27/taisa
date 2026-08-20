# Interaction Feedback QA Plan

**Tier:** Standard Product QA revision  
**Branch:** `fix/glass-elevation-keyboard-surfaces`  
**Approved by Baah:** 2026-08-20

## Scope

- Restore centered content inside native and fallback glass button materials.
- Lift the selected navigation capsule and its content together by one optical pixel.
- Make the safe native discard-sheet action explicit as **Go back**.
- Add restrained tactile feedback for recording start, accepted send, dismiss, pause/resume,
  committed page selection, safe sheet exit, and destructive confirmation.
- Never emit repeated haptics while dragging, for a cancelled page swipe, or for disabled actions.

## Build and verification

1. Add failing regression tests for the approved geometry, sheet label, and haptic policy.
2. Centralize semantic haptic roles and reuse the existing `expo-haptics` dependency.
3. Apply haptics at accepted state changes rather than generic touch-down.
4. Run focused tests, full mobile tests, TypeScript, and design-system verification.
5. Commit and integrate the exact revision into `preview/taisa`; confirm the preview runtime.

## Device QA

- Confirm record, send, close, pause/resume, page-swipe settlement, and discard-sheet feedback each
  occur once and feel appropriately weighted.
- Confirm cancelled swipes and disabled actions are silent.
- Confirm glass icons are centered and the selected capsule no longer appears low.
