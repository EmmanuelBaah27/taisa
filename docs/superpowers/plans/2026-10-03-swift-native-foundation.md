# Swift Native Foundation Part 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a reproducible SwiftUI iPhone/iPad project, production-isolated preview catalog, portable transcription contract fixtures, build identity, native design-system seed, automated verification, and signed development builds on Baah's iPhone and iPad.

**Architecture:** A committed XcodeGen specification and generated Xcode project define separate `Taisa` and `TaisaPreview` applications. Focused local Swift-package targets provide core identity, API contracts, semantic design tokens, and preview support; the production target cannot import the preview module. The first runnable shell proves project structure, signing, previews, contract decoding, accessibility, and exact-build traceability while deferring encrypted persistence and audio hardware work to subsequent foundation plans.

**Tech Stack:** Xcode 26.1.1, Swift 6.2.1, SwiftUI, Observation, Swift Testing/XCTest, XCUITest, XcodeGen 2.46.0, Node.js built-in test runner, TypeScript contract sources, JSON fixtures

**Spec:** `docs/superpowers/specs/2026-10-03-swift-first-native-rebuild-design.md`

## Global Constraints

- Target iOS and iPadOS 17 or later; do not add macOS, watchOS, visionOS, Android, or web targets.
- Keep the Node/Express gateway and `shared/` TypeScript contracts unchanged except for portable fixture generation or validation required by this plan.
- The React Native application is reference evidence only and is not modified by this plan.
- Use bundle ID `com.taisa.app` for production Release, `com.taisa.app.dev` for development, and `com.taisa.app.preview` for the preview catalog.
- `TaisaPreview` is development-only and must not archive or appear in production dependencies, resources, symbols, routes, or bundle strings.
- Product views consume typed values and components from `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/`; unapproved raw visual values fail verification.
- Preview fixtures use synthetic data, deterministic clocks and identifiers, temporary or in-memory storage only, and deny external networking.
- Diagnostics contain no transcripts, prompts, profile content, recordings, keys, or decrypted archives.
- Every implementation or bug fix follows test-first development where an executable test is practical.
- A simulator build does not satisfy device QA. Completion requires exact signed builds installed and launched on the registered iPhone and iPad.
- This plan does not select or implement SQLCipher, recording, streaming transport, notifications, biometrics, export/restore, Navii rendering, or shaders. Those receive separate approved foundation plans.
- Do not delete or rewrite React Native branches, worktrees, evidence, or user changes.

## File Structure

- Create `apple/project.yml` — authoritative XcodeGen targets, settings, package dependencies, and shared schemes.
- Create `apple/Taisa.xcodeproj/` — generated, committed project output; never hand-edit it.
- Create `apple/Config/Base.xcconfig`, `Debug.xcconfig`, `Preview.xcconfig`, and `Release.xcconfig` — deployment, bundle, signing, and environment settings.
- Create `apple/scripts/generate-project.sh` — enforce XcodeGen version and regenerate the project.
- Create `apple/scripts/verify-project.sh` — verify regeneration, schemes, bundle IDs, archive policy, target membership, and preview isolation.
- Create `apple/scripts/generate-build-metadata.sh` — generate content-free build identity from Git and build settings.
- Create `apple/Packages/TaisaFoundation/Package.swift` — local package manifest.
- Create `apple/Packages/TaisaFoundation/Sources/TaisaCore/` — environment and build-identity value types.
- Create `apple/Packages/TaisaFoundation/Sources/TaisaContracts/` — Codable API envelopes and transcription stream events.
- Create `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/` — semantic tokens and foundation components.
- Create `apple/Packages/TaisaFoundation/Sources/TaisaPreviewSupport/` — deterministic fixture contracts available only to the preview target.
- Create corresponding package tests under `apple/Packages/TaisaFoundation/Tests/`.
- Create `apple/TaisaApp/` — production composition root and adaptive foundation screen.
- Create `apple/TaisaPreview/` — preview-only composition root and scenario browser.
- Create `apple/TaisaUITests/` — launch, identity, accessibility, and production-isolation smoke tests.
- Create `shared/fixtures/transcription/` — portable valid and invalid NDJSON/JSON event fixtures.
- Create `scripts/native-contracts/verify-transcription-fixtures.mjs` and tests — validate fixtures against the TypeScript runtime guard.
- Create `scripts/native-apple/verify.mjs` and tests — repository-level native structure and isolation checks.
- Create `.github/workflows/native-apple.yml` — generation, contract, package, simulator, and UI-test checks.
- Create `docs/product-contracts/native-foundation.md` — platform-neutral shell, identity, fixture, and adaptation contract.
- Create `docs/migration/swiftui/native-builds.md` — exact signed-build evidence.

