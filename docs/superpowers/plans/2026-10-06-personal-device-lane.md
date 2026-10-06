# Personal Device Lane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Proposed — awaiting Baah Plan approval

**Goal:** Install a truthful local-only Swift Taisa build through an Xcode Personal Team and provide recovery-key-encrypted file export/import for deliberate iPhone–iPad transfer.

**Architecture:** A separate generated `TaisaPersonal` app target and `Taisa-Personal` scheme reuse the native app and encrypted local packages without linking `TaisaCloudKit` or declaring paid capabilities. A new `TaisaRecovery` package creates a chunked authenticated archive from a consistent SQLCipher checkpoint and restores only through a fully validated candidate store; a thin SwiftUI document flow owns Files/AirDrop interaction and explicit replacement confirmation.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing/XCTest, XcodeGen 2.46.0, SQLCipher/GRDB 7.11.1, CryptoKit AES-GCM/HKDF, Security Keychain Services, UniformTypeIdentifiers, system file importer/exporter.

**Spec:** `docs/superpowers/specs/2026-10-06-personal-device-lane-design.md`

## Global Constraints

- Support iOS 17+ on iPhone and iPad.
- Use the stable Personal bundle identifier `com.taisa.app.personal`.
- The Personal product has no iCloud, CloudKit, push, Associated Domains, or remote-notification capability and does not link `TaisaCloudKit`.
- Development and Production CloudKit identities and entitlements remain unchanged; Preview remains fake-only.
- Personal status is local-only and never reports fake synchronization success.
- Archives are database-only, exclude audio, use the generated Taisa recovery key, and never contain plaintext content, database keys, or recovery material.
- Restore validates a candidate completely before explicit confirmation and atomic promotion; every failure preserves the active store and Keychain key.
- Manual transfer replaces one device state; it does not merge divergent histories.
- No Apple portal mutation, production CloudKit schema promotion, App Store upload, or React Native change is authorized by this plan.

## Review Focus

- Re-signing the same Personal bundle must preserve the app container; identity drift must fail project verification.
- A Personal binary or plist containing any CloudKit symbol/capability must fail isolation checks.
- Pending audio work must reject export before an archive file is published.
- Truncated, reordered, duplicated, or tampered archive chunks must fail authentication while preserving the active store.
- Restore interruption before or during promotion must recover the original store and original Keychain key on relaunch.

---

### Task 1: Generate an isolated Personal app identity

**Files:**
- Create: `apple/Config/Personal.xcconfig`
- Create: `apple/Config/TaisaPersonal.entitlements`
- Create: `apple/TaisaPersonalTests/PersonalIsolationTests.swift`
- Modify: `apple/project.yml`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaCore/TaisaEnvironment.swift`
- Modify: `apple/Packages/TaisaFoundation/Tests/TaisaCoreTests/TaisaEnvironmentTests.swift`
- Modify: `scripts/native-apple/verify.mjs`
- Modify: `scripts/native-apple/__tests__/verify.test.mjs`
- Modify: `scripts/native-apple/verify-all.sh`
- Modify: `package.json`

**Interfaces:**
- Consumes: `TaisaApp` sources, generated build metadata, `TaisaCore`, `TaisaContracts`, `TaisaDesignSystem`, `TaisaStorage`, and `TaisaSecurity`.
- Produces: `TaisaEnvironment.personal`, `TaisaPersonal` app target, `Taisa-Personal` scheme, and `inspectNativeProject(...).personalIsolation`.

- [ ] **Step 1: Write failing environment and project-isolation tests**

Add a Swift test asserting `TaisaEnvironment(configurationValue: "personal") == .personal`, `allowsFixtures == false`, and `allowsLiveCloudTransport == false`. Extend the Node verifier expectation to include:

```js
personal: {
  bundleIdentifier: 'com.taisa.app.personal',
  entitlementKeys: [],
  linksLiveTransport: false,
  configuresBackgroundMode: false,
  archiveEnabled: false,
}
```

Assert the existing development/production entitlement objects are byte-for-byte unchanged by fixture mutation tests.

- [ ] **Step 2: Run RED**

Run:

```bash
cd apple/Packages/TaisaFoundation && swift test --filter TaisaEnvironmentTests
cd ../../../ && node --test scripts/native-apple/__tests__/verify.test.mjs
```

Expected: FAIL because `.personal`, the config, target, scheme, and verifier fields do not exist.

- [ ] **Step 3: Implement the minimal Personal target and scheme**

Add:

```swift
public enum TaisaEnvironment: String, Codable, Sendable {
    case development, preview, personal, production

