# Task Detail Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open the same expandable task-detail sheet from Home and the Tasks page while keeping “View all tasks” as the only route from Home to the Tasks page.

**Architecture:** Add a shared design-system sheet presentation contract. Extract the existing task detail into one reusable presentation view, then let the app shell and Tasks page present it with the shared `CareerWorkModel`.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, XCTest, TaisaDesignSystem, TaisaCareerWork, TaisaStorage

**Spec:** `docs/superpowers/specs/2026-11-19-task-detail-sheet-design.md`

## Global Constraints

- Support iOS and iPadOS 26 or later.
- Use design-system components, semantic tokens, and Central Icons only.
- Do not add feature-local sheet styling or a second task-detail implementation.
- Keep “View all tasks” as the only Home route to the Tasks page.
- Start the detail sheet at medium height and allow expansion to large height.
- Preserve existing task storage, lifecycle, and imported data.

## Review Focus

- A rapid second task tap must present the second task, not stale detail from the first task.
- A deleted task must dismiss the sheet and disappear after refresh.
- A failed detail load must keep recovery and retry behavior available in the sheet.
- A task mutation from the sheet must refresh the presenting Home or Tasks collection.
- Dismissing and reopening the sheet must not leave the shared model on a stale route.

---

### Task 1: Shared expandable-sheet contract

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaExpandableSheet.swift`
- Modify: `apple/Packages/TaisaFoundation/Tests/TaisaDesignSystemTests/ActionComponentTests.swift`

**Interfaces:**
- Consumes: SwiftUI sheet content and an `isPresented` or item binding from a product presenter.
- Produces: `TaisaExpandableSheet` or an equivalent public DS-owned modifier with medium and large detents and a visible drag indicator.

- [ ] **Step 1: Write the failing design-system test**

Add `expandableSheetOwnsApprovedTaskDetailPresentation()` and assert that the public contract exposes medium as its initial position, supports medium and large positions, and shows the drag indicator.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter ActionComponentTests.expandableSheetOwnsApprovedTaskDetailPresentation`

Expected: FAIL because the expandable-sheet contract does not exist.

- [ ] **Step 3: Implement the shared contract**

Create the DS-owned SwiftUI presentation adapter. Keep detents, drag-indicator visibility, and semantic background inside the component. Accept caller content through `@ViewBuilder`.

- [ ] **Step 4: Run the focused design-system tests**

Run: `swift test --package-path apple/Packages/TaisaFoundation --filter ActionComponentTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaExpandableSheet.swift apple/Packages/TaisaFoundation/Tests/TaisaDesignSystemTests/ActionComponentTests.swift
git commit -m "feat(design-system): add expandable task sheet"
```

### Task 2: Reusable task-detail presentation

**Files:**
- Modify: `apple/TaisaApp/CareerWork/CareerWorkView.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaCareerWork/CareerWorkModel.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaCareerWorkTests/CareerWorkModelTests.swift`
- Test: `apple/TaisaUnitTests/CareerWorkViewContractTests.swift`

**Interfaces:**
- Consumes: `CareerWorkModel`, `actionID: String`, `openRecovery: () -> Void`, and `dismiss: () -> Void`.
- Produces: `TaskDetailSheetContent`, an internal reusable view that selects the task, renders the existing detail, supports existing task mutations, and dismisses after successful deletion. `CareerWorkModel.deleteSelectedAction() async -> Bool` reports whether deletion succeeded.

- [ ] **Step 1: Write failing contract tests**

Add model tests proving deletion returns `true` only after a successful mutation and returns `false` on failure. Add view tests proving one reusable task-detail presentation consumes an action identifier, uses `CareerActionDetail`, selects `.action(id:)`, keeps recovery handling, and invokes dismissal only after successful deletion.

- [ ] **Step 2: Run the focused unit tests and verify failure**

Run: `xcodebuild test -project apple/Taisa.xcodeproj -scheme Taisa -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/CareerWorkViewContractTests`

Expected: FAIL because the reusable sheet content does not exist.

- [ ] **Step 3: Extract the reusable presentation**

Keep `CareerActionDetail` as the single detail renderer. Add loading, failure, retry, and recovery states around it. Select the requested action on task start and when the identifier changes. Use the existing model for every mutation.

- [ ] **Step 4: Make deletion dismissal explicit**

Change `deleteSelectedAction()` to return `Bool`, following the existing `editSelectedAction` mutation pattern. Call `dismiss()` only when it returns `true`. Ensure the presenter can refresh after dismissal.

- [ ] **Step 5: Run focused tests**