## Review Focus

- A Release archive must never contain `TaisaPreviewSupport`, fixture IDs, synthetic profiles, or the preview bundle identifier; Tasks 1, 5, and 8 verify source membership and built-product strings.
- A dirty or detached Git checkout must still produce explicit, truthful build identity rather than claiming a clean branch; Tasks 3 and 8 test these forms.
- Unknown transcription event types and malformed completed events must fail decoding without accepting partial data; Task 6 tests valid and invalid cross-language fixtures.
- Accessibility sizes and iPad split widths must not clip or hide build diagnostics or the foundation action; Tasks 4 and 7 add preview and UI coverage.
- Regenerating the Xcode project must be deterministic and must not erase signing, schemes, test targets, or source exclusions; Tasks 1 and 8 compare generated output.

---

### Task 1: Create the reproducible Xcode project and enforce target isolation

**Files:**
- Create: `apple/project.yml`
- Create: `apple/Config/Base.xcconfig`
- Create: `apple/Config/Debug.xcconfig`
- Create: `apple/Config/Preview.xcconfig`
- Create: `apple/Config/Release.xcconfig`
- Create: `apple/scripts/generate-project.sh`
- Create: `apple/scripts/verify-project.sh`
- Create: `scripts/native-apple/verify.mjs`
- Create: `scripts/native-apple/__tests__/verify.test.mjs`
- Create: `apple/TaisaApp/TaisaApp.swift`
- Create: `apple/TaisaApp/FoundationRootView.swift`
- Create: `apple/TaisaPreview/TaisaPreviewApp.swift`
- Create: `apple/TaisaPreview/PreviewRootView.swift`
- Create: generated `apple/Taisa.xcodeproj/`
- Modify: `.gitignore`
- Modify: `package.json`

**Interfaces:**
- Produces: schemes `Taisa-Dev`, `Taisa-Preview`, and `Taisa`
- Produces: app targets `Taisa` and `TaisaPreview`
- Produces: `npm run generate:native-apple` and `npm run verify:native-apple`
- Consumes later: local package products added in Task 2

- [ ] **Step 1: Write failing repository-isolation tests**

```javascript
test('declares distinct production, development, and preview identities', async () => {
  const result = await inspectNativeProject(fixtureRoot);
  assert.deepEqual(result.bundleIdentifiers, {
    production: 'com.taisa.app',
    development: 'com.taisa.app.dev',
    preview: 'com.taisa.app.preview',
  });
});

test('production target excludes preview sources and support product', async () => {
  const result = await inspectNativeProject(fixtureRoot);
  assert.deepEqual(result.productionPreviewLeaks, []);
  assert.equal(result.previewArchiveEnabled, false);
});
```

- [ ] **Step 2: Run RED**

Run: `node --test scripts/native-apple/__tests__/verify.test.mjs`

Expected: FAIL because the native project specification and verifier do not exist.

- [ ] **Step 3: Add deterministic XcodeGen configuration**

`project.yml` defines iOS 17, Swift 6, separate application targets, unit/UI tests, explicit source membership, shared schemes, and Release archiving only for `Taisa`. Require XcodeGen `2.46.0` exactly so generated project diffs are reproducible. The generator exits with an installation instruction when that version is absent; installation is a user-authorized toolchain action, not an implicit script side effect.

- [ ] **Step 4: Generate and commit the project**

Run: `cd apple && ./scripts/generate-project.sh`

