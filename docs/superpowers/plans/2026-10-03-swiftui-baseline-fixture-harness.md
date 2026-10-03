# SwiftUI Baseline Fixture Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a physical-device, development-only React Native fixture target that reproduces all 65 SwiftUI parity states without exposing fixture behavior in production Taisa.

**Architecture:** A separate `TaisaBaseline` iOS target and `baseline/index.tsx` entry reuse production presentation through typed interfaces. An exhaustive fixture registry supplies deterministic in-memory services and readiness markers; capture tooling rejects revision, metadata, hash, setting, and production-isolation drift.

**Tech Stack:** Expo SDK 54, React Native 0.81, TypeScript 5.9, Expo Router, Zustand, Jest, Node test runner, Xcode 26, `xcodebuild`, `xcrun devicectl`, Metro.

**Spec:** `docs/superpowers/specs/2026-10-03-swiftui-baseline-fixture-harness-design.md`

## Global Constraints

- Implement in an isolated feature worktree based on the exact canonical `preview/taisa` candidate; never develop on `main` or directly in the canonical preview worktree.
- Preserve all user changes and existing worktrees.
- `TaisaBaseline` uses bundle ID `com.taisa.app.baseline`, scheme `TaisaBaseline`, display name `Taisa Baseline`, URL scheme `taisa-baseline`, and Debug-only distribution.
- Production `Taisa` must not import, route to, bundle, or expose fixture modules, IDs, markers, synthetic profiles, or the baseline URL scheme.
- Baseline adapters must not access production storage, biometrics, notifications, archives, microphone, or non-loopback network destinations.
- Registry and Markdown catalog must contain exactly one matching definition for every `PC-001` through `PC-065`.
- Static capture waits for `baseline:ready:<PC-NNN>`; motion capture spans `baseline:motion-start:<PC-NNN>` through `baseline:motion-complete:<PC-NNN>`.
- Media is limited to 10 MB per file and 100 MB in-repository total. External evidence requires Baah-approved durable storage and resolvable hashes.
- Physical iPhone and iPad evidence is required; simulator evidence is diagnostic only.
- Performance uses Release production `Taisa`, never `TaisaBaseline`, with at least five runs per device.
- Any candidate revision change invalidates capture until builds, manifests, and evidence are regenerated.
- Follow TDD for implementation and fixes; diagnose failures before changing code.
- The next Baah gate after execution is baseline-freeze approval, not Ship approval.

## Review Focus

- Release production archives must remain free of baseline modules and strings; Task 1 adds source, scheme, target-membership, and built-bundle scans.
- Consecutive fixture selections must not retain store, clock, animation, or repository state; Task 2 tests reconstruction and disposal.
- External requests must fail before transmitting content; Task 3 tests deny-by-default transport.
- Accessibility-setting drift or device reconnects must invalidate capture batches; Task 7 tests batch epochs and appearance records.
- Catalog or candidate revision mismatch must stop capture before accepting media; Tasks 6 and 7 enforce both.

---

### Task 1: Create and enforce the isolated native target

**Files:**
- Create: `mobile/baseline/index.tsx`
- Create: `mobile/baseline/UnavailableBaselineRoot.tsx`
- Create: `mobile/ios/TaisaBaseline/Info.plist`
- Create: `mobile/ios/TaisaBaseline/TaisaBaseline.entitlements`
- Create: `mobile/ios/Taisa.xcodeproj/xcshareddata/xcschemes/TaisaBaseline.xcscheme`
- Create: `mobile/scripts/verify-baseline-isolation.mjs`
- Create: `mobile/scripts/__tests__/verify-baseline-isolation.test.mjs`
- Modify: `mobile/ios/Taisa.xcodeproj/project.pbxproj`
- Modify: `mobile/ios/Taisa/AppDelegate.swift`
- Modify: `mobile/package.json`