    public var allowsFixtures: Bool { self == .preview }
    public var allowsLiveCloudTransport: Bool {
        self == .development || self == .production
    }
}
```

Use `Personal.xcconfig` with `PRODUCT_BUNDLE_IDENTIFIER = com.taisa.app.personal`, `TAISA_ENVIRONMENT = personal`, and `TAISA_PERSONAL` compilation condition. Generate `TaisaPersonal` from `TaisaApp` plus `Generated`, link no `TaisaCloudKit`, bind an empty `TaisaPersonal.entitlements`, generate an Info.plist without `UIBackgroundModes`, and expose a non-archiving `Taisa-Personal` scheme with its own unit-test host.

- [ ] **Step 4: Prove project and built-product isolation**

Run:

```bash
npm run generate:native-apple
npm run verify:native-apple
xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Personal -configuration Personal -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Inspect the built app with `codesign -d --entitlements :-`, `plutil`, and `otool -L`; expect no iCloud/push/Associated Domains keys, no remote-notification background mode, and no `TaisaCloudKit` product or CloudKit framework linkage attributable to app code.

- [ ] **Step 5: Commit**

```bash
git add apple package.json scripts/native-apple
git commit -m "feat: add isolated personal device build"
```

### Task 2: Expose truthful local-only runtime capability

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaCore/SyncCapability.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaCoreTests/SyncCapabilityTests.swift`
- Modify: `apple/TaisaApp/FoundationRootView.swift`
- Modify: `apple/TaisaUnitTests/CloudKitIsolationTests.swift`
- Modify: `apple/TaisaPersonalTests/PersonalIsolationTests.swift`

**Interfaces:**
- Consumes: `TaisaEnvironment` from Task 1.
- Produces: `SyncCapability.forEnvironment(_:) -> SyncCapability` with `.localOnly`, `.fakePreview`, and `.privateCloudKit` cases.

- [ ] **Step 1: Write failing capability and copy tests**

Test the exact mapping:

```swift
#expect(SyncCapability.forEnvironment(.personal) == .localOnly)
#expect(SyncCapability.forEnvironment(.preview) == .fakePreview)
#expect(SyncCapability.forEnvironment(.development) == .privateCloudKit)
#expect(SyncCapability.forEnvironment(.production) == .privateCloudKit)
```

The Personal-hosted test must assert that its bundle maps to `.personal`, the displayed status is `Stored securely on this device`, and `CloudKitRuntimeConfiguration.containerIdentifier(for:)` returns nil for `com.taisa.app.personal`.

- [ ] **Step 2: Run RED**

Run `cd apple/Packages/TaisaFoundation && swift test --filter SyncCapabilityTests` and the Personal simulator test target. Expected: FAIL because `SyncCapability` and the local-only status do not exist.

- [ ] **Step 3: Implement capability selection without a fake sync engine**

Add:

```swift
public enum SyncCapability: Equatable, Sendable {
    case localOnly
    case fakePreview
    case privateCloudKit

    public static func forEnvironment(_ environment: TaisaEnvironment) -> Self {
        switch environment {
        case .personal: .localOnly
        case .preview: .fakePreview
        case .development, .production: .privateCloudKit
        }
    }
}
```

Render the Personal-only status copy from this value. Do not instantiate `InMemorySyncTransport` for Personal and do not add a successful/up-to-date sync state.

- [ ] **Step 4: Run GREEN and commit**

Run the focused package tests, Personal hosted tests, `npm run verify:native-apple`, and unsigned Personal build. Then commit:

```bash
git add apple
git commit -m "feat: report truthful personal storage status"
```

### Task 3: Create authenticated portable snapshot archives

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaRecovery/SnapshotManifest.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaRecovery/PortableArchive.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaRecovery/SnapshotService.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaRecoveryTests/SnapshotTests.swift`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaStore.swift`

**Interfaces:**
- Consumes: an open `TaisaStore`, `RecoveryKey`, an `AudioExportGuard`, destination URL, clock, and capacity policy.
- Produces: `SnapshotService.createPortableArchive(at:recoveryKey:) async throws -> SnapshotReceipt` and versioned `.taisa-backup` files.

- [ ] **Step 1: Write failing archive contract tests**

Define fixtures for representative repository rows and assert deterministic manifest counts and plaintext SHA-256. Test pending-audio rejection before destination creation, wrong recovery key, modified header, reordered/duplicated/missing 1 MiB chunks, nonce uniqueness, no audio paths, no plaintext canary, and cleanup after cancellation or disk failure.

- [ ] **Step 2: Run RED**

Run `cd apple/Packages/TaisaFoundation && swift test --filter SnapshotTests`. Expected: FAIL because `TaisaRecovery` does not exist.

- [ ] **Step 3: Add the recovery package and exact archive format**

Define:

```swift
public struct SnapshotManifest: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let schemaVersion: Int
    public let createdAt: Date
    public let sourceInstallationID: UUID
    public let plaintextByteCount: Int64
    public let plaintextSHA256: Data
    public let entityCounts: [String: Int]
    public let chunkCount: Int
}