Expected: `apple/Taisa.xcodeproj` is generated with the three shared schemes and no user-specific workspace data.

- [ ] **Step 5: Verify target isolation**

Run: `node --test scripts/native-apple/__tests__/verify.test.mjs && npm run verify:native-apple`

Expected: PASS; preview sources and dependencies appear only in `TaisaPreview`.

- [ ] **Step 6: Verify both app targets build**

Run: `xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Dev -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build`

Run: `xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Preview -configuration Preview -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' CODE_SIGNING_ALLOWED=NO build`

Expected: both commands finish with `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add .gitignore package.json apple scripts/native-apple
git commit -m "build: bootstrap native Apple project"
```

### Task 2: Establish focused Swift module boundaries

**Files:**
- Create: `apple/Packages/TaisaFoundation/Package.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaCore/TaisaEnvironment.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaCore/TaisaError.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaContracts/APIEnvelope.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaDesignSystem.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaPreviewSupport/PreviewCapability.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaCoreTests/TaisaEnvironmentTests.swift`
- Modify: `apple/project.yml`

**Interfaces:**
- Produces: `TaisaEnvironment: String, Codable, Sendable` with `.development`, `.preview`, and `.production`
- Produces: package products `TaisaCore`, `TaisaContracts`, `TaisaDesignSystem`, and `TaisaPreviewSupport`
- Enforces: `TaisaPreviewSupport` is linked only by `TaisaPreview`

- [ ] **Step 1: Write failing package tests**

```swift
@Test func environmentRejectsUnknownConfiguration() {
    #expect(throws: TaisaEnvironmentError.self) {
        try TaisaEnvironment(configurationValue: "staging")
    }
}

@Test func productionIsNotFixtureCapable() {
    #expect(TaisaEnvironment.production.allowsFixtures == false)
}
```

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test`

Expected: FAIL because the package and types do not exist.

- [ ] **Step 3: Implement the package and strict environment parsing**

```swift
public enum TaisaEnvironment: String, Codable, Sendable {
    case development
    case preview
    case production

    public var allowsFixtures: Bool { self == .preview }
}
```

The throwing initializer accepts only the three exact build-setting values. It never silently falls back to development.

- [ ] **Step 4: Link package products with one-way dependencies**

`Taisa` links Core, Contracts, and DesignSystem. `TaisaPreview` links those products plus PreviewSupport. Package targets never import an application target.

- [ ] **Step 5: Run package and isolation checks**

Run: `cd apple/Packages/TaisaFoundation && swift test`

Run: `npm run verify:native-apple`

Expected: PASS and no production dependency on PreviewSupport.

- [ ] **Step 6: Commit**

```bash
git add apple/Packages apple/project.yml apple/Taisa.xcodeproj
git commit -m "feat: define native foundation modules"
```

### Task 3: Generate truthful build identity and diagnostics

**Files:**
- Create: `apple/scripts/generate-build-metadata.sh`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaCore/BuildIdentity.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaCoreTests/BuildIdentityTests.swift`
- Create: `apple/TaisaApp/BuildDiagnosticsView.swift`
- Modify: `apple/project.yml`

**Interfaces:**
- Produces: `BuildIdentity(gitCommit: String, gitBranch: String?, isDirty: Bool, buildNumber: String, bundleIdentifier: String, environment: TaisaEnvironment, contractRevision: String)`
- Produces: generated `apple/Generated/BuildMetadata.generated.swift`
- Production behavior: diagnostics are reachable only in Debug/Preview builds

- [ ] **Step 1: Write failing identity tests**

```swift
@Test func detachedDirtyBuildRemainsExplicit() {
    let identity = BuildIdentity(
        gitCommit: "abc123", gitBranch: nil, isDirty: true,
        buildNumber: "7", bundleIdentifier: "com.taisa.app.dev",
        environment: .development, contractRevision: "fixtures-v1"
    )
    #expect(identity.sourceDescription == "abc123 (detached, dirty)")
}
```

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter BuildIdentityTests`

Expected: FAIL because `BuildIdentity` does not exist.

- [ ] **Step 3: Implement content-free build metadata generation**

The script uses argument arrays and `git rev-parse`/`git status --porcelain`; it does not interpolate Git output into shell commands. It writes only commit, branch/detached state, dirty flag, build number, environment, bundle ID, and contract revision.

- [ ] **Step 4: Add development diagnostics**

`BuildDiagnosticsView` presents the exact values as selectable text with accessibility labels. Production compilation excludes the route and generated development details with `#if DEBUG || TAISA_PREVIEW`.