**Interfaces:**
- Consumes: existing `Taisa` target and Expo bundle URL behavior
- Produces: `TaisaBaseline`, compile condition `TAISA_BASELINE`, bundle root `baseline/index`, and `verify:baseline-isolation`

- [ ] **Step 1: Write failing target-isolation tests**

```js
test('production target has no baseline source, scheme, or bundle strings', async () => {
  assert.deepEqual((await verifyBaselineIsolation(project)).productionLeaks, []);
});

test('baseline target is distinct and Debug-only', async () => {
  assert.deepEqual((await verifyBaselineIsolation(project)).baselineTarget, {
    bundleIdentifier: 'com.taisa.app.baseline', displayName: 'Taisa Baseline',
    scheme: 'taisa-baseline', releaseArchiveEnabled: false,
  });
});
```

- [ ] **Step 2: Run RED**

Run: `cd mobile && node --test scripts/__tests__/verify-baseline-isolation.test.mjs`  
Expected: FAIL because the verifier and target do not exist.

- [ ] **Step 3: Implement the verifier and minimal target**

The verifier parses project membership, shared schemes, bundle identifiers, compile conditions, URL schemes, and built production bundle strings. AppDelegate selects `baseline/index` only inside `#if TAISA_BASELINE`; the normal target keeps the Expo Router entry.

- [ ] **Step 4: Verify GREEN**

Run: `cd mobile && node --test scripts/__tests__/verify-baseline-isolation.test.mjs && npm run verify:baseline-isolation`  
Expected: PASS.

Run: `cd mobile && xcodebuild -workspace ios/Taisa.xcworkspace -scheme Taisa -configuration Debug -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO`  
Expected: BUILD SUCCEEDED.

Run: `cd mobile && xcodebuild -workspace ios/Taisa.xcworkspace -scheme TaisaBaseline -configuration Debug -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO`  
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add mobile/baseline mobile/ios mobile/scripts mobile/package.json
git commit -m "build: isolate baseline capture target"
```

### Task 2: Define fixture contracts, selection, reset, and readiness

**Files:**
- Create: `mobile/src/baseline/contracts.ts`
- Create: `mobile/src/baseline/fixtureController.ts`
- Create: `mobile/src/baseline/BaselineRoot.tsx`
- Create: `mobile/src/baseline/__tests__/fixtureController.test.ts`
- Modify: `mobile/baseline/index.tsx`

**Interfaces:**
- Consumes: launch arguments and baseline-only deep links
- Produces: `BaselineFixtureDefinition`, `BaselineDependencies`, `BaselineMotionScript`, `createFixtureController()`, and readiness/error markers

- [ ] **Step 1: Write failing controller tests**

```ts
test('unknown ids never construct dependencies', () => {
  expect(createFixtureController(registry).select('PC-999'))
    .toEqual({ status: 'error', code: 'unknown-fixture' });
});

test('reselecting a fixture creates a clean container', () => {
  const controller = createFixtureController(registry);
  const first = controller.select('PC-008');
  first.dependencies.clock.advance(5000);
  const second = controller.select('PC-008');
  expect(second.dependencies).not.toBe(first.dependencies);
  expect(second.dependencies.clock.now()).toBe('2026-10-03T00:00:00.000Z');
});
```

- [ ] **Step 2: Run RED**

Run: `cd mobile && npm test -- --runInBand src/baseline/__tests__/fixtureController.test.ts`  
Expected: FAIL because the controller is missing.

- [ ] **Step 3: Implement minimal contracts and controller**

Selection accepts only the catalog range, checks device compatibility, disposes the previous container, constructs a new container, and emits exact `booting`, `ready`, `motion-start`, `motion-complete`, or `error` markers.

- [ ] **Step 4: Verify GREEN**

Run: `cd mobile && npm test -- --runInBand src/baseline/__tests__/fixtureController.test.ts && npm run typecheck`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/baseline mobile/src/baseline
git commit -m "feat: define deterministic baseline fixture controller"
```

### Task 3: Build deterministic deny-by-default adapters

