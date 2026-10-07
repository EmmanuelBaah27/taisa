# SwiftUI Functional Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the native foundation landing screen with an iOS 26 SwiftUI Home that reads recent conversations, active goals, and open actions from Taisa's encrypted local store.

**Architecture:** Add one coherent, bounded Home read query in `TaisaStorage`; place platform-neutral Home snapshot/state contracts and the observable feature model in a focused `TaisaHome` package target; compose the real store and recovery route in a small app shell. Native SwiftUI views render explicit states and keep feature presentation local so later redesign does not disturb data or navigation contracts.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, XCTest/XCUITest, GRDB + SQLCipher, XcodeGen, iOS/iPadOS 26+

**Spec:** `docs/superpowers/specs/2026-10-07-swiftui-functional-home-design.md`

## Global Constraints

- Target iOS/iPadOS 26 or later and continue supporting iPhone and iPad destinations.
- Build with standard SwiftUI navigation, list, toolbar, loading, empty, focus, and accessibility behavior.
- Home reads only the encrypted local store; network and CloudKit availability never gate rendering.
- SwiftUI views and `TaisaHome` do not import GRDB or issue SQL.
- Preserve the active store on every read, key, integrity, migration, and recovery failure.
- Do not import React Native data, delete React Native code, or trigger native production cutover.
- Do not add AI summaries, voice UI, custom glass, custom navigation, speculative DS components, or final Home art direction.
- Use synthetic content only in previews and tests; logs and diagnostics remain content-free.
- Keep existing recovery behavior and development/Preview/Personal identity isolation intact.
- Update documentation, previews, tests, and generated Xcode project state in the same change as their implemented contracts.

## Review Focus

- Equal timestamps and nil action due dates must produce stable ordering across repeated reads; Task 2 pins both cases.
- A refresh that finishes out of order must not replace newer Home state; Task 3 pins generation-based stale-result rejection.
- A refresh failure after content is visible must preserve the content and surface a retryable issue; Task 3 pins this state.
- A missing Keychain key or corrupt existing store must route to recovery without creating or replacing storage; Task 4 pins the composition result.
- Accessibility-size text and narrow iPad windows must keep headings and recovery/retry actions reachable; Task 6 pins identifiers and layout scenarios.

---

### Task 1: Reconcile the native program and raise the platform baseline

**Files:**
- Modify: `apple/Config/Base.xcconfig`
- Modify: `apple/project.yml`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Modify: `apple/Taisa.xcodeproj/project.pbxproj` (generated)
- Modify: `docs/features/swiftui-native-rebuild.md`
- Modify: `docs/superpowers/specs/2026-10-03-swift-first-native-rebuild-design.md`
- Modify: `docs/migration/swiftui/program-ledger.md`
- Test: `scripts/native-apple/__tests__/verify-project-baseline.test.mjs`
- Modify: `scripts/native-apple/verify.mjs`

**Interfaces:**
- Consumes: approved Product baseline from the feature spec.
- Produces: one enforceable iOS 26 deployment floor and canonical native-program status/direction.

- [ ] **Step 1: Write the failing deployment-floor verifier test**

Add assertions that read `Base.xcconfig`, `project.yml`, and `Package.swift` and require, respectively:

```js
assert.match(baseConfig, /IPHONEOS_DEPLOYMENT_TARGET = 26\.0/);
assert.match(project, /iOS: "26\.0"/);
assert.match(packageManifest, /\.iOS\(\.v26\)/);
```

Also assert the canonical SwiftUI scope contains `native-first`, `functionality`, and `iOS/iPadOS 26`, and no longer declares visual parity or baseline freeze as a Product prerequisite.

- [ ] **Step 2: Run the verifier test and confirm the old baseline fails**

Run: `node --test scripts/native-apple/__tests__/verify-project-baseline.test.mjs`

Expected: FAIL because the repository still declares iOS 17 and stale parity-first program state.

- [ ] **Step 3: Update the deployment floor and canonical program documents**

Set:

```text
apple/Config/Base.xcconfig: IPHONEOS_DEPLOYMENT_TARGET = 26.0
apple/project.yml: deploymentTarget.iOS = "26.0"
Package.swift: .iOS(.v26)
```