- [ ] **Step 5: Verify clean, dirty, and detached fixtures**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter BuildIdentityTests`

Run: `node --test scripts/native-apple/__tests__/verify.test.mjs`

Expected: PASS for clean branch, dirty branch, and detached fixture repositories.

- [ ] **Step 6: Commit**

```bash
git add apple
git commit -m "feat: expose native build identity"
```

### Task 4: Seed the native design system and adaptive foundation shell

**Files:**
- Create: `docs/product-contracts/design-tokens.json`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/ColorToken.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/SpacingToken.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TypographyToken.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaText.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaButton.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaDesignSystemTests/TokenTests.swift`
- Create: `scripts/native-apple/verify-design-system.mjs`
- Create: `scripts/native-apple/__tests__/verify-design-system.test.mjs`
- Modify: `apple/TaisaApp/FoundationRootView.swift`
- Modify: `package.json`

**Interfaces:**
- Produces: typed semantic roles for background, foreground, muted foreground, primary action, borders, spacing, and foundation typography
- Produces: `TaisaText(role:color:content:)` and `TaisaButton(role:label:action:)`
- Produces: `npm run verify:native-design-system`

- [ ] **Step 1: Write failing token and lint tests**

```swift
@Test func primaryActionUsesPortableContractValue() {
    #expect(TaisaColor.primaryAction.hex == "#CDEC1A")
}
```

```javascript
test('feature views contain no raw color literals', async () => {
  assert.deepEqual(await rawVisualValues('apple/TaisaApp'), []);
});
```

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TokenTests`

Run: `node --test scripts/native-apple/__tests__/verify-design-system.test.mjs`

Expected: FAIL because tokens and verifier do not exist.

- [ ] **Step 3: Define the portable seed tokens**

Copy only the semantic roles required by the foundation shell from `mobile/design-system/tokens.json` into the platform-neutral contract. Normalize hex casing and document that the portable JSON, not NativeWind classes, is the cross-platform value source.

- [ ] **Step 4: Implement typed Swift tokens and components**

Use Dynamic Type text styles, minimum 44-point interaction targets, semantic foreground styles, and accessibility labels. Add previews for iPhone, iPad split width, accessibility extra-extra-extra-large text, increased contrast, and reduced transparency.

- [ ] **Step 5: Build the adaptive shell**

The shell shows the Taisa identity, a concise “Native foundation ready” state, environment badge in non-production builds, and one accessible action opening diagnostics. It uses readable width constraints on iPad rather than scaling phone geometry.

- [ ] **Step 6: Verify**

Run: `cd apple/Packages/TaisaFoundation && swift test`

Run: `npm run verify:native-design-system`

Expected: PASS with no raw visual values in app views.

- [ ] **Step 7: Commit**

```bash
git add docs/product-contracts/design-tokens.json apple scripts/native-apple package.json
git commit -m "feat(ds): seed native design system"
```

### Task 5: Build the production-isolated native preview catalog

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaPreviewSupport/PreviewScenario.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaPreviewSupport/PreviewRegistry.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaPreviewSupport/DeniedNetworkTransport.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaPreviewSupportTests/PreviewRegistryTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaPreviewSupportTests/DeniedNetworkTransportTests.swift`
- Create: `apple/TaisaPreview/PreviewCatalogView.swift`
- Create: `apple/TaisaPreview/FoundationScenarios.swift`
- Modify: `apple/TaisaPreview/TaisaPreviewApp.swift`
- Modify: `scripts/native-apple/verify.mjs`