**Files:**
- Create: `mobile/src/baseline/dependencies.ts`
- Create: `mobile/src/baseline/frozenClock.ts`
- Create: `mobile/src/baseline/inMemoryRepositories.ts`
- Create: `mobile/src/baseline/scriptedServices.ts`
- Create: `mobile/src/baseline/syntheticContent.ts`
- Create: `mobile/src/baseline/__tests__/dependencies.test.ts`

**Interfaces:**
- Consumes: production domain types and typed capability interfaces
- Produces: `createBaselineDependencies(seed): BaselineDependencies` with deterministic repositories, coaching, transcription, privacy, notification, archive, authentication, and recorder adapters

- [ ] **Step 1: Write failing determinism and network tests**

```ts
test('independent containers serialize identically', () => {
  expect(snapshot(createBaselineDependencies('fixture.home.attention')))
    .toEqual(snapshot(createBaselineDependencies('fixture.home.attention')));
});

test('external transport fails before dispatch', async () => {
  const deps = createBaselineDependencies('fixture.coaching.text');
  await expect(deps.transport.post('https://api.taisa.example/v1', { private: true }))
    .rejects.toMatchObject({ code: 'baseline-network-denied' });
  expect(deps.transport.sentBodies).toEqual([]);
});
```

- [ ] **Step 2: Run RED**

Run: `cd mobile && npm test -- --runInBand src/baseline/__tests__/dependencies.test.ts`  
Expected: FAIL because adapters are missing.

- [ ] **Step 3: Implement adapters**

Use stable IDs, frozen time, synthetic strings, in-memory archive results, scripted audio descriptors, and transport that permits loopback diagnostics only. It must never initialize production database, coaching, notification, biometric, archive-file, or microphone services.

- [ ] **Step 4: Verify GREEN**

Run: `cd mobile && npm test -- --runInBand src/baseline/__tests__/dependencies.test.ts && npm run typecheck`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/baseline
git commit -m "feat: add synthetic baseline dependencies"
```

### Task 4: Extract shared shell, onboarding, Home, Chats, and Me views

**Files:**
- Create: `mobile/src/screens/AppShellView.tsx`
- Create: `mobile/src/screens/OnboardingView.tsx`
- Create: `mobile/src/screens/HomeView.tsx`
- Create: `mobile/src/screens/ChatsView.tsx`
- Create: `mobile/src/screens/MeView.tsx`
- Create: `mobile/src/screens/__tests__/baselinePrimaryViews.test.tsx`
- Modify: `mobile/app/_layout.tsx`
- Modify: `mobile/app/onboarding/index.tsx`
- Modify: `mobile/app/(tabs)/index.tsx`
- Modify: `mobile/app/(tabs)/chats.tsx`
- Modify: `mobile/app/(tabs)/you.tsx`
- Modify: `mobile/src/baseline/BaselineRoot.tsx`

**Interfaces:**
- Consumes: serializable view state and callbacks derived by production containers or baseline adapters
- Produces: pure shared views for `PC-001`–`PC-019` and `PC-044`–`PC-052`

- [ ] **Step 1: Write failing shared-view tests**

```ts
test.each(['initializing', 'privacy-locked', 'privacy-recovery'])('renders shell %s', (state) => {
  expect(renderShellFixture(state).toJSON()).toMatchSnapshot();
});

test('production Home route delegates to HomeView', () => {
  expect(readRoute('app/(tabs)/index.tsx')).toMatch(/<HomeView/);
});
```

- [ ] **Step 2: Run RED**

Run: `cd mobile && npm test -- --runInBand src/screens/__tests__/baselinePrimaryViews.test.tsx`  
Expected: FAIL because shared views are missing.

- [ ] **Step 3: Extract presentation without changing production behavior**

Route containers retain hydration, repositories, navigation, and side effects. Shared views receive typed state and callbacks. Baseline callbacks mutate only the current fixture controller.

- [ ] **Step 4: Verify GREEN and regressions**

Run: `cd mobile && npm test -- --runInBand src/screens/__tests__/baselinePrimaryViews.test.tsx src/navigation/__tests__/localCaptureRoutes.test.ts src/navigation/__tests__/onboardingFields.test.ts src/services/__tests__/privacyGuard.test.ts src/services/__tests__/exportArchive.test.ts`  
Expected: PASS.

Run: `cd mobile && npm run typecheck && npm run verify:design-system`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/app mobile/src/screens mobile/src/baseline
git commit -m "refactor: share primary journey presentation"
```