public protocol AudioExportGuard: Sendable {
    func assertNoPendingAudioReferences() async throws
}

public struct SnapshotReceipt: Equatable, Sendable {
    public let archiveURL: URL
    public let manifest: SnapshotManifest
}
```

The binary format is magic `TAISABK1`, a canonical encrypted manifest, a random 32-byte salt, and ordered frames. From `RecoveryKey` plus that salt, derive separate 32-byte keys with HKDF-SHA256 contexts `taisa.portable-backup.frames.v1` and `taisa.portable-backup.database.v1`; key separation prevents a framed-archive operation from being reused as a SQLCipher operation. Seal each frame independently with AES-GCM and associated data binding format version, archive ID, chunk index, total count, and manifest digest. Write to a mode-0600 sibling temporary file, `fsync`, verify by reopening, then atomically rename to the chosen destination.

Add a `TaisaStore.exportCheckpoint(to:archiveDatabaseKey:)` boundary that holds store lifecycle ownership, checkpoints WAL, uses GRDB backup into a fresh SQLCipher database keyed by the random archive database key, and returns authenticated counts/hash metadata without exposing key bytes in descriptions or errors.

- [ ] **Step 4: Run GREEN, mutation checks, and commit**

Run snapshot tests and disposable mutations that remove chunk-index AAD, skip the audio guard, and publish before verification; each mutation must fail tests. Run the full Swift suite, then commit:

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: create portable encrypted snapshots"
```

### Task 4: Validate and atomically restore a candidate store

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaRecovery/RestoreCoordinator.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaRecovery/RestoreJournal.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaRecoveryTests/RestoreTests.swift`
- Modify: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaStore.swift`

**Interfaces:**
- Consumes: archive URL, `RecoveryKey`, active-store URL, `DatabaseKeyStore`, free-space provider, and explicit replacement callback.
- Produces: `RestoreCoordinator.validate(...) -> RestoreCandidate` and `promote(_:confirmReplacement:) async throws -> RestoreReceipt`.

- [ ] **Step 1: Write failing restore and crash-matrix tests**

Cover correct/wrong key, truncated/tampered archive, future format/schema, invalid counts/hash, less than `2 × archive size + 100 MB` free space, declined confirmation, active handles, and interruption after every journal phase. Assert active database bytes and original Keychain key remain unchanged for every pre-commit failure. Assert relaunch rolls back an interrupted exchange or completes cleanup after a committed promotion.

- [ ] **Step 2: Run RED**

Run `cd apple/Packages/TaisaFoundation && swift test --filter RestoreTests`. Expected: FAIL because restore types are absent.

- [ ] **Step 3: Implement candidate validation and durable promotion**

Define:

```swift
public struct RestoreCandidate: Sendable {
    public let directory: URL
    public let databaseURL: URL
    public let databaseKey: Data
    public let manifest: SnapshotManifest
}

public enum RestorePhase: String, Codable, Sendable {
    case prepared, originalMoved, candidateMoved, keyCommitted, committed
}
```

Decrypt into a mode-0700 candidate directory, verify every frame and manifest digest, derive the archive database key with the Task 3 context, and open the candidate with an in-memory key store. Run SQLCipher integrity, migration preflight, entity counts, and hash checks, then rekey the candidate to a newly generated device-local 32-byte key before requesting confirmation. Promotion records each phase in a mode-0600 journal, closes active handles through the store lifecycle, moves the original aside, moves the candidate into place, saves the new device-local candidate key, reopens and integrity-checks, and only then marks committed. Recovery uses the phase plus filesystem state to restore the original database and original Keychain key whenever commit was not proven; the derived archive database key is never persisted to Keychain.

- [ ] **Step 4: Run GREEN, mutation checks, and commit**

