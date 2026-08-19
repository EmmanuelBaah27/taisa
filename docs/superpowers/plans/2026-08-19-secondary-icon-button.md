# Secondary Icon Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the reusable Figma-matched secondary icon button with the bottom navigation's fluid scale interaction.

**Architecture:** A business-free `SecondaryIconButton` owns its press animation and delegates icon rendering to the existing `Icon` primitive. Exact surface and motion values are exported as stable DS contracts so focused tests can protect the Figma measurements and navigation parity.

**Tech Stack:** React Native, NativeWind, React Native Animated, Storybook, Jest, TypeScript.

**Spec:** `docs/features/secondary-icon-button.md`

## Global Constraints

- Preserve Figma node `414:706`: 56×56 container, 24px icon, 16px padding, 40px radius, translucent white surface, 6% dark border, and 6px soft shadow.
- Reuse the navigation shell motion values: pressed scale 1.12, 70ms press, 100ms hold, 90ms release.
- Respect the operating system reduce-motion preference.
- Keep the component typed, business-free, exported, catalogued, and documented.
- Do not modify the recording page in this plan.

---

### Task 1: Protect the design and motion contract

**Files:**
- Create: `mobile/src/components/ui/__tests__/SecondaryIconButton.test.ts`
- Create: `mobile/src/components/ui/SecondaryIconButton.tsx`

**Interfaces:**
- Produces: `SECONDARY_ICON_BUTTON_FIGMA`, `SECONDARY_ICON_BUTTON_MOTION`, `SecondaryIconButtonProps`, and `SecondaryIconButton`.

- [x] Write focused assertions for the 56px surface, 24px icon, Figma colors/shadow, navigation-equivalent timing, accessibility, and disabled state.
- [x] Run `npm test -- --runInBand src/components/ui/__tests__/SecondaryIconButton.test.ts` and confirm it fails because the module is absent.
- [x] Implement the minimal typed component and motion contract.
- [x] Re-run the focused test and confirm it passes.

### Task 2: Catalogue and document the primitive

**Files:**
- Create: `mobile/src/components/ui/SecondaryIconButton.stories.tsx`
- Modify: `mobile/src/components/ui/index.ts`
- Modify: `docs/design-system.md`
- Modify: `docs/workflow.md`

**Interfaces:**
- Consumes: `SecondaryIconButton`.
- Produces: public barrel export, Storybook default/disabled examples, DS documentation, and workflow status.

- [x] Add default pause and disabled Storybook stories.
- [x] Export the component and its types/constants from the UI barrel.
- [x] Document visual, motion, accessibility, and intended-use rules.
- [x] Run `npm run verify:design-system` and confirm the catalog and documentation checks pass.

### Task 3: Verify the isolated DS change

**Files:**
- Verify all files changed by Tasks 1–2.

**Interfaces:**
- Produces: review evidence for the device-QA gate.

- [x] Run the focused component and navigation tests.
- [x] Run design-system verification.
- [x] Run mobile type-check and compare output with the recorded shared-types baseline; confirm no changed-file diagnostic is introduced.
- [x] Inspect the diff for DS compliance, raw styling drift, and accidental recording-page changes.

## Verification evidence

- Focused component/navigation tests: 12 passed, 0 failed.
- Design-system verification: passed with 23 catalog modules.
- Mobile type-check: existing `@taisa/shared` export failures remain from the approved baseline exception; no changed-file diagnostic is present.
- Diff check: passed; the recording page is unchanged.