### Task 5: Extract shared coaching, conversation, voice, motion, and platform views

**Files:**
- Create: `mobile/src/screens/CoachingView.tsx`
- Create: `mobile/src/screens/ConversationView.tsx`
- Create: `mobile/src/screens/RecordingView.tsx`
- Create: `mobile/src/screens/__tests__/baselineCaptureViews.test.tsx`
- Create: `mobile/src/baseline/systemSettings.ts`
- Modify: `mobile/app/chat/index.tsx`
- Modify: `mobile/app/thread/[id].tsx`
- Modify: `mobile/app/recording/index.tsx`
- Modify: `mobile/app/(tabs)/_layout.tsx`
- Modify: `mobile/src/hooks/useVoiceRecorder.ts`
- Modify: `mobile/src/baseline/BaselineRoot.tsx`

**Interfaces:**
- Consumes: scripted coaching, transcript, recorder, proposal, accessibility, keyboard, rotation, and viewport state
- Produces: shared views and named actions for `PC-020`–`PC-043` and `PC-053`–`PC-065`

- [ ] **Step 1: Write failing state and motion tests**

```ts
test.each(['clear', 'uncertain', 'no-speech', 'transcription-failed'])('renders voice %s', (state) => {
  expect(renderVoiceFixture(state).toJSON()).toMatchSnapshot();
});

test('real transition is bracketed by motion markers', async () => {
  expect(await runMotion('PC-055', 'close-chat-card')).toEqual([
    'baseline:motion-start:PC-055', 'baseline:motion-complete:PC-055',
  ]);
});

test.each([1024, 744, 507])('keeps primary action reachable at width %d', (width) => {
  expect(renderIPadFixture('multitasking', width).getByLabelText('Primary capture action')).toBeTruthy();
});
```

- [ ] **Step 2: Run RED**

Run: `cd mobile && npm test -- --runInBand src/screens/__tests__/baselineCaptureViews.test.tsx`  
Expected: FAIL because shared capture views and platform adapters are missing.

- [ ] **Step 3: Extract and inject capabilities**

Production routes retain real side effects. `RecordingView` receives a recorder presentation model; baseline uses scripted amplitude, interruption, cleanup, and post-Send events without microphone access. Accessibility fixtures block readiness unless actual system flags match. Rotation and width use real window dimensions and preserve semantic selection/scroll IDs.

- [ ] **Step 4: Verify GREEN and regressions**

Run: `cd mobile && npm test -- --runInBand src/screens/__tests__/baselineCaptureViews.test.tsx src/services/__tests__/privateCapture.test.ts src/services/__tests__/audio.test.ts src/navigation/__tests__/conversationResume.test.ts`  
Expected: PASS.

Run: `cd mobile && npm run typecheck && npm run verify:design-system`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/app mobile/src/screens mobile/src/hooks mobile/src/baseline
git commit -m "refactor: share capture and platform presentation"
```

### Task 6: Register and verify all 65 fixtures

**Files:**
- Create: `mobile/src/baseline/fixtureRegistry.ts`
- Create: `mobile/src/baseline/__tests__/fixtureRegistry.test.ts`
- Create: `mobile/scripts/verify-baseline-catalog.mjs`
- Create: `mobile/scripts/__tests__/verify-baseline-catalog.test.mjs`
- Modify: `mobile/package.json`
- Modify: `docs/migration/swiftui/parity-catalog.md`

**Interfaces:**
- Consumes: Tasks 2–5 fixture builders and parity catalog
- Produces: `baselineFixtureRegistry: ReadonlyMap<CatalogId, BaselineFixtureDefinition>` and `verify:baseline-catalog`

- [ ] **Step 1: Write failing bijection tests**

```ts
test('contains PC-001 through PC-065 exactly once', () => {
  expect([...baselineFixtureRegistry.keys()]).toEqual(expectedCatalogIds);
});

