# Swift Native Encrypted Storage, Sync, and Recovery Implementation Plan

**Status:** Shipped through the approved Personal device lane in PR #12 (`8c22c7b`); live CloudKit activation remains deferred pending paid Apple capabilities and separate approval.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build private offline-first native storage that synchronizes end-to-end encrypted career data between Baah's iPhone and iPad and restores it safely with a user-held recovery key.

**Architecture:** Product features use typed repositories over a device-encrypted SQLCipher store. A transactional outbox feeds authenticated encrypted envelopes into a transport-neutral sync engine; Apple's `CKSyncEngine` implements the first private-CloudKit transport, while a separate snapshot service provides bounded disaster recovery.

**Tech Stack:** Swift 6, Swift Testing/XCTest, XcodeGen 2.46.0, SQLCipher's managed GRDB Swift package 7.11.1, SQLCipher.swift resolved and locked by SwiftPM, CryptoKit AES-GCM/HKDF, Security Keychain Services, AuthenticationServices Passwords API with iOS availability fallback, CloudKit private custom zones, `CKSyncEngine`, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-10-04-swift-native-encrypted-sync-design.md`

## Global Constraints

- Support iOS 17+, iPhone and iPad; use iOS 26 Passwords APIs only behind `#available` and provide a manual-save confirmation flow on older supported systems.
- The shipped native foundation at `444d239` is the required predecessor; do not merge this work ahead of that foundation.
- Never write private content, keys, recovery material, plaintext entity IDs, titles, messages, or transcripts to CloudKit metadata, logs, diagnostics, notifications, screenshots, or test artifacts.
- The device SQLCipher key is random, Keychain-protected, and never synchronized; the random vault key is separately wrapped by recovery-key-derived material.
- Use only CryptoKit and SQLCipher cryptographic primitives; no custom cipher, nonce construction, or password-based KDF.
- A local transaction commits product state and its outbox entry together; cloud availability never gates local save.
- Preview and automated fixtures must use an in-memory/fake transport and must never access a real CloudKit container.
- Development, preview, and production identities remain isolated; the React Native production app and data are never overwritten.
- Database backup/sync excludes recorded and temporary audio.
- Same-field conflicts preserve both values; no silent last-write-wins.
- Unknown key, integrity, account, schema, or restore state fails closed without replacing readable local data.
- Every product-facing SwiftUI surface consumes `TaisaDesignSystem`; no storage/network/business logic enters the design-system module.
- External Apple Developer/App Store Connect mutations and CloudKit production-schema promotion require a separate Baah approval at Task 7.

## Review Focus

- **Apple Account changes while unsent local work exists:** local data and outbox remain preserved, sync locks to an account-changed state, and no new vault is created automatically (Task 6 tests).
- **A removed device that still possesses an old vault key:** ordinary removal is not called cryptographic revocation; remove-and-rotate remains incomplete until every current cloud payload is re-encrypted and verified (Task 8 tests).
- **Recovery key saved in Passwords under different OS capabilities:** iOS 26 uses the preferred credential manager; iOS 17–25 requires explicit copy/manual-save and confirmation without claiming programmatic verification (Task 4 tests).
- **Delete-versus-edit after a long offline period:** the item stays deleted, the edit is preserved as a conflict, and tombstone cleanup cannot run before all registered devices and retention rules permit it (Task 5 tests).
- **Interrupted candidate restore with low disk space or an incompatible schema:** the active database and device key remain byte-for-byte unchanged (Task 9 tests).

---

### Task 1: Prove and pin the native persistence and Apple capability stack

**Files:**
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Modify: `apple/project.yml`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/SQLCipherProbe.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/SQLCipherProbeTests.swift`
- Create: `apple/TaisaUnitTests/AppleCapabilityAvailabilityTests.swift`
- Modify: `apple/scripts/verify-project.sh`
- Create: `docs/migration/swiftui/encrypted-sync-dependencies.md`

**Interfaces:**
- Consumes: generated native project and existing `TaisaFoundation` package.
- Produces: `SQLCipherProbe.verify(databaseURL:key:) throws -> SQLCipherRuntime` and a pinned, reproducible SQLCipher/GRDB dependency graph.

- [ ] **Step 1: Add failing SQLCipher runtime tests**

Assert that a keyed database reports non-empty `PRAGMA cipher_version`, survives close/reopen with the right key, rejects the wrong key, and does not expose a canary string in raw file bytes:

```swift
@Test func encryptedDatabaseRejectsWrongKeyAndHidesPlaintext() throws {
    let result = try SQLCipherProbe.makeAndVerify(canary: "PRIVATE-CANARY")
    #expect(!result.cipherVersion.isEmpty)
    #expect(result.reopenedWithCorrectKey)
    #expect(result.wrongKeyRejected)
    #expect(!result.fileBytes.contains(Data("PRIVATE-CANARY".utf8)))
}
```

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter SQLCipherProbeTests`
Expected: FAIL because `TaisaStorage` and `SQLCipherProbe` do not exist.