Reconcile the native rebuild scope/spec/ledger to state that the foundation is shipped, encrypted storage/recovery is merged, Product work proceeds in functionality-first vertical slices, React Native is non-blocking reference, redesign follows functional completion, and visual parity is not a gate. Preserve historical plan files rather than rewriting their recorded outcomes.

- [ ] **Step 4: Regenerate and verify the Xcode project**

Run: `npm run generate:native-apple`

Run: `node --test scripts/native-apple/__tests__/verify-project-baseline.test.mjs && bash scripts/native-apple/verify-generated-project.sh`

Expected: PASS; generated `project.pbxproj` matches `project.yml` and every deployment floor is 26.0.

- [ ] **Step 5: Commit the baseline reconciliation**

```bash
git add apple/Config/Base.xcconfig apple/project.yml apple/Packages/TaisaFoundation/Package.swift apple/Taisa.xcodeproj docs/features/swiftui-native-rebuild.md docs/superpowers/specs/2026-10-03-swift-first-native-rebuild-design.md docs/migration/swiftui/program-ledger.md scripts/native-apple
git commit -m "docs: align native product baseline"
```

### Task 2: Add one coherent encrypted Home query

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Home/HomeSnapshot.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Home/HomeQuery.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/HomeQueryTests.swift`

**Interfaces:**
- Consumes: `TaisaStore.read`, `ConversationRecord`, `GoalRecord`, and `ActionRecord`.
- Produces: `public struct HomeSnapshot: Sendable, Equatable` and `public struct HomeQuery: Sendable` with `public func load(limits: HomeLimits = .default) async throws -> HomeSnapshot`.

- [ ] **Step 1: Write failing query-contract tests**

Define and test these public contracts:

```swift
public struct HomeLimits: Sendable, Equatable {
    public let conversations: Int
    public let goals: Int
    public let actions: Int
    public static let `default` = HomeLimits(conversations: 5, goals: 5, actions: 5)
}

public struct HomeSnapshot: Sendable, Equatable {
    public let conversations: [ConversationRecord]
    public let goals: [GoalRecord]
    public let actions: [ActionRecord]
    public var isEmpty: Bool { conversations.isEmpty && goals.isEmpty && actions.isEmpty }
}
```

Tests must insert active/completed/archived goals, open/completed/archived actions, tombstoned rows, equal timestamps, due and nil-due actions, and more than each limit. Assert:

```swift
#expect(snapshot.conversations.map(\.id) == expectedRecentIDs)
#expect(snapshot.goals.allSatisfy { $0.status == "active" })
#expect(snapshot.actions.allSatisfy { $0.status == "open" })
#expect(snapshot.actions.map(\.id) == expectedDueThenUndatedIDs)
#expect(snapshot.conversations.count == limits.conversations)
```

Add a transaction-coherence test that mutates between separately observable reads and proves `HomeQuery.load` returns one database snapshot, plus an invalid zero/negative limit test that throws a content-free `HomeQueryError.invalidLimit`.

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter HomeQueryTests`

Expected: FAIL because `HomeSnapshot`, `HomeLimits`, and `HomeQuery` do not exist.

- [ ] **Step 3: Implement the bounded read in one `TaisaStore.read` transaction**

Use parameterized GRDB queries, exclude tombstones, add stable ID tie-breaks, decode records before leaving the store boundary, and map database failures to:

```swift
public enum HomeQueryError: Error, Sendable, Equatable {
    case invalidLimit
    case readFailed
}
```

Do not add list methods to every CRUD repository or leak `Row`, `Database`, or SQL into Product targets.

- [ ] **Step 4: Run storage tests**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter HomeQueryTests`

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TaisaStorageTests`

Expected: PASS with deterministic ordering, bounded results, tombstone filtering, coherent reads, and content-free errors.

- [ ] **Step 5: Commit the Home query**

```bash
git add apple/Packages/TaisaFoundation/Sources/TaisaStorage/Home apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/HomeQueryTests.swift
git commit -m "feat: add encrypted Home query"
```