test('fixture, devices, and capture kind match Markdown', async () => {
  expect(await compareCatalogToRegistry()).toEqual([]);
});
```

- [ ] **Step 2: Run RED**

Run: `cd mobile && npm test -- --runInBand src/baseline/__tests__/fixtureRegistry.test.ts`  
Expected: FAIL because the exhaustive registry is missing.

Run: `cd mobile && node --test scripts/__tests__/verify-baseline-catalog.test.mjs`  
Expected: FAIL because the verifier is missing.

- [ ] **Step 3: Add every definition without generic fallback rendering**

Each definition declares fixture ID, route, devices, static or motion capture, ready marker, and named motion action when required.

- [ ] **Step 4: Verify GREEN and full mobile suite**

Run: `cd mobile && npm test -- --runInBand src/baseline/__tests__/fixtureRegistry.test.ts && npm run verify:baseline-catalog && npm run verify:baseline-isolation`  
Expected: PASS with 65 definitions.

Run: `cd mobile && npm test -- --runInBand && npm run typecheck && npm run verify:design-system && npm run verify:button-surfaces`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/baseline mobile/scripts mobile/package.json docs/migration/swiftui/parity-catalog.md
git commit -m "feat: register SwiftUI parity fixtures"
```

### Task 7: Implement capture batching, hashes, and evidence verification

**Files:**
- Create: `scripts/swiftui-baseline/media.mjs`
- Create: `scripts/swiftui-baseline/__tests__/media.test.mjs`
- Create: `scripts/swiftui-baseline/capture-device.mjs`
- Create: `docs/migration/swiftui/reference-media/README.md`
- Create: `docs/migration/swiftui/reference-media/manifest.json`
- Modify: `scripts/swiftui-baseline/capture.mjs`
- Modify: `scripts/swiftui-baseline/verify.mjs`
- Modify: `scripts/swiftui-baseline/__tests__/verify.test.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: canonical commit, catalog revision, device metadata, system settings, readiness markers, media files
- Produces: `validateMediaManifest()`, `refreshMediaHashes()`, atomic capture batches, and spec-compliant manifest records

- [ ] **Step 1: Write failing evidence tests**

```js
test('rejects media from another candidate', async () => {
  assert.match(validate(record({ commit: 'wrong' })), /candidate commit mismatch/);
});

test('invalidates appearance or connection changes inside a batch', () => {
  assert.match(validateBatch([first, changedAppearance]), /batch settings changed/);
});