- [ ] **Step 3: Pin the managed SQLCipher GRDB package**

Add `https://github.com/sqlcipher/GRDB.swift.git` at exact `7.11.1`, create the `TaisaStorage` library target, and link its `GRDB` product into the app/test targets through `project.yml`. Commit the generated `Package.resolved`, record the resolved SQLCipher.swift/core version and BSD/MIT notices, and reject SQLCipher 5 beta.

- [ ] **Step 4: Implement the probe and capability assertions**

`SQLCipherProbe` opens GRDB with raw 32-byte key material, sets the key before the first read, enables foreign keys and WAL, verifies `cipher_version` and `cipher_integrity_check`, and maps wrong-key/open failures to typed errors. `AppleCapabilityAvailabilityTests` compile-checks CloudKit, Security, CryptoKit, and the availability-gated AuthenticationServices adapter surface for iOS 17.

- [ ] **Step 5: Verify deterministic generation and device build**

Run:

```bash
npm run generate:native-apple
npm run verify:native-apple
cd apple/Packages/TaisaFoundation && swift test
xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Dev -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS; generated project is stable, SQLCipher is linked once, and no system SQLite symbol collision appears.

- [ ] **Step 6: Commit**

```bash
git add apple docs/migration/swiftui/encrypted-sync-dependencies.md
git commit -m "build: prove native encrypted storage stack"
```

### Task 2: Establish device-key handling, schema, migrations, and safe open

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/StorageError.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/KeychainStore.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/DatabaseKeyStore.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaSchema.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaMigrator.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaStore.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/TaisaStoreTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/TaisaMigratorTests.swift`

**Interfaces:**
- Consumes: pinned GRDB/SQLCipher stack from Task 1.
- Produces: `TaisaStore.open(at:keyStore:) async throws -> TaisaStore`, `TaisaStore.read`, `TaisaStore.write`, and schema version 1.

- [ ] **Step 1: Write failing safe-open and migration tests**

Cover fresh creation, reopen, wrong key, database file present with missing Keychain key, foreign keys, WAL, cipher integrity, migration idempotence, interrupted migration rollback, and rejection of a future schema.

```swift
@Test func existingDatabaseWithoutKeyFailsClosed() async throws {
    let fixture = try StoreFixture(existingDatabase: true, keychainKey: nil)
    await #expect(throws: StorageError.missingKeyForExistingStore) {
        try await TaisaStore.open(at: fixture.url, keyStore: fixture.keyStore)
    }
    #expect(try fixture.bytesAfterAttempt() == fixture.bytesBeforeAttempt)
}
```

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter 'TaisaStoreTests|TaisaMigratorTests'`
Expected: FAIL with missing storage types.

- [ ] **Step 3: Implement Keychain and store opening**

Generate 32 random bytes with `SecRandomCopyBytes`; save under `taisa.database-key.v1` using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Check file existence before key creation. Open through GRDB configuration that supplies SQLCipher key before queries, then verify cipher/integrity/foreign keys and run migrations.

- [ ] **Step 4: Implement schema version 1**

Create normalized tables for profile, conversations, messages, goals, milestones, actions, evidence, memory items/sources, sync devices, field versions, conflicts, outbox, inbox quarantine, tombstones, sync state, vault metadata, snapshot manifests, and migration state. Use opaque UUID strings, UTC integer milliseconds, foreign keys, unique idempotency constraints, and indexes only on local plaintext columns. No audio URI column enters snapshot eligibility.

- [ ] **Step 5: Run GREEN and full package tests**

Run: `cd apple/Packages/TaisaFoundation && swift test`
Expected: all existing and storage tests PASS.

- [ ] **Step 6: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: add encrypted native store"
```