### Task 3: Build the platform-neutral Home model

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaHome/HomeClient.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaHome/HomeState.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaHome/HomeModel.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaHomeTests/HomeModelTests.swift`

**Interfaces:**
- Consumes: `HomeSnapshot` from `TaisaStorage` through an injected closure, not a concrete GRDB type.
- Produces: `HomeClient`, `HomeState`, `HomeIssue`, and `@MainActor @Observable final class HomeModel` for app and preview targets.

- [ ] **Step 1: Declare the target and write failing model tests**

Add `TaisaHome` as a library depending on `TaisaStorage`, and `TaisaHomeTests`. Define:

```swift
public struct HomeClient: Sendable {
    public var load: @Sendable () async throws -> HomeSnapshot
}

public enum HomeIssue: Sendable, Equatable {
    case storageUnavailable
    case recoveryRequired
}

public enum HomeState: Sendable, Equatable {
    case idle
    case loading
    case empty
    case content(HomeSnapshot, isRefreshing: Bool, issue: HomeIssue?)
    case failure(HomeIssue)
}
```

Write tests for first load, empty, content, refresh-with-content, failure without content, failure preserving content, retry, cancellation, and two controlled loads completing newest-first then oldest-last. The final assertion must prove the stale older result is ignored.

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter HomeModelTests`

Expected: FAIL because `TaisaHome` and its contracts do not exist.

- [ ] **Step 3: Implement the minimal observable state machine**

Use `@MainActor`, Observation, one owned `Task`, and a monotonically increasing load generation. `load()` cancels the prior task, retains content during refresh, maps only safe error categories, and checks both cancellation and generation before publishing.

Do not add a generic store, reducer framework, router framework, or dependency container.