test('rejects wrong hashes, size excess, and unresolved external storage', async () => {
  assert.deepEqual(await validateMediaManifest(invalidManifest), expectedErrors);
});
```

- [ ] **Step 2: Run RED**

Run: `node --test scripts/swiftui-baseline/__tests__/media.test.mjs scripts/swiftui-baseline/__tests__/verify.test.mjs`  
Expected: FAIL for missing media validation.

- [ ] **Step 3: Implement capture and validation**

The driver accepts no file before its marker, records exact physical device and settings, never creates placeholder evidence, and writes atomically. `--refresh-media-hashes` hashes declared existing files only.

- [ ] **Step 4: Verify GREEN and expected pre-capture failure**

Run: `node --test scripts/swiftui-baseline/__tests__/*.test.mjs`  
Expected: PASS.

Run: `npm run capture:swiftui-baseline -- --candidate=origin/preview/taisa --refresh-media-hashes`  
Expected before capture: non-zero with only missing media listed and no status mutation.

- [ ] **Step 5: Commit**

```bash
git add scripts/swiftui-baseline package.json docs/migration/swiftui/reference-media
git commit -m "feat: validate SwiftUI baseline evidence"
```

### Task 8: Integrate the verified harness into canonical preview

**Files:**
- Modify: `docs/migration/swiftui/baseline-manifest.json`
- Modify: `docs/migration/swiftui/program-ledger.md`
- Modify: `docs/workflow.md`
- Modify: this plan's ignored execution ledger

**Interfaces:**
- Consumes: clean verified feature branch and clean canonical `preview/taisa`
- Produces: one pushed preview revision containing the harness and no unrelated feature work

- [ ] **Step 1: Run pre-integration gates**

Run: `cd mobile && npm test -- --runInBand && npm run typecheck && npm run verify:design-system && npm run verify:button-surfaces && npm run verify:baseline-catalog && npm run verify:baseline-isolation`  
Expected: PASS.

Run: `npm run verify:workflow && git diff --check`  
Expected: PASS.

- [ ] **Step 2: Review the feature range**

Resolve the base from the execution ledger, then run `git diff --stat BASE..HEAD` and `git log --oneline BASE..HEAD`. Expected: only harness, presentation-boundary, tests, and Program 0 documentation.

- [ ] **Step 3: Integrate, verify, and push**

Stop if canonical preview is dirty, diverged, or differs from `origin/preview/taisa`. Integrate without force-push/history rewrite, rerun Step 1 from the preview worktree, push `preview/taisa`, and confirm local/remote SHAs match.

- [ ] **Step 4: Regenerate candidate evidence**

Run: `npm run capture:swiftui-baseline -- --candidate=origin/preview/taisa`  
Expected: manifest advances to the exact pushed revision and dispositions remain resolved.

- [ ] **Step 5: Commit documentation**

```bash
git add docs/migration/swiftui/baseline-manifest.json docs/migration/swiftui/program-ledger.md docs/workflow.md
git commit -m "docs: advance SwiftUI baseline candidate"
```

### Task 9: Capture all physical-device reference media

**Files:**
- Create: all files enumerated by `docs/migration/swiftui/reference-media/manifest.json`
- Modify: `docs/migration/swiftui/reference-media/manifest.json`
- Modify: `docs/migration/swiftui/parity-catalog.md`

**Interfaces:**
- Consumes: exact pushed candidate, signed baseline builds, physical iPhone/iPad, fixtures
- Produces: hashed evidence for every required catalog/device combination

- [ ] **Step 1: Build and install exact signed revision**

Build `TaisaBaseline` on the agreed iPhone and iPad. Record Xcode, device, OS, build number, commit, bundle ID, and viewport. Stop on any mismatch.

- [ ] **Step 2: Capture static states**

Launch each catalog ID, wait for its exact ready marker, verify settings, capture, and record metadata immediately. Add iPad evidence for shell, navigation, modal/popover, keyboard, rotation, and multitasking rows.

- [ ] **Step 3: Capture motion states**

Start recording before the named action, require `motion-start`, perform only the scripted action, require `motion-complete`, then stop. Discard timeouts, crashes, setting drift, disconnects, and improvised sequences.

- [ ] **Step 4: Hash and verify**

Run: `npm run capture:swiftui-baseline -- --candidate=origin/preview/taisa --refresh-media-hashes`  
Expected: all artifacts hash with no stale commit/metadata.

Run: `npm run verify:swiftui-baseline`  
Expected at this stage: no media errors; performance evidence may remain pending.

- [ ] **Step 5: Commit**

```bash
git add docs/migration/swiftui/reference-media docs/migration/swiftui/parity-catalog.md
git commit -m "docs: capture React Native parity references"
```

### Task 10: Record Release performance evidence

**Files:**
- Create: `docs/migration/swiftui/performance-baseline.md`
- Create: `docs/migration/swiftui/performance/raw/iphone.json`
- Create: `docs/migration/swiftui/performance/raw/ipad.json`
- Modify: `scripts/swiftui-baseline/verify.mjs`
- Modify: `scripts/swiftui-baseline/__tests__/verify.test.mjs`

**Interfaces:**
- Consumes: Release production `Taisa` at canonical candidate and controlled synthetic archive
- Produces: five-or-more raw runs per metric/device plus recomputed median and worst case

- [ ] **Step 1: Write failing completeness tests**

```js
test('requires five runs per device and metric', async () => {
  assert.match(await verifyPerformance(incomplete), /requires at least 5 runs/);
});

test('recomputes summary from raw observations', () => {
  assert.deepEqual(summarize([10, 30, 20, 50, 40]), { median: 30, worst: 50 });
});
```

- [ ] **Step 2: Run RED**

Run: `node --test scripts/swiftui-baseline/__tests__/verify.test.mjs`  
Expected: FAIL because performance completeness is not verified.

- [ ] **Step 3: Implement schema and verifier**

Require device, OS, build, commit, tool, raw values, unit, directionality, median, worst case, and caveats for each spec metric.

- [ ] **Step 4: Measure five Release runs on each device**

Measure cold/warm launch; Home, long Chats, and conversation memory; database open and representative queries; scrolling/navigation frame stability; tap-to-record; stop-to-first-transcript; clear-result-to-coaching-start; installed size; and exported archive size. Record thermal and environmental deviations.

- [ ] **Step 5: Verify and commit**

Run: `npm run verify:swiftui-baseline`  
Expected: PASS for sources, catalog, media, metadata, and performance.

```bash
git add docs/migration/swiftui/performance-baseline.md docs/migration/swiftui/performance scripts/swiftui-baseline
git commit -m "docs: record React Native performance baseline"
```

### Task 11: Prepare the baseline freeze approval gate

**Files:**
- Modify: `docs/migration/swiftui/baseline-manifest.json`
- Modify: `docs/migration/swiftui/program-ledger.md`
- Modify: `docs/workflow.md`
- Modify: `docs/superpowers/plans/2026-10-02-swiftui-program-0-baseline-freeze.md`

**Interfaces:**
- Consumes: verified candidate, resolved sources, exhaustive media, completed performance
- Produces: review-ready freeze manifest and explicit Baah approval request

- [ ] **Step 1: Write and observe failing freeze-integrity test**

Test that `status: frozen` is rejected unless every source is resolved, every catalog row is captured, all media validates, performance is complete, and candidate equals `origin/preview/taisa`.

Run: `node --test scripts/swiftui-baseline/__tests__/verify.test.mjs`  
Expected: FAIL until freeze rules exist.

- [ ] **Step 2: Implement freeze rules and closeout**

Record actual outcome, deviations, candidate change, Expo AV migration concern, evidence locations, remaining debt, and next Program 1 gate.

- [ ] **Step 3: Run complete verification**

Run: `node --test scripts/swiftui-baseline/__tests__/*.test.mjs`  
Expected: PASS.

Run: `cd mobile && npm test -- --runInBand && npm run typecheck && npm run verify:design-system && npm run verify:button-surfaces && npm run verify:baseline-catalog && npm run verify:baseline-isolation`  
Expected: PASS.

Run: `npm run verify:swiftui-baseline && npm run verify:workflow && git diff --check`  
Expected: PASS.

- [ ] **Step 4: Whole-branch review and one fix pass**

Review production isolation, determinism, catalog coverage, evidence provenance, performance calculations, and deviations. Fix Critical/Important findings with RED→GREEN; ledger Minor findings.

- [ ] **Step 5: Commit review-ready freeze**

```bash
git add docs scripts mobile
git commit -m "docs: prepare SwiftUI baseline freeze"
```

- [ ] **Step 6: Request Baah baseline-freeze approval**

Present the candidate revision, verification results, device/OS matrix, media count/size, performance summary, deviations, and debt. Do not set `status: frozen`, tag, push a freeze tag, begin Program 1, merge, or delete branches before explicit approval.