### Task 3: Add typed repositories and a transactional change journal

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Models/*.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Repositories/ProfileRepository.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Repositories/ConversationRepository.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Repositories/GoalRepository.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Repositories/ActionRepository.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Repositories/EvidenceRepository.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Repositories/MemoryRepository.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaStorage/Sync/ChangeJournal.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/RepositoryContractTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/ChangeJournalTests.swift`

**Interfaces:**
- Consumes: `TaisaStore` transactional access.
- Produces: typed CRUD repositories; `ChangeJournal.pending(limit:) async throws -> [PendingChange]`; every mutation accepts `MutationContext(id:deviceID:timestamp:)`.

- [ ] **Step 1: Write failing repository contract tests**

Run the same create/update/delete/idempotency/isolation suite against every repository. Assert that successful synchronizable mutations add exactly one outbox row in the same transaction and a forced outbox failure rolls back the domain mutation.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter 'RepositoryContractTests|ChangeJournalTests'`
Expected: FAIL because repositories and journal are absent.

- [ ] **Step 3: Implement focused domain records and repositories**

Use `Codable & Sendable & Equatable` public models with stable IDs. Keep SQL records internal. Message creation is append-only; editable entities write field-version ancestry; delete writes a tombstone. Repository protocols expose domain operations without GRDB or CloudKit types.

- [ ] **Step 4: Implement the journal**

Within the caller's database transaction, encode a canonical local mutation, insert it under the mutation idempotency ID, and expose bounded FIFO reads, acknowledgement, retry category, and supersession only when ancestry proves an older unsent edit is safe to coalesce.

- [ ] **Step 5: Run GREEN**

Run: `cd apple/Packages/TaisaFoundation && swift test`
Expected: all package tests PASS, including rollback and duplicate mutation coverage.

- [ ] **Step 6: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: add native repositories and change journal"
```

### Task 4: Build the vault, recovery-key ceremony, Passwords adapter, and rotation

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSecurity/RecoveryKey.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSecurity/VaultEnvelope.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSecurity/Vault.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSecurity/PasswordsSaving.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSecurity/RecoverySetupState.swift`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaSecurityTests/VaultTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaSecurityTests/RecoverySetupTests.swift`

**Interfaces:**
- Consumes: CryptoKit, Security, and vault metadata persistence.
- Produces: `RecoveryKey.generate()`, `Vault.seal/open`, `Vault.wrap/unwrap`, `Vault.rotateRecoveryKey`, and `PasswordsSaving.save(recoveryKey:) async throws -> PasswordSaveResult`.

- [ ] **Step 1: Write failing cryptography and setup-state tests**

Use fixed test vectors to cover generation/normalization/checksum, AES-GCM authentication, unique nonces, associated-data mismatch, wrong recovery key, malformed/unsupported envelopes, rotation, iOS 26 programmatic save result, iOS 17–25 manual-save result, and refusal to enable sync until both confirmations are true.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TaisaSecurityTests`
Expected: FAIL because `TaisaSecurity` does not exist.

- [ ] **Step 3: Implement vault cryptography**

Generate 256-bit recovery and vault keys with `SecRandomCopyBytes`. Encode recovery keys as checksummed uppercase groups. Derive a wrapping key with HKDF-SHA256 using random salt plus `taisa.vault-wrap.v1` context; use CryptoKit AES-GCM combined boxes and bind version/vault/record/type/schema/tombstone values as associated data. Zero temporary mutable buffers where Swift permits and never stringify raw vault keys.

- [ ] **Step 4: Implement Passwords capability behavior**

On supported iOS 26 builds with an approved owned web-credentials domain, use `CredentialDataManager.save(password:for:title:)`. If no owned domain is approved, on iOS 17–25, or after a declined/failed save, return `.manualSaveRequired`, offer copy, explain how to create a Passwords entry, and require explicit confirmation. Neither path silently writes a synchronizable private Keychain item.

- [ ] **Step 5: Run GREEN and secret-scan tests**

Run: `cd apple/Packages/TaisaFoundation && swift test`
Expected: PASS; captured logs and error descriptions contain no recovery or vault key bytes.

- [ ] **Step 6: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: add recovery-key vault"
```

### Task 5: Implement deterministic merge, conflicts, and tombstones

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/SyncMutation.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/VersionVector.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/MergeEngine.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/Conflict.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/TombstonePolicy.swift`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaSyncTests/MergeEngineTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaSyncTests/TombstonePolicyTests.swift`

**Interfaces:**
- Consumes: canonical repository mutations and registered-device acknowledgements.
- Produces: `MergeEngine.merge(local:remote:) -> MergeDecision` and `TombstonePolicy.mayPurge(_:devices:now:) -> Bool`.

- [ ] **Step 1: Write a table-driven failing merge matrix**

Cover new record, duplicate, append-only messages, ancestor update, non-overlapping field edits, same-field edits, edit/delete, delete/delete, stale offline update, resolved conflict, reordered delivery, unknown entity version, removed device, and clock skew. Assert both competing values survive a conflict.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TaisaSyncTests`
Expected: FAIL because sync merge types are absent.

- [ ] **Step 3: Implement version and merge rules**

Use per-device monotonic counters plus field ancestry; timestamps are display metadata, never the conflict authority. Persist conflicts encrypted locally through storage interfaces. Conflict resolution references both parent versions and emits a normal outgoing mutation.

- [ ] **Step 4: Implement conservative tombstone purge**

Set the initial retention floor to 90 days. Permit purge only when every currently registered device has acknowledged a frontier beyond the deletion and no unresolved conflict references it. Removed devices stop blocking only after an explicit removal event is synchronized.

- [ ] **Step 5: Run GREEN**

Run: `cd apple/Packages/TaisaFoundation && swift test`
Expected: PASS for the full merge matrix and tombstone safety rules.

- [ ] **Step 6: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: preserve native sync conflicts"
```

### Task 6: Build the transport-neutral sync coordinator and deterministic fake

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/SyncTransport.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/SyncCoordinator.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/SyncState.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/RetryPolicy.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/InMemorySyncTransport.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaSyncTests/SyncCoordinatorTests.swift`

**Interfaces:**
- Consumes: journal, vault, merge engine, and `SyncTransport`.
- Produces: `SyncCoordinator.synchronize(reason:) async -> SyncOutcome`, observable typed `SyncState`, and a deterministic two-device test transport.

- [ ] **Step 1: Write failing two-device and failure-state tests**

Test offline edits/reconnect, 250-record batch boundaries, duplicates, partial upload, interrupted download, malformed ciphertext quarantine, account change with pending outbox, quota, retry-after, token expiry/full reconciliation, cancellation, app relaunch, and no automatic vault reset.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter SyncCoordinatorTests`
Expected: FAIL because coordinator/transport are absent.

- [ ] **Step 3: Define transport and state interfaces**

```swift
public protocol SyncTransport: Sendable {
    func accountState() async -> SyncAccountState
    func fetch(after token: Data?) async throws -> SyncFetchPage
    func send(_ changes: [EncryptedChange]) async throws -> SyncSendResult
}
```

Keep CloudKit types out of this protocol. Model actionable account-changed, offline, quota, recovery-required, conflict, retrying, and up-to-date states.

- [ ] **Step 4: Implement coordinator and fake**

Read at most 200 outbox items per batch, encrypt off the main actor, replay idempotently, authenticate before merge, commit downloaded records and durable token together, quarantine invalid input, and apply bounded exponential retry with transport-provided retry times.

- [ ] **Step 5: Run GREEN**

Run: `cd apple/Packages/TaisaFoundation && swift test`
Expected: PASS, including two independent in-memory stores converging after offline work.

- [ ] **Step 6: Commit**

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: add encrypted sync coordinator"
```

### Task 7: Integrate private CloudKit with CKSyncEngine

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaCloudKit/CloudKitSyncTransport.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaCloudKit/CloudRecordMapper.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaCloudKit/CloudKitErrorMapper.swift`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Modify: `apple/project.yml`
- Create: `apple/Config/TaisaDev.entitlements`
- Create: `apple/Config/TaisaPreview.entitlements`
- Create: `apple/Config/Taisa.entitlements`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaCloudKitTests/CloudRecordMapperTests.swift`
- Create: `apple/TaisaUnitTests/CloudKitIsolationTests.swift`
- Create: `docs/migration/swiftui/cloudkit-schema.md`

**Interfaces:**
- Consumes: `SyncTransport`, encrypted envelopes, and persisted CKSyncEngine state.
- Produces: private-zone CloudKit transport for development/production apps; preview remains fake-only.

- [ ] **Step 1: Write failing mapper and isolation tests**

Assert record names/fields never contain canary private strings, only allowlisted opaque metadata is server-visible, assets contain ciphertext, account changes map to locked states, `serverRecordChanged` returns both encrypted versions to merge logic, and preview has no production container entitlement.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TaisaCloudKitTests` and `npm run verify:native-apple`
Expected: FAIL because CloudKit integration and entitlements are absent.

- [ ] **Step 3: Stop for external capability approval**

Present exact proposed container IDs:

- Development: `iCloud.com.taisa.app.dev`
- Production: `iCloud.com.taisa.app`
- Preview: no live container; deterministic fake only.

After Baah approves, create/enable iCloud, CloudKit, and remote notifications in the Apple Developer/App Store Connect surfaces. For Passwords integration, Baah either supplies and approves an owned HTTPS domain, which is then configured for web credentials and `CredentialDataManager`, or chooses the already-tested manual Passwords-save flow; absence of an owned domain never leads to an invented association. Do not promote a production CloudKit schema yet.

- [ ] **Step 4: Implement CKSyncEngine transport**

Use one `CKSyncEngine` for the private database, one custom zone `TaisaVaultV1`, persist its serialized state in SQLCipher, supply pending changes from the outbox, honor the engine's 250-record server ceiling by using 200, handle account-change events, and map retryable/application errors without exposing payloads.

- [ ] **Step 5: Generate and verify the project**

Run:

```bash
npm run generate:native-apple
npm run verify:native-apple
xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Dev -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS; development and production entitlements are distinct; preview cannot instantiate live CloudKit.

- [ ] **Step 6: Commit**

```bash
git add apple docs/migration/swiftui/cloudkit-schema.md
git commit -m "feat: add private CloudKit transport"
```

### Task 8: Add device enrollment, removal, and resumable cryptographic revocation

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/DeviceRegistry.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/EnrollmentCoordinator.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaSync/VaultRotationCoordinator.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaSyncTests/EnrollmentTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaSyncTests/VaultRotationTests.swift`

**Interfaces:**
- Consumes: vault, repositories, transport, and device authentication callback.
- Produces: first-device setup, recovery-key enrollment, ordinary removal, and verified remove-and-rotate operations.

- [ ] **Step 1: Write failing enrollment/revocation tests**

Cover correct/wrong key, no iCloud account, account mismatch, duplicate enrollment, interrupted bootstrap, ordinary removal disclaimer, rotation journal resume after every batch, old-key rejection for new envelopes, old-copy limitation, and refusal to claim revocation before all live cloud records/snapshots verify under the new vault key.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter 'EnrollmentTests|VaultRotationTests'`
Expected: FAIL with missing coordinators.

- [ ] **Step 3: Implement enrollment and device registry**

Create opaque device IDs and signed/encrypted registration envelopes. Bootstrap into a candidate store, require recovery-key authentication, and publish acknowledgement frontiers only after successful local commit.

- [ ] **Step 4: Implement resumable remove-and-rotate**

Write a durable rotation journal containing opaque item IDs and phases. Generate a new vault key, re-encrypt current records/snapshots in bounded batches, verify remote ciphertext under the new key, publish the new recovery wrapper, then retire old current envelopes. Cancellation or crash resumes; it never deletes the only decryptable version.

- [ ] **Step 5: Run GREEN and commit**

Run: `cd apple/Packages/TaisaFoundation && swift test`
Expected: PASS.

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: add secure native device enrollment"
```

### Task 9: Add bounded encrypted snapshots and atomic candidate restore

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaRecovery/SnapshotManifest.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaRecovery/SnapshotService.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaRecovery/RestoreCoordinator.swift`
- Modify: `apple/Packages/TaisaFoundation/Package.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaRecoveryTests/SnapshotTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaRecoveryTests/RestoreTests.swift`

**Interfaces:**
- Consumes: store checkpoint/export, vault, snapshot transport, filesystem capacity, and explicit replacement confirmation.
- Produces: `SnapshotService.create/list/prune` and `RestoreCoordinator.validate/promote`.

- [ ] **Step 1: Write failing snapshot and restore tests**

Test consistent checkpoint, authenticated manifest, no audio paths, wrong key, tampering, incompatible future schema, insufficient disk space, interrupted download/decrypt/migration/promotion, entity-count/hash mismatch, active-store byte preservation, and retention.

- [ ] **Step 2: Run RED**

Run: `cd apple/Packages/TaisaFoundation && swift test --filter TaisaRecoveryTests`
Expected: FAIL because recovery package is absent.

- [ ] **Step 3: Implement bounded snapshot policy**

Create after 24 hours with meaningful changes, before migration/rotation/restore, and on explicit Back Up Now. Retain the newest 7 daily, 4 weekly, and 3 pre-risk snapshots, pruning only after a newer snapshot verifies. Refuse creation when nonterminal audio work references files.

- [ ] **Step 4: Implement candidate restore**

Require free space of at least `2 × encrypted snapshot size + 100 MB`; stream download/decrypt, authenticate manifest, verify schema/hashes/counts, migrate a candidate, close active handles, atomically exchange store directories, reopen and integrity-check, and roll back the exchange on failure.

- [ ] **Step 5: Run GREEN and commit**

Run: `cd apple/Packages/TaisaFoundation && swift test`
Expected: PASS.

```bash
git add apple/Packages/TaisaFoundation
git commit -m "feat: add encrypted native recovery"
```

### Task 10: Build the native setup, status, conflict, and recovery validation UI

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaStatusBanner.swift`
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaSecureCode.swift`
- Create: `apple/TaisaApp/Storage/StorageFoundationModel.swift`
- Create: `apple/TaisaApp/Storage/RecoverySetupView.swift`
- Create: `apple/TaisaApp/Storage/SyncStatusView.swift`
- Create: `apple/TaisaApp/Storage/ConflictReviewView.swift`
- Create: `apple/TaisaApp/Storage/SnapshotRecoveryView.swift`
- Modify: `apple/TaisaApp/FoundationRootView.swift`
- Modify: `apple/TaisaPreview/FoundationScenarios.swift`
- Create: `apple/TaisaPreview/StorageFoundationScenarios.swift`
- Create: `apple/TaisaPreviewUITests/TaisaStorageFoundationTests.swift`
- Create: `apple/TaisaUITests/TaisaRecoverySetupTests.swift`

**Interfaces:**
- Consumes: typed setup/sync/conflict/snapshot states through `StorageFoundationModel`.
- Produces: narrow device-QA surfaces; DS primitives remain logic-free.

- [ ] **Step 1: Add DS primitives and failing scenario/UI tests**

Test accessibility labels/order, Dynamic Type, copy protection/background shielding state, Passwords/manual save paths, both-confirmations gate, offline local-save message, conflict choice preserving both values, restore replacement confirmation, narrow iPad centering, reduced motion, and no recovery key in screenshots/attachments after leaving the ceremony.

- [ ] **Step 2: Run RED**

Run `Taisa-Preview` and `Taisa-Dev` focused XCUITest plans.
Expected: FAIL because storage views/scenarios are absent.

- [ ] **Step 3: Implement DS primitives first**

`TaisaStatusBanner` exposes semantic severity/status and action slots; `TaisaSecureCode` renders grouped recovery material only during an authenticated ceremony, supports explicit copy, and redacts in accessibility/app-inactive state. Add documented preview states and no business logic.

- [ ] **Step 4: Implement feature views and model**

Map typed platform states to approved actionable copy. Keep coordinators injected behind protocols. Product views import only Taisa DS for visual primitives and constrain iPad reading width to 560 points.

- [ ] **Step 5: Run UI and DS gates**

Run:

```bash
npm run verify:native-design-system
xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Dev test -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild -project apple/Taisa.xcodeproj -scheme Taisa-Preview test -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)'
```

Expected: PASS with no recovery material in result-bundle attachments.

- [ ] **Step 6: Commit**

```bash
git add apple docs/design-system.md
git commit -m "feat: add native encrypted-sync controls"
```

### Task 11: Enforce privacy, lifecycle, performance budgets, CI, and exact-device QA

**Files:**
- Create: `apple/Packages/TaisaFoundation/Sources/TaisaCore/PrivacySafeDiagnostics.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaCoreTests/PrivacySafeDiagnosticsTests.swift`
- Create: `apple/TaisaUnitTests/StorageLifecycleTests.swift`
- Create: `apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/StoragePerformanceTests.swift`
- Modify: `scripts/native-apple/verify-all.sh`
- Modify: `.github/workflows/native-apple.yml`
- Modify: `apple/scripts/record-signed-build.mjs`
- Modify: `docs/product-contracts/native-foundation.md`
- Create: `docs/product-contracts/encrypted-sync.md`
- Create: `docs/migration/swiftui/encrypted-sync-qa.md`
- Modify: `docs/migration/swiftui/native-builds.md`
- Modify: `docs/architecture.md`
- Modify: `docs/data-model.md`
- Modify: `docs/workflow.md`
- Modify: `docs/roadmap.md`

**Interfaces:**
- Consumes: all prior tasks and registered device IDs.
- Produces: content-safe diagnostics, CI gates, measured budgets, exact signed-build records, and Review + QA evidence.

- [ ] **Step 1: Write failing privacy/lifecycle/performance tests**

Inject canary names/messages/keys and assert no log, diagnostic, notification, CloudKit mapper output, screenshot attachment name, or serialized error contains them. Test background shielding, protected-data unavailable/available transitions, force quit with pending outbox, low-memory batching, and account change.

Performance fixture: 10,000 messages, 2,000 evidence items, 500 goals/actions, 1,000 pending changes. On release-mode physical devices, measure five warm runs after one discarded run. Required budgets:

- local save acknowledgement p95 ≤ 100 ms;
- warm database open p95 ≤ 500 ms;
- encrypt/decrypt 200 record envelopes ≤ 1 second;
- apply 1,000 already-downloaded changes ≤ 2 seconds;
- create a 100 MB snapshot ≤ 10 seconds;
- restore/verify/migrate a 100 MB snapshot ≤ 30 seconds;
- incremental sync work adds < 75 MB peak resident memory;
- no main-thread stall ≥ 100 ms during background sync.

- [ ] **Step 2: Run RED**

Run focused Swift tests and the updated verification script.
Expected: FAIL because privacy diagnostics, performance harness, and gates are absent.

- [ ] **Step 3: Implement content-safe diagnostics and lifecycle ownership**

Allow only enumerated error categories, opaque operation prefixes, counts, sizes, versions, and durations. Shield the root while inactive, suspend protected-data access while locked, resume idempotently after unlock, and cancel/restart bounded work across lifecycle transitions.

- [ ] **Step 4: Add CI and signed-record requirements**

Extend the full native gate with every package/test target, entitlement/container isolation checks, canary scans, Release preview-leak scan, and performance smoke thresholds. Signed records add database schema, envelope version, CloudKit environment/container, vault fixture revision, and sync/recovery results.

- [ ] **Step 5: Run the complete local gate**

Run: `npm run verify:native-apple:all`
Expected: PASS with no generated-project drift, content leak, or Release preview/live-fixture leak.

- [ ] **Step 6: Commit the clean candidate before signing**

```bash
git add .github scripts apple docs
git commit -m "test: verify encrypted native sync"
git status --porcelain
```

Expected: clean worktree.

- [ ] **Step 7: Build/install exact signed candidates**

With Baah's approval for real CloudKit development resources, sign isolated `com.taisa.app.dev` and `com.taisa.app.preview` builds from the clean candidate. Install on iPhone `00008130-000834AA34C2001C` and iPad `00008112-000C25CA0107401E`; never overwrite `com.taisa.app`.

- [ ] **Step 8: Execute two-device QA**

Verify first-device recovery ceremony, Passwords save/manual confirmation, offline edits on both devices, reconnect convergence, duplicate-free history, same-field conflict, delete-versus-edit, tombstone behavior, wrong key, second-device enrollment, key rotation, ordinary removal warning, remove-and-rotate interruption/resume, snapshot creation/retention, candidate restore, account sign-out/change, quota/unavailable simulations where Apple permits, app lock/background privacy, and all measured budgets.

- [ ] **Step 9: Stop for Baah QA**

Baah confirms the exact signed records, normal cross-device use, conflict copy/behavior, recovery-key ceremony, accessibility, iPad layout, and recovery flow. Any defect enters the reproduce → failing test → owning-layer fix → full gate → new signed build loop.

- [ ] **Step 10: Record acceptance and commit evidence**

Update scope Closeout, canonical architecture/data model, workflow/roadmap, CloudKit schema status, accepted differences, measured results, and four signed device/build records.

```bash
git add docs
git commit -m "docs: verify encrypted native sync"
```

## Plan approval boundary

Approval authorizes implementation in an isolated branch after the native-foundation predecessor is safely integrated. It does not authorize Apple Developer/App Store Connect capability creation, CloudKit production schema promotion, App Store distribution, Taisa accounts, backend route retirement, React Native deletion, audio synchronization, or Ship. Task 7 and exact signed-device QA stop at their named gates.