**Interfaces:**
- Produces: `PreviewScenario` with String identifier, title, device family, accessibility settings, readiness state, and an `@MainActor @Sendable () -> AnyView` root-view factory
- Produces: exhaustive `PreviewRegistry` with unique stable identifiers
- Produces: `DeniedNetworkTransport.send(_:) async throws` that always fails before transmission

- [ ] **Step 1: Write failing registry and transport tests**

```swift
@Test func registryRejectsDuplicateIdentifiers() {
    #expect(throws: PreviewRegistryError.duplicateIdentifier("foundation.default")) {
        try PreviewRegistry(scenarios: [fixture, fixture])
    }
}

@Test func transportNeverStartsARequest() async {
    await #expect(throws: PreviewTransportError.externalNetworkingDenied) {
        try await DeniedNetworkTransport().send(.fixture)
    }
}
```

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter PreviewSupportTests`

Expected: FAIL because the preview support types do not exist.

- [ ] **Step 3: Implement deterministic preview support**

The foundation registry includes default, accessibility-text, narrow-iPad, reduced-motion, increased-contrast, and diagnostics scenarios. Scenario selection reconstructs dependencies so state never leaks between fixtures.

- [ ] **Step 4: Implement the catalog UI**

The preview app lists searchable scenario names, displays current appearance requirements, opens the selected scenario, and exposes a stable readiness accessibility identifier. It contains only synthetic copy.

- [ ] **Step 5: Expand production-isolation verification**

Reject any PreviewSupport dependency, preview source membership, fixture identifier, or `com.taisa.app.preview` string in the built production Release bundle.

- [ ] **Step 6: Verify**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter PreviewSupportTests`

Run: `npm run verify:native-apple`

Run: `xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Expected: PASS; built production scan reports no preview leakage.

- [ ] **Step 7: Commit**

```bash
git add apple scripts/native-apple
git commit -m "feat: add native preview catalog"
```

### Task 6: Establish portable transcription contract fixtures

**Files:**
- Create: `shared/fixtures/transcription/delta.valid.json`
- Create: `shared/fixtures/transcription/completed-clear.valid.json`
- Create: `shared/fixtures/transcription/completed-uncertain.valid.json`
- Create: `shared/fixtures/transcription/no-speech.valid.json`
- Create: `shared/fixtures/transcription/failed.valid.json`
- Create: `shared/fixtures/transcription/unknown-type.invalid.json`
- Create: `shared/fixtures/transcription/completed-empty.invalid.json`
- Create: `scripts/native-contracts/verify-transcription-fixtures.mjs`
- Create: `scripts/native-contracts/__tests__/verify-transcription-fixtures.test.mjs`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaContracts/TranscriptionStreamEvent.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaContractsTests/TranscriptionStreamEventTests.swift`
- Modify: `package.json`

**Interfaces:**
- Consumes: `shared/types/transcription.ts::isTranscriptionStreamEvent`
- Produces: strict Codable `TranscriptionStreamEvent` cases `delta`, `completed`, `noSpeech`, and `failed`
- Produces: `npm run verify:native-contracts`

- [ ] **Step 1: Write failing TypeScript-side fixture tests**

```javascript
test('all valid fixtures satisfy the runtime guard', async () => {
  assert.deepEqual(await invalidValidFixtures(fixturesRoot), []);
});

test('all invalid fixtures are rejected by the runtime guard', async () => {
  assert.deepEqual(await acceptedInvalidFixtures(fixturesRoot), []);
});
```

- [ ] **Step 2: Write failing Swift decoding tests**

```swift
@Test(arguments: validFixtureURLs)
func decodesEveryCanonicalFixture(_ url: URL) throws {
    _ = try JSONDecoder().decode(TranscriptionStreamEvent.self, from: Data(contentsOf: url))
}

@Test(arguments: invalidFixtureURLs)
func rejectsEveryInvalidFixture(_ url: URL) {
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(TranscriptionStreamEvent.self, from: Data(contentsOf: url))
    }
}
```

- [ ] **Step 3: Run RED**