Run the Task 2 `xcodebuild test` command.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apple/TaisaApp/CareerWork/CareerWorkView.swift apple/Packages/TaisaFoundation/Sources/TaisaCareerWork/CareerWorkModel.swift apple/Packages/TaisaFoundation/Tests/TaisaCareerWorkTests/CareerWorkModelTests.swift apple/TaisaUnitTests/CareerWorkViewContractTests.swift
git commit -m "refactor(tasks): share task detail presentation"
```

### Task 3: Present task detail from Home

**Files:**
- Modify: `apple/TaisaApp/AppShell/PrimaryAppShell.swift`
- Modify: `apple/TaisaApp/Home/HomeSectionViews.swift`
- Modify: `apple/TaisaApp/Home/ThisWeekSection.swift`
- Test: `apple/TaisaUnitTests/PrimaryAppShellTests.swift`
- Test: `apple/TaisaUnitTests/HomeViewContractTests.swift`

**Interfaces:**
- Consumes: Task 1 expandable-sheet contract and Task 2 task-detail content.
- Produces: `PrimaryAppShellModel.presentTask(id:)` and `dismissTask()` with a selected Home task identifier separate from `workDestination`.

- [ ] **Step 1: Write failing shell and Home tests**

Assert that `.action(id)` sets the selected task sheet identifier without setting `workDestination`. Assert that `.actions` still sets `.tasks(route: nil)`. Assert that Home task rows send `.action(id)` and the summary row sends `.actions`.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `xcodebuild test -project apple/Taisa.xcodeproj -scheme Taisa -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/PrimaryAppShellTests -only-testing:TaisaUnitTests/HomeViewContractTests`

Expected: FAIL because Home action intent still routes to `workDestination`.

- [ ] **Step 3: Add shell-owned task selection**

Add `selectedTaskID: String?`, `presentTask(id:)`, and `dismissTask()` to `PrimaryAppShellModel`. Keep task-sheet selection independent of primary navigation and `workDestination`.

- [ ] **Step 4: Present the shared sheet**

Attach the Task 1 presentation contract to `PrimaryAppShell`. Supply Task 2 content, the shared `careerWorkModel`, refresh of `homeModel`, and dismissal.

- [ ] **Step 5: Preserve the Tasks route boundary**

Map `.action(id)` to `presentTask(id:)`. Keep `.actions` mapped to `.tasks(route: nil)`.

- [ ] **Step 6: Run focused tests**

Run the Task 3 `xcodebuild test` command.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apple/TaisaApp/AppShell/PrimaryAppShell.swift apple/TaisaApp/Home/HomeSectionViews.swift apple/TaisaApp/Home/ThisWeekSection.swift apple/TaisaUnitTests/PrimaryAppShellTests.swift apple/TaisaUnitTests/HomeViewContractTests.swift
git commit -m "feat(home): present task detail sheet"
```

### Task 4: Present the same sheet from Tasks

**Files:**
- Modify: `apple/TaisaApp/CareerWork/CareerWorkView.swift`
- Test: `apple/TaisaUnitTests/CareerWorkViewContractTests.swift`

**Interfaces:**
- Consumes: Task 1 expandable-sheet contract and Task 2 task-detail content.
- Produces: Tasks collection selection that opens the shared sheet instead of a navigation destination.

- [ ] **Step 1: Write failing Tasks-page tests**

Assert that a task collection tap selects the sheet identifier, does not set the navigation detail route, and presents the shared sheet contract. Cover switching directly from one task identifier to another and dismissal after deletion.

- [ ] **Step 2: Run focused tests and verify failure**

Run the Task 2 focused `xcodebuild test` command.

Expected: FAIL because the task collection still uses `selectedRoute` navigation.

- [ ] **Step 3: Add Tasks-page sheet selection**

Add task-sheet item state to the actions root. Keep Goal and Evidence routes unchanged. Task row activation sets the sheet item and presents Task 2 content through Task 1.

- [ ] **Step 4: Refresh collection state**

After mutation or dismissal, reload the shared model so changed or deleted tasks appear correctly in the collection.

- [ ] **Step 5: Run focused tests**

Run the Task 2 focused `xcodebuild test` command.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apple/TaisaApp/CareerWork/CareerWorkView.swift apple/TaisaUnitTests/CareerWorkViewContractTests.swift
git commit -m "feat(tasks): present task detail sheet"
```

### Task 5: Integrated verification and simulator smoke test

**Files:**
- Modify only files required by failures found in this task.

**Interfaces:**
- Consumes: Tasks 1 through 4.
- Produces: A verified APF-69 candidate installed on the iPhone 17 Pro simulator.

- [ ] **Step 1: Run the full foundation suite**

Run: `swift test --package-path apple/Packages/TaisaFoundation`

Expected: all tests pass.

- [ ] **Step 2: Run native Apple verification**

Run: `npm run verify:native-apple:all`

Expected: PASS.

- [ ] **Step 3: Build and install the simulator app**

Build `Taisa` for the booted iPhone 17 Pro simulator, install the result, and launch `com.taisa.app.dev`.

- [ ] **Step 4: Smoke-test both entry points**

Verify Home task tap opens the medium sheet, drag expands it to large, dismissal returns Home, “View all tasks” opens Tasks, and a Tasks-page task tap opens the same sheet.

- [ ] **Step 5: Smoke-test mutations and failure boundaries**

Verify an edit refreshes detail and its presenting list, deletion dismisses the sheet and removes the row, and a load failure shows recovery or retry without routing away.

- [ ] **Step 6: Record the exact evidence in APF-69**

Record commit, test counts, simulator device, smoke results, and any remaining blocker. Do not mark Ship approved.

- [ ] **Step 7: Commit any verification-only repair**

Commit only if Step 2 through Step 5 required a code or test correction.