- [ ] **Step 4: Run Home and full package tests**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter HomeModelTests`

Run: `cd apple/Packages/TaisaFoundation && swift test`

Expected: PASS.

- [ ] **Step 5: Commit the Home model**

```bash
git add apple/Packages/TaisaFoundation/Package.swift apple/Packages/TaisaFoundation/Sources/TaisaHome apple/Packages/TaisaFoundation/Tests/TaisaHomeTests
git commit -m "feat: model native Home states"
```

### Task 4: Compose the real store and recovery-safe app shell

**Files:**
- Create: `apple/TaisaApp/App/AppRuntime.swift`
- Create: `apple/TaisaApp/App/AppRootView.swift`
- Create: `apple/TaisaApp/Home/HomeView.swift`
- Create: `apple/TaisaApp/Home/HomeSectionViews.swift`
- Modify: `apple/TaisaApp/TaisaApp.swift`
- Modify: `apple/TaisaApp/FoundationRootView.swift`
- Modify: `apple/project.yml`
- Modify: `apple/Taisa.xcodeproj/project.pbxproj` (generated)
- Test: `apple/TaisaUnitTests/AppRuntimeTests.swift`
- Test: `apple/TaisaUnitTests/HomeViewContractTests.swift`

**Interfaces:**
- Consumes: `TaisaStore`, `HomeQuery`, `HomeModel`, and the existing recovery route/backend.
- Produces: `AppRuntime.State`, `AppRootView`, and `HomeView`; ordinary launch uses these instead of `FoundationRootView`.

- [ ] **Step 1: Add package dependencies and failing composition tests**

Add `TaisaHome` to Taisa, TaisaPersonal, TaisaPreview, and relevant test targets in `project.yml`. Test these runtime outcomes:

```swift
XCTAssertEqual(await runtime.start(), .ready)
XCTAssertEqual(await missingKeyRuntime.start(), .recoveryRequired)
XCTAssertEqual(await corruptStoreRuntime.start(), .recoveryRequired)
```

Assert a missing key for an existing store leaves the original file identity and bytes unchanged. Add source-contract tests that require `HomeView` identifiers for root, each section, empty, retry, and recovery while forbidding `import GRDB` in `TaisaApp/Home`.

- [ ] **Step 2: Run focused app tests and verify they fail**

Run: `npm run generate:native-apple`

Run: `xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUnitTests/AppRuntimeTests -only-testing:TaisaUnitTests/HomeViewContractTests`

Expected: FAIL because the runtime, app root, Home view, identifiers, and package linkage do not exist. If that named simulator is unavailable, select the available iPhone using `scripts/native-apple/select-simulator.mjs` as `verify-all.sh` does and record the exact destination.

- [ ] **Step 3: Implement runtime composition and native Home views**

`AppRuntime` creates the same protected application-support namespace and store identity used by recovery, opens the store once, builds `HomeClient { try await HomeQuery(store: store).load() }`, and owns safe recovery routing. Extract the shared store-location factory from `PersonalRecoveryBackend` rather than duplicating path, protection, exclusion-from-backup, installation identity, or interrupted-restore rules.

`AppRootView` switches only among startup, Home, and recovery-required states. `HomeView` uses native `NavigationStack`, `List`/`Section`, `ProgressView`, `ContentUnavailableView`, toolbar actions, `.task`, and `.refreshable` where appropriate. Rows remain feature-local and emit typed intents without fake destination screens.

Keep `FoundationRootView` available only for the explicit development diagnostics route or remove its ordinary-root responsibility without deleting build diagnostics.

- [ ] **Step 4: Regenerate and run focused app tests**

Run: `npm run generate:native-apple`

Run the focused `xcodebuild test` command from Step 2 against the selected simulator.

Expected: PASS; store failures preserve data and ordinary composition exposes Home contracts.

- [ ] **Step 5: Commit the app shell and Home view**

```bash
git add apple/TaisaApp apple/TaisaUnitTests apple/project.yml apple/Taisa.xcodeproj
git commit -m "feat: launch native functional Home"
```

### Task 5: Add deterministic Home preview scenarios

**Files:**
- Create: `apple/TaisaPreview/HomeScenarios.swift`
- Create: `apple/TaisaPreview/HomeScenarioView.swift`
- Modify: `apple/TaisaPreview/FoundationScenarios.swift`
- Modify: `apple/TaisaPreview/PreviewCatalogView.swift`
- Test: `apple/Packages/TaisaFoundation/Tests/TaisaPreviewSupportTests/PreviewRegistryTests.swift`
- Test: `apple/TaisaPreviewUITests/TaisaPreviewCatalogTests.swift`

**Interfaces:**
- Consumes: `HomeModel`, `HomeClient`, and synthetic `HomeSnapshot` values.
- Produces: preview scenarios `home.loading`, `home.empty`, `home.content`, `home.refreshing`, `home.failure`, `home.accessibilityText`, and `home.narrowIPad`.

- [ ] **Step 1: Write failing registry and UI tests**

Require every Home scenario ID exactly once, require `.ready` fixture status, open representative empty/content/failure scenarios, and assert their state-specific accessibility identifiers. Assert the preview transport remains denied and scenario strings contain no production content.

- [ ] **Step 2: Run preview tests and verify they fail**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter PreviewRegistryTests`

Run: `xcodebuild test -quiet -project apple/Taisa.xcodeproj -scheme Taisa-Preview -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' -only-testing:TaisaPreviewUITests/TaisaPreviewCatalogTests`

Expected: FAIL because the Home scenarios are absent. If the named simulator is unavailable, use the selection logic from `verify-all.sh` and record the destination.

- [ ] **Step 3: Implement synthetic Home scenarios**

Construct `HomeModel` with deterministic clients: suspended loading, empty snapshot, populated snapshot, content plus suspended refresh, and typed failure. Use fixed synthetic UUIDs/timestamps and obviously fictional titles. Never open Keychain, SQLCipher, CloudKit, the network, or production recovery storage from preview scenarios.

- [ ] **Step 4: Run package and preview tests**

Run the two focused commands from Step 2, then `npm run verify:native-contracts`.

Expected: PASS.

- [ ] **Step 5: Commit preview coverage**

```bash
git add apple/TaisaPreview apple/TaisaPreviewUITests apple/Packages/TaisaFoundation/Tests/TaisaPreviewSupportTests
git commit -m "test: cover native Home preview states"
```

### Task 6: Prove launch, accessibility, adaptability, and documentation