Run: `node --test scripts/native-contracts/__tests__/verify-transcription-fixtures.test.mjs`

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TranscriptionStreamEventTests`

Expected: FAIL because fixtures and Swift event types do not exist.

- [ ] **Step 4: Implement strict cross-language fixtures and decoder**

The Swift decoder rejects unknown types, extra required-envelope errors, invalid UUIDs, negative sequences/costs, empty completed transcripts, non-positive duration, and unknown failure codes. Unknown optional response fields may be ignored only where the TypeScript guard also permits them.

- [ ] **Step 5: Verify both languages**

Run: `npm run verify:native-contracts`

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TranscriptionStreamEventTests`

Expected: both validators agree on every valid and invalid fixture.

- [ ] **Step 6: Commit**

```bash
git add shared/fixtures scripts/native-contracts apple/Packages/TaisaFoundation package.json
git commit -m "test: synchronize native transcription contracts"
```

### Task 7: Add native UI smoke tests for iPhone and iPad

**Files:**
- Create: `apple/TaisaUITests/TaisaLaunchTests.swift`
- Create: `apple/TaisaUITests/TaisaPreviewCatalogTests.swift`
- Create: `apple/TaisaUITests/TaisaAccessibilityLayoutTests.swift`
- Modify: `apple/project.yml`

**Interfaces:**
- Consumes: accessibility identifiers `foundation.root`, `foundation.diagnostics`, `preview.catalog`, and `preview.ready.<scenario>`
- Produces: simulator evidence for launch, diagnostics identity, scenario readiness, large text, and compact iPad width

- [ ] **Step 1: Write failing launch and isolation UI tests**

```swift
func testProductionDevelopmentShellLaunchesWithoutPreviewCatalog() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.otherElements["foundation.root"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.otherElements["preview.catalog"].exists)
}
```

- [ ] **Step 2: Run RED**

Run: `xcodebuild test -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TaisaUITests`

Expected: FAIL until identifiers and test target wiring are complete.

- [ ] **Step 3: Add preview readiness and adaptive-layout coverage**

Launch the preview target with `-TAISAPreviewScenario foundation.accessibilityText` and assert its readiness identifier. Run large content size on iPhone and a compact split-view width on iPad; assert the title, primary action, and diagnostics remain hittable and do not horizontally scroll.

- [ ] **Step 4: Run iPhone and iPad tests**

Run: `xcodebuild test -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Run: `xcodebuild test -project apple/Taisa.xcodeproj -scheme Taisa-Preview -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'`

Expected: PASS on both simulator families.

- [ ] **Step 5: Commit**

```bash
git add apple
git commit -m "test: cover native foundation flows"
```

### Task 8: Make native verification reproducible in CI

**Files:**
- Create: `.github/workflows/native-apple.yml`
- Create: `scripts/native-apple/verify-generated-project.sh`
- Modify: `scripts/native-apple/verify.mjs`
- Modify: `scripts/native-apple/__tests__/verify.test.mjs`
- Modify: `scripts/verify-workflow.sh`
- Modify: `package.json`

**Interfaces:**
- Produces: `npm run verify:native-apple:all`
- Produces: CI artifacts for test results and simulator screenshots without readable user data

- [ ] **Step 1: Add failing verification tests**

Test that native verification fails for a changed generated project, missing shared scheme, Release preview dependency, missing fixture validation, absent design-system verification, and an unexpanded build-identity placeholder.

- [ ] **Step 2: Run RED**

Run: `node --test scripts/native-apple/__tests__/*.test.mjs`

Expected: FAIL until the combined verifier and workflow checks exist.

- [ ] **Step 3: Implement the combined verification command**

`verify:native-apple:all` runs:

```text
project regeneration diff
repository isolation tests
portable contract fixture tests
Swift package tests
native design-system verification
Taisa-Dev simulator build/test
Taisa-Preview simulator build/test
Taisa Release build and preview-leak scan
workflow verification
```

The generation-diff check runs in a temporary directory or restores only generated files proven clean before the check. It never discards user changes.

- [ ] **Step 4: Add CI**

Use the `macos-26` runner, select `/Applications/Xcode_26.1.1.app`, assert build `17B100`, and install XcodeGen `2.46.0`. Cache only tool/dependency downloads, not generated project output. Upload `.xcresult` bundles on failure.

