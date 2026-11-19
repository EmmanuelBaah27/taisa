# APF-69 DS Control Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove raw SwiftUI buttons from the complete APF-69 changed Product surface using approved shared DS contracts.

**Architecture:** Extend `TaisaButton` for compact Tasks actions, add a generic `TaisaPressable<Label>` for arbitrary interactive row content, and move existing platform wrappers into dedicated primitive files. Product and composite DS sources then consume only those contracts under APF-88 verification.

**Tech Stack:** SwiftUI, Swift Testing/XCTest source contracts, Node native DS verifier

**Spec:** APF-69 Linear issue and approval comment dated 2026-11-18

## Global Constraints

- No new raw-button policy debt or broad module exemption.
- Raw SwiftUI `Button` remains only in dedicated registered primitive files.
- Existing tokens and Central Icons only.
- Preserve the approved Figma Tasks geometry, date-picker behavior, keyboard behavior, accessibility identifiers, and local persistence.

## Review Focus

- Compact buttons must retain 44-point effective touch targets where visually smaller.
- Icon-only buttons need explicit accessibility labels.
- Generic pressables must not introduce styling or business semantics.
- System menu/dialog actions retain native roles and cancellation behavior.
- Moving primitives must not change public API names used by existing consumers.

---

### Task 1: Shared button contracts

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaButton.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaPressable.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaDesignSystemTests/ActionComponentTests.swift`

- [ ] Add failing contract tests for intrinsic/circular button layouts and the generic pressable.
- [ ] Implement the minimal token-backed shared contracts.
- [ ] Run focused design-system tests and commit.

### Task 2: Dedicated primitive boundaries

**Files:**
- Split primitive wrappers from `TaisaPageChrome.swift` and `TaisaSystemControls.swift` into dedicated same-named component files.
- Modify: `scripts/native-apple/design-system-control-policy.json`
- Test: native DS verifier tests and CLI.

- [ ] Add failing verifier coverage for the dedicated files and changed source inventory.
- [ ] Move public APIs without behavior changes and register only dedicated primitive files.
- [ ] Run native DS verification and commit.

### Task 3: Complete APF-69 adoption

**Files:**
- Modify APF-69 changed Product and composite DS files reported by the verifier.
- Move the Tasks composer into `apple/TaisaApp/Home/TaskComposerView.swift`.
- Modify Home and CareerWork source-contract/UI tests.

- [ ] Replace arbitrary row/card buttons with `TaisaPressable`.
- [ ] Replace Tasks actions with compact `TaisaButton` variants.
- [ ] Replace toolbar/menu/dialog usages with their dedicated DS primitives.
- [ ] Run the Tasks UI regression, native DS verification, and focused package tests.
- [ ] Run `npm run verify:native-apple:fast`, inspect the complete diff, and commit the candidate.