Mutate confirmation, key ordering, and journal recovery one at a time and require tests to fail. Run all recovery and storage tests plus the full Swift suite. Commit:

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: restore encrypted snapshots atomically"
```

### Task 5: Add Files/AirDrop export and restore UI

**Files:**
- Create: `apple/TaisaApp/Recovery/RecoveryView.swift`
- Create: `apple/TaisaApp/Recovery/RecoveryViewModel.swift`
- Create: `apple/TaisaApp/Recovery/TaisaBackupDocument.swift`
- Create: `apple/TaisaUnitTests/RecoveryViewModelTests.swift`
- Modify: `apple/TaisaApp/FoundationRootView.swift`
- Modify: `apple/project.yml`

**Interfaces:**
- Consumes: `SnapshotService`, `RestoreCoordinator`, recovery-key ceremony, SwiftUI `fileExporter`/`fileImporter`, and local-only capability.
- Produces: **Back Up Now**, **Export Encrypted Backup**, and **Restore Backup** flows for Personal builds.

- [ ] **Step 1: Write failing view-model tests**

Test idle/creating/export-ready/import-selected/validating/confirmation/restoring/success/failure states; double-tap suppression; cancellation cleanup; wrong-key retry; replacement warning; divergent-device warning; and redaction when the scene becomes inactive. Copy must say `Stored securely on this device` and `Restoring replaces this device’s current Taisa data`; it must never say synced, merged, or uploaded.

- [ ] **Step 2: Run RED**

Run the Recovery view-model unit tests. Expected: FAIL because the recovery flow is absent.

- [ ] **Step 3: Implement the system document flow**

Use a UTType exported as `com.taisa.encrypted-backup` with extension `.taisa-backup`. `fileExporter` receives only a verified archive; `fileImporter` copies security-scoped input into a private temporary directory before validation. Disable repeated actions while busy, require device authentication before accepting the recovery key, require explicit replacement confirmation, and remove temporary plaintext/candidate material on every terminal path.

- [ ] **Step 4: Run UI/accessibility checks and commit**

Run unit tests and simulator UI checks for iPhone, narrow iPad, Dynamic Type, VoiceOver order, reduced motion, background shielding, cancellation, and error recovery. Commit:

```bash
git add apple/TaisaApp apple/TaisaUnitTests apple/project.yml
git commit -m "feat: add encrypted backup transfer flow"
```

### Task 6: Verify, sign, install, and document the weekly refresh path

**Files:**
- Modify: `docs/migration/swiftui/native-builds.md`
- Modify: `docs/migration/swiftui/cloudkit-schema.md`
- Modify: `docs/features/swift-native-encrypted-sync.md`
- Modify: `docs/workflow.md`
- Modify: `docs/roadmap.md`

**Interfaces:**
- Consumes: Tasks 1–5 and Baah's Personal Team selected in Xcode.
- Produces: exact automated evidence, signed build records, weekly refresh instructions, and physical-device QA record without claiming live sync.

- [ ] **Step 1: Run the complete automated matrix**

Run:

```bash
cd apple/Packages/TaisaFoundation && swift test
cd ../../../ && npm run verify:native-apple:all
xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Personal -configuration Personal -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Also build Dev Debug, Production Release, and Preview to prove their existing isolation still holds. Scan all products for entitlement, linkage, fixture, plaintext-canary, and recovery-key leakage.

- [ ] **Step 2: Request the external signing gate**

Before contacting Apple or installing, show the exact command, bundle ID `com.taisa.app.personal`, selected Personal Team ID, and both device identifiers. Baah's approval authorizes Personal provisioning/install only; it does not authorize CloudKit capability creation, schema promotion, App Store actions, deletion of an installed app, or production installation.

- [ ] **Step 3: Install without deleting and verify weekly-refresh persistence**

Build/sign `Taisa-Personal`, install over the same bundle identifier on iPhone and iPad, create a canary record, rebuild/reinstall, and verify the record remains. Export from the authoritative device, AirDrop/Files-transfer it, restore on the receiving device, verify representative counts/hash, force-quit/reopen, and confirm both devices remain local-only with no CloudKit traffic.

- [ ] **Step 4: Review and update canonical documentation**

Use `superpowers:requesting-code-review`, resolve blocking findings, then use `superpowers:verification-before-completion` and rerun the complete matrix. Document the seven-day signing limitation, “reinstall over; never delete” procedure, backup safety warning, no-merge limitation, signed build/profile evidence, and the still-deferred CloudKit acceptance criterion.

- [ ] **Step 5: Commit the verified closeout**

```bash
git add docs
git commit -m "docs: verify personal device recovery lane"
```

Stop at Review + QA. PR creation, merge, branch cleanup, production CloudKit schema promotion, and Ship require Baah's separate approval.