- [ ] **Step 5: Run the complete local gate**

Run: `npm run verify:native-apple:all`

Expected: PASS with zero production preview leaks and no generated-project drift.

- [ ] **Step 6: Commit**

```bash
git add .github package.json scripts apple
git commit -m "ci: verify native Apple foundation"
```

### Task 9: Install exact signed builds on the registered iPhone and iPad

**Files:**
- Create: `docs/product-contracts/native-foundation.md`
- Create: `docs/migration/swiftui/native-builds.md`
- Create: `apple/scripts/record-signed-build.mjs`
- Create: `apple/scripts/__tests__/record-signed-build.test.mjs`
- Modify: `docs/workflow.md`
- Modify: `docs/roadmap.md`

**Interfaces:**
- Consumes: registered device UDIDs and the exact committed native revision
- Produces: signed build records with commit, dirty state, Xcode/build number, bundle ID, environment, contract revision, device, OS, install result, launch result, and tester confirmation

- [ ] **Step 1: Write failing signed-build record tests**

```javascript
test('rejects a record whose installed commit differs from the candidate', () => {
  assert.match(validateSignedBuild({
    candidateCommit: 'abc', installedCommit: 'def',
  }).join('\n'), /installed commit differs/);
});
```

- [ ] **Step 2: Run RED**

Run: `node --test apple/scripts/__tests__/record-signed-build.test.mjs`

Expected: FAIL because the record tool does not exist.

- [ ] **Step 3: Document the portable foundation contract**

Record shell purpose, visible states, copy, accessibility roles, adaptive-layout requirements, build identity fields, preview isolation, fixture revision, and deliberate Apple-only behavior. This becomes the reusable source for a future React Native shell.

- [ ] **Step 4: Run the full gate and commit the candidate**

Run: `npm run verify:native-apple:all`

Expected: PASS. Commit any generated evidence before signing so the installed Git revision is immutable and the worktree is clean.

- [ ] **Step 5: Build and install Taisa-Dev on both devices**

Run signed `xcodebuild` commands with automatic provisioning for:

- iPhone 15 Pro UDID `00008130-000834AA34C2001C`
- iPad Pro 11-inch (4th generation) UDID `00008112-000C25CA0107401E`

Install and launch the resulting `com.taisa.app.dev` app with `xcrun devicectl`. Do not overwrite or delete the existing React Native production app.

- [ ] **Step 6: Build and install TaisaPreview on both devices**

Install and launch `com.taisa.app.preview`. Confirm the catalog identifies the exact commit and opens the default, accessibility-text, and narrow-iPad scenarios.

- [ ] **Step 7: Record exact-build evidence**

Run the record tool against `xcrun devicectl device info` and build metadata. Reject dirty builds, mismatched commits, wrong bundle IDs, or missing launch confirmation.

- [ ] **Step 8: Stop for Baah device QA**

Ask Baah to confirm on both devices:

- Taisa Dev launches the foundation shell and cannot open the preview catalog.
- Taisa Preview launches the scenario catalog.
- text remains readable at the tested accessibility size;
- iPad layout is centered and readable rather than stretched;
- diagnostics show the stated commit, build number, environment, and fixture revision.

Do not mark the foundation accepted until both devices match the signed records.

- [ ] **Step 9: Commit evidence**

```bash
git add docs/product-contracts/native-foundation.md docs/migration/swiftui/native-builds.md apple/scripts docs/workflow.md docs/roadmap.md
git commit -m "docs: verify signed native foundation"
```

## Foundation acceptance

This plan is complete only when:

- project regeneration is deterministic;
- production, development, and preview identities are isolated;
- package, contract, design-system, simulator, UI, Release isolation, and workflow checks pass;
- the exact clean revision is signed, installed, and launched on the registered iPhone and iPad;
- Baah confirms the recorded builds on both devices;
- the next foundation plans are explicitly listed as encrypted persistence/recovery, audio/streaming, and advanced resources/platform services.

Approval of this plan does not authorize those later foundation plans or any Product slice.
