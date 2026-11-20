# Native Typography Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make bundled Taisa fonts the only authored typography path in the native app and fail CI when future Product work bypasses it.

**Architecture:** `TaisaTypography` remains the semantic authority: Inter owns UI/body/navigation/metadata roles and Scoutie Sans owns display/page-title roles. Product screens consume those roles through `TaisaText` or DS components; a source verifier rejects raw Product font declarations while runtime tests prove the bundled PostScript names resolve.

**Tech Stack:** SwiftUI, Swift Testing, XCTest, Node.js native-design-system verifier, Xcode iOS/iPadOS 26 simulators.

**Spec:** [APF-75 approved Scope and Plan](https://linear.app/a-playing-field/issue/APF-75/complete-remaining-native-design-system-adoption-migration) and `docs/design-system.md`.

## Global Constraints

- Preserve iOS/iPadOS 26+ and Dynamic Type scaling.
- Preserve business logic, native navigation state, Back behavior, and encrypted local data.
- Inter is the family for UI/body/navigation/metadata roles; Scoutie Sans is the family for display/page-title roles.
- Product source may not own raw system/custom font declarations or font-family names.
- No new feature-local typography API or broad system-owned exception.
- APF-69 remains downstream and is not modified in this branch.

## Review Focus

- A missing or incorrect PostScript name must fail before silently falling back to San Francisco.
- Dynamic Type must continue to scale each semantic role from its intended text style.
- Raw font syntax hidden behind qualified or weighted SwiftUI expressions must be rejected.
- Native navigation and Back behavior must survive DS-owned title presentation.
- Long/localized text and accessibility sizes must not be clipped by fixed line-height workarounds.

---

### Task 1: Semantic font contract

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TypographyToken.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaText.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaDesignSystemTests/TypographyTokenTests.swift`
- Modify: `docs/design-system.md`

**Interfaces:**
- Produces: semantic `TaisaTypography.family`, `pointSize`, `relativeTextStyle`, and `font` mappings used by all DS and Product consumers.

- [ ] Write failing tests asserting literal family/size/weight/style mappings for every semantic role and UIKit runtime resolution for `Inter` and `Scoutie Sans`.
- [ ] Run focused DS tests and verify failure because current roles use system fonts and expose no family contract.
- [ ] Implement the minimal semantic mapping with relative custom fonts and document the native role table.
- [ ] Run focused DS tests and verify they pass.
- [ ] Commit the semantic typography contract.

### Task 2: Fail-closed typography enforcement

**Files:**
- Modify: `scripts/native-apple/verify-design-system.mjs`
- Modify: `scripts/native-apple/__tests__/verify-design-system.test.mjs`

**Interfaces:**
- Consumes: Product must use the Task 1 semantic typography API.
- Produces: `rawTypographyValues(root)` violations and a failing native DS gate for new Product typography bypasses.

- [ ] Add verifier fixture tests that fail on `.font(.system...)`, semantic shortcuts such as `.headline`, custom family literals, and weighted raw font expressions while allowing DS semantic references.
- [ ] Run verifier tests and verify RED because raw typography is not detected.
- [ ] Implement Swift-aware typography detection with file/line/value diagnostics.
- [ ] Run verifier tests and verify the fixtures pass while the real app fails on the existing migration debt.
- [ ] Commit the enforcement contract.

### Task 3: Full Product adoption

**Files:**
- Modify: native Product files reported by `rawTypographyValues("apple/TaisaApp")`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaPageChrome.swift`
- Modify: affected app contract tests under `apple/TaisaUnitTests/`

**Interfaces:**
- Consumes: Task 1 semantic roles and Task 2 verifier.
- Produces: zero raw Product typography violations and DS-owned shared page chrome.

- [ ] Add or adjust focused behavioral/view contract tests for affected rows, titles, and shared headers; verify RED where raw typography remains.
- [ ] Replace each reported Product font with `TaisaText` or an existing semantic DS role without changing data/navigation behavior.
- [ ] Replace the shared page-header system font with its semantic role.
- [ ] Run app contract tests and the real DS verifier until both pass.
- [ ] Commit the full Product migration.

### Task 4: Authored navigation titles and integration proof

**Files:**
- Modify: shared navigation/page-header components and their Product consumers as identified by the audit.
- Modify: `apple/TaisaUITests/TaisaLaunchTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3 typography and enforcement contracts.
- Produces: DS-rendered authored titles with unchanged native route and Back semantics.

- [ ] Add failing UI/contract coverage for DS title ownership plus Home/Chats/You and child-page navigation behavior.
- [ ] Implement the smallest shared toolbar/header adaptation that preserves native NavigationStack state and Back controls.
- [ ] Run focused package, verifier, unit, and UI tests on iPhone and iPad simulators.
- [ ] Run `npm run verify:native-apple:fast`, review the whole branch, resolve blocking findings with RED→GREEN evidence, then run the applicable full native matrix once on the frozen candidate.
- [ ] Commit integration proof and prepare APF-75 for canonical-preview QA.
