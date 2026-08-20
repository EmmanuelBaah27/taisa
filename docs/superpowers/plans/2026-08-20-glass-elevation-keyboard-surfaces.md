# Glass Elevation and Keyboard Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the navbar, typing composer, and shared glass controls soft unclipped elevation; remove the keyboard’s black backdrop; vertically center the selected capsule; and clear the Chats date badge from the header fade.

**Architecture:** Keep all existing screen geometry and business behavior. Shared glass elevation is owned by an outer business-free caster while the inner native/fallback material remains clipped to its shape; screen-specific keyboard and list spacing stay in the chat shell and Chats screen. Pure constants and source-contract tests protect geometry and presentation boundaries.

**Tech Stack:** Expo SDK 54, React Native 0.81, NativeWind, Expo Glass Effect, Expo Blur, Reanimated 4, Jest.

**Spec:** `docs/features/glass-elevation-keyboard-surfaces.md`

## Global Constraints

- Preserve navbar shell/capsule widths, heights, horizontal positions, icons, labels, colors, and navigation animation.
- Preserve composer dimensions, input behavior, copy, and send/record actions.
- Native glass must remain the preferred iOS material and must never be nested.
- The glass material clips to its shape; the elevation caster must not clip.
- Use semantic theme roles and NativeWind; do not add `StyleSheet.create()` or a native dependency.
- Device QA from the exact published `preview/taisa` revision is required.

---

### Task 1: Unclipped shared glass-button elevation

**Files:**
- Modify: `mobile/src/components/ui/liquidGlass.ts`
- Modify: `mobile/src/components/ui/LiquidGlassButtonSurface.tsx`
- Modify: `mobile/src/components/ui/__tests__/liquidGlass.test.ts`
- Modify: `mobile/src/components/ui/__tests__/LiquidGlassButtonSurface.test.ts`
- Modify: `docs/design-system.md`

**Interfaces:**
- Produces: `LiquidGlassFallbackTokens` with shared neutral shadow offset/radius/opacity values.
- Produces: `LiquidGlassButtonSurface` with one non-clipping outer elevation view and one clipped material view, without changing its props.

- [ ] Add tests asserting the outer surface owns the shadow, the material child owns `overflow: 'hidden'`, and prominent/standard/subtle hierarchies resolve deliberate neutral elevation.
- [ ] Run `npm test -- --runInBand src/components/ui/__tests__/liquidGlass.test.ts src/components/ui/__tests__/LiquidGlassButtonSurface.test.ts` and confirm the new assertions fail for the missing outer caster/token fields.
- [ ] Extend the pure appearance tokens with hierarchy-specific shadow values and wrap both native and fallback materials in the non-clipping animated elevation layer.
- [ ] Keep press scale on the outer animated layer so the shadow and material scale together; keep blur/sheen inside the clipped fallback material.
- [ ] Document that elevation is shared by native and fallback glass controls.
- [ ] Re-run the focused tests and `npm run typecheck`.
- [ ] Commit `fix(ds): elevate shared glass controls`.

### Task 2: Navbar shadow and capsule centering

**Files:**
- Modify: `mobile/src/navigation/bottomNavigation.ts`
- Modify: `mobile/src/components/ui/BottomNavBar.tsx`
- Modify: `mobile/src/navigation/__tests__/bottomNavigation.test.ts`
- Modify: `docs/design-system.md`

**Interfaces:**
- Consumes: existing `BOTTOM_NAVIGATION_FIGMA.elevation` contract.
- Produces: exact 6-point top and bottom capsule padding inside the 60-point navbar shell.

- [ ] Change the navigation tests to require a broader, softer neutral elevation and to require `top: 6` with a 48-point capsule height and no optical Y offset.
- [ ] Run `npm test -- --runInBand src/navigation/__tests__/bottomNavigation.test.ts` and confirm failure against the current `top: 8` and shadow constants.
- [ ] Remove `CAPSULE_OPTICAL_OFFSET_Y`, center the capsule at 6 points, and tune only the neutral elevation opacity/radius/offset while preserving every layout/motion constant.
- [ ] Update the navbar design-system entry to state equal vertical padding.
- [ ] Re-run the focused test and `npm run typecheck`.
- [ ] Commit `fix(ds): center and elevate bottom navigation`.

### Task 3: Elevated typing composer and opaque keyboard-safe shell

**Files:**
- Modify: `mobile/src/components/ui/VoiceComposer.tsx`
- Modify: `mobile/src/components/ui/ChatSurfaces.tsx`
- Modify: `mobile/src/components/ui/__tests__/VoiceComposer.test.ts`
- Modify: `mobile/src/components/ui/__tests__/ChatSurfaces.test.ts`
- Modify: `mobile/src/navigation/__tests__/localCaptureRoutes.test.ts`
- Modify: `docs/design-system.md`

**Interfaces:**
- Produces: the existing text-mode composer container with unchanged minimum height/radius and a semantic white elevation caster.
- Produces: `ChatScreenShell` whose outer `KeyboardAvoidingView` owns `bg-background`.

- [ ] Add a composer test asserting text mode retains `min-h-[100px]` and `rounded-[28px]` while the container has neutral shadow styling.
- [ ] Add shell/source tests asserting `KeyboardAvoidingView` owns `bg-background` and the transparent modal remains unchanged for the card morph.
- [ ] Run the three focused test files and confirm failure for missing elevation and missing outer background.
- [ ] Add the neutral composer shadow without altering its border, padding, input height, or action positions.
- [ ] Add `bg-background` to the keyboard-avoiding shell so padding never exposes the transparent modal host.
- [ ] Update the composer and shell design-system entries.
- [ ] Re-run the focused tests, `npm run typecheck`, and `npm run verify:design-system`.
- [ ] Commit `fix(ds): polish keyboard composer surface`.

### Task 4: Chats header-fade clearance

**Files:**
- Modify: `mobile/app/(tabs)/chats.tsx`
- Modify: `mobile/src/navigation/__tests__/chatListSpacing.test.ts`

**Interfaces:**
- Produces: a 12-point initial list top inset above the first sticky date group without changing later section spacing or sticky behavior.

- [ ] Add a source-contract assertion for `paddingTop: 12` in the Chats `contentContainerStyle`, while retaining the border-only sticky badge assertions.
- [ ] Run `npm test -- --runInBand src/navigation/__tests__/chatListSpacing.test.ts` and confirm failure because no initial top clearance exists.
- [ ] Add the 12-point tokenized top padding to the list content container only.
- [ ] Re-run the focused test and `npm run typecheck`.
- [ ] Commit `fix: clear chat dates from header fade`.

### Task 5: Full verification and canonical preview publication

**Files:**
- Review only: all files changed by Tasks 1–4.

**Interfaces:**
- Produces: a committed revision integrated into and served by canonical `preview/taisa`.

- [ ] Run `npm test -- --runInBand` in `mobile/` and require zero failures.
- [ ] Run `npm run typecheck`, `npm run verify:design-system`, and `npm run verify:button-surfaces` in `mobile/`.
- [ ] Run `git diff --check`, inspect the complete branch diff, and complete the required local code review.
- [ ] Commit any review corrections and repeat the affected checks.
- [ ] Integrate the verified branch into `preview/taisa`, push `origin/preview/taisa`, fetch, and confirm local/remote SHAs match.
- [ ] Launch the paired iPhone from the canonical preview Metro runtime and inspect native logs for crashes, Worklets errors, and glass-effect failures.
- [ ] Hand off the exact revision for Baah device QA; do not claim Ship readiness before that gate passes.