**Files:**
- Modify: `apple/TaisaUITests/TaisaLaunchTests.swift`
- Modify: `apple/TaisaPreviewUITests/TaisaAccessibilityLayoutTests.swift`
- Create: `docs/qa/swiftui-functional-home-device-matrix.md`
- Modify: `docs/architecture.md`
- Modify: `docs/design-system.md`
- Modify: `docs/migration/swiftui/native-builds.md`
- Modify: `docs/features/swiftui-functional-home.md`
- Modify: `docs/workflow.md`
- Modify: `docs/roadmap.md`

**Interfaces:**
- Consumes: completed runtime, Home states, preview scenarios, and exact-build evidence process.
- Produces: automated launch/accessibility evidence, current architecture/component documentation, and the exact signed-device QA checklist.

- [ ] **Step 1: Replace foundation-launch assertions with failing Home assertions**

Update production UI tests to require `home.root`, native title `Home`, the three section identifiers for populated fixtures, no preview catalog, and continued diagnostics isolation. Add preview UI assertions at accessibility XXXL and narrow iPad width that Retry and recovery remain reachable and essential row titles exist without horizontal scrolling.

- [ ] **Step 2: Run focused UI tests and confirm any missing contract fails**

Run Taisa-Dev UI tests on the selected iPhone simulator and Taisa-Preview accessibility tests on the selected iPad simulator.

Expected: FAIL only for still-missing identifiers or layout behavior; do not weaken assertions to make the tests green.

- [ ] **Step 3: Fix the minimum view semantics and update canonical documentation**

Add semantic headings, accessibility labels/hints, wrapping priorities, readable-width behavior, and non-colour state descriptions required by the tests. Document:

- the shipped `TaisaHome` and feature-local Home presentation boundary;
- standard SwiftUI controls as the native-first default;
- the rule that shared component docs change with implementation;
- iOS 26+ and the local Home read path;
- the signed iPhone/iPad device matrix covering launch, empty/content/failure, refresh, Dynamic Type, VoiceOver, contrast, Reduce Motion, reduced transparency, narrow iPad window, offline behavior, and recovery routing.

Advance the feature to Review + QA only after automated verification passes; leave Ship blocked on Baah's exact-build device approval.

- [ ] **Step 4: Run the complete verification matrix**

Run: `git diff --check`

Run: `npm run verify:native-apple:all`

Run: `npm run verify:workflow`

Expected: all available automated checks pass. Missing simulator or signed-device infrastructure is recorded as missing evidence, never reported as a pass.

- [ ] **Step 5: Commit review readiness**

```bash
git add apple/TaisaUITests apple/TaisaPreviewUITests docs
git commit -m "docs: raise functional Home for device QA"
```

### Task 7: Review and canonical device QA handoff

**Files:**
- Modify after evidence: `docs/qa/swiftui-functional-home-device-matrix.md`
- Modify after evidence: `docs/features/swiftui-functional-home.md`
- Modify after evidence: `docs/migration/swiftui/native-builds.md`

**Interfaces:**
- Consumes: one clean reviewed implementation commit and the repository's signed-build evidence tooling.
- Produces: exact revision/device evidence and a Ship-gate report; it does not merge without Baah's Ship approval.

- [ ] **Step 1: Run independent code review and remediate findings**

Use `superpowers:requesting-code-review` against the complete branch. Fix accepted findings with focused regression tests and rerun the affected checks.

- [ ] **Step 2: Run verification-before-completion on the exact candidate**

Use `superpowers:verification-before-completion`; record the candidate SHA and fresh outputs from `npm run verify:native-apple:all` and workflow verification.

- [ ] **Step 3: Produce and install exact signed Personal builds**

Follow `docs/migration/swiftui/native-builds.md` and the existing signed-build recorder. Do not reuse evidence from another commit. Confirm bundle identity, signer, provisioning profile, embedded commit, environment, entitlements, and authorized devices before installation.

- [ ] **Step 4: Baah performs the Home device matrix**

Run every applicable row on the registered iPhone and iPad. Record failures as QA notes, return the feature to Build, and repeat verification after fixes. Do not mark Ship from simulator evidence.

- [ ] **Step 5: Present the Ship gate**

Report the exact candidate SHA, checks, device/OS matrix, accepted temporary visual decisions, known debt, and remaining out-of-scope work. Wait for explicit Baah Ship approval before merge or branch cleanup.
