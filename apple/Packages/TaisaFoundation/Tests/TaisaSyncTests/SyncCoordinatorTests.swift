import Foundation
import Testing
import TaisaSecurity
import TaisaStorage
import TaisaSync

private actor CoordinatorKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized) struct SyncCoordinatorTests {
    private func device() async throws -> (TaisaStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: CoordinatorKeys())
        return (store, directory)
    }

    @Test func firstSyncMovesEncryptedProfileBetweenIndependentStores() async throws {
        let (first, firstDirectory) = try await device()
        let (second, secondDirectory) = try await device()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("account-one".utf8))
        let recordID = UUID().uuidString
        let mutationID = UUID().uuidString
        try await ProfileRepository(store: first).create(
            ProfileRecord(id: recordID, displayName: "Private name", headline: "Designer", biography: "Private biography", updatedAtMS: 10),
            context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 10)
        )
        let sender = SyncCoordinator(store: first, vault: vault, transport: transport, nowMS: { 100 })
        let receiver = SyncCoordinator(store: second, vault: vault, transport: transport, nowMS: { 101 })
        #expect(await sender.synchronize(reason: .manual).state == .upToDate)
        #expect(try await ChangeJournal(store: first).state(id: mutationID) == .remotelyAcknowledged(atMS: 100))
        #expect(await receiver.synchronize(reason: .manual).state == .upToDate)
        #expect(try await ProfileRepository(store: second).get(id: recordID)?.displayName == "Private name")
        #expect(await receiver.synchronize(reason: .manual).downloaded == 0)
        #expect(await transport.allChanges().count == 1)
    }

    @Test func accountChangeLocksPendingWorkWithoutReplacingLocalData() async throws {
        let (store, directory) = try await device()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("first-account".utf8))
        let coordinator = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 100 })
        #expect(await coordinator.synchronize(reason: .manual).state == .upToDate)
        let recordID = UUID().uuidString
        let mutationID = UUID().uuidString
        try await ProfileRepository(store: store).create(
            ProfileRecord(id: recordID, displayName: "Keep locally", headline: "", biography: "", updatedAtMS: 10),
            context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 10)
        )
        await transport.setAccountFingerprint(Data("other-account".utf8))
        #expect(await coordinator.synchronize(reason: .manual).state == .accountChanged)
        #expect(try await ChangeJournal(store: store).pending(limit: 10).map(\.id) == [mutationID])
        #expect(try await ProfileRepository(store: store).get(id: recordID)?.displayName == "Keep locally")
        #expect(await transport.allChanges().isEmpty)
    }

    @Test func concurrentSameFieldEditsPersistBothAlternatives() async throws {
        let (first, firstDirectory) = try await device()
        let (second, secondDirectory) = try await device()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("same-account".utf8))
        let firstSync = SyncCoordinator(store: first, vault: vault, transport: transport, nowMS: { 100 })
        let secondSync = SyncCoordinator(store: second, vault: vault, transport: transport, nowMS: { 100 })
        let recordID = UUID().uuidString
        let firstDevice = UUID().uuidString
        let secondDevice = UUID().uuidString
        try await ProfileRepository(store: first).create(
            ProfileRecord(id: recordID, displayName: "Base", headline: "", biography: "", updatedAtMS: 10),
            context: MutationContext(id: UUID().uuidString, deviceID: firstDevice, timestamp: 10)
        )
        #expect(await firstSync.synchronize(reason: .manual).state == .upToDate)
        #expect(await secondSync.synchronize(reason: .manual).state == .upToDate)
        try await ProfileRepository(store: first).update(
            ProfileRecord(id: recordID, displayName: "First private value", headline: "", biography: "", updatedAtMS: 20),
            context: MutationContext(id: UUID().uuidString, deviceID: firstDevice, timestamp: 20)
        )
        try await ProfileRepository(store: second).update(
            ProfileRecord(id: recordID, displayName: "Second private value", headline: "", biography: "", updatedAtMS: 21),
            context: MutationContext(id: UUID().uuidString, deviceID: secondDevice, timestamp: 21)
        )
        #expect(await firstSync.synchronize(reason: .manual).state == .upToDate)
        #expect(await secondSync.synchronize(reason: .manual).state == .conflictsNeedReview)
        #expect(await firstSync.synchronize(reason: .manual).state == .conflictsNeedReview)
        let firstConflict = try #require(await ConflictStore(store: first).unresolved().first { $0.fieldName == "displayName" })
        let secondConflict = try #require(await ConflictStore(store: second).unresolved().first { $0.fieldName == "displayName" })
        #expect(firstConflict == secondConflict)
        #expect(Set([firstConflict.first.value, firstConflict.second.value].compactMap { $0 }) == Set([Data("\"First private value\"".utf8), Data("\"Second private value\"".utf8)]))
    }

    @Test func uploadUsesTwoHundredItemBatchesAndReplaysWithoutDuplicates() async throws {
        let (store, directory) = try await device()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = InMemorySyncTransport(accountFingerprint: Data("batch-account".utf8))
        let vault = try Vault.generate()
        let repository = ProfileRepository(store: store)
        let deviceID = UUID().uuidString
        for index in 0..<250 {
            try await repository.create(
                ProfileRecord(id: UUID().uuidString, displayName: "Name \(index)", headline: "", biography: "", updatedAtMS: Int64(index)),
                context: MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: Int64(index))
            )
        }
        let coordinator = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 1_000 })
        #expect(await coordinator.synchronize(reason: .manual).uploaded == 250)
        #expect(await transport.allChanges().count == 250)
        #expect(await coordinator.synchronize(reason: .manual).uploaded == 0)
        #expect(await transport.allChanges().count == 250)
    }

    @Test func partialUploadAcknowledgesOnlyActualSuccessAndRetriesRemainingItem() async throws {
        let (store, directory) = try await device()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = InMemorySyncTransport(accountFingerprint: Data("partial-account".utf8))
        let vault = try Vault.generate()
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let deviceID = UUID().uuidString
        let repository = ProfileRepository(store: store)
        for id in [firstID, secondID] {
            try await repository.create(
                ProfileRecord(id: UUID().uuidString, displayName: "Local", headline: "", biography: "", updatedAtMS: 10),
                context: MutationContext(id: id, deviceID: deviceID, timestamp: 10)
            )
        }
        await transport.failNextItems([secondID: .rateLimited(retryAfterMS: 5_000)])
        let coordinator = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 1_000 })
        let first = await coordinator.synchronize(reason: .manual)
        #expect(first.state == .retrying)
        #expect(first.uploaded == 1)
        #expect(first.retryAtMS == 5_000)
        #expect(try await ChangeJournal(store: store).state(id: firstID) == .remotelyAcknowledged(atMS: 1_000))
        #expect(try await ChangeJournal(store: store).state(id: secondID) == .retrying(category: "rate_limited", attempts: 1))
        #expect(await coordinator.synchronize(reason: .manual).uploaded == 0)
        let relaunched = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 5_000 })
        #expect(await relaunched.synchronize(reason: .manual).uploaded == 1)
        #expect(await transport.allChanges().count == 2)
    }

    @Test func malformedCiphertextQuarantinesWholePageWithoutAdvancingToken() async throws {
        let (senderStore, senderDirectory) = try await device()
        let (receiverStore, receiverDirectory) = try await device()
        defer {
            try? FileManager.default.removeItem(at: senderDirectory)
            try? FileManager.default.removeItem(at: receiverDirectory)
        }
        let transport = InMemorySyncTransport(accountFingerprint: Data("quarantine-account".utf8))
        let vault = try Vault.generate()
        let recordID = UUID().uuidString
        try await ProfileRepository(store: senderStore).create(
            ProfileRecord(id: recordID, displayName: "Must remain hidden", headline: "", biography: "", updatedAtMS: 10),
            context: MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 10)
        )
        #expect(await SyncCoordinator(store: senderStore, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .upToDate)
        let invalidID = UUID().uuidString
        let metadata = EnvelopeMetadata(vaultID: vault.id, recordID: UUID(uuidString: invalidID)!, entityType: "profile", schemaVersion: 1, tombstone: false)
        let session = try await transport.bind(expectedFingerprint: Data("quarantine-account".utf8))
        _ = try await transport.send([EncryptedChange(id: invalidID, envelope: VaultEnvelope(version: 1, metadata: metadata, ciphertext: Data(repeating: 0, count: 28)))], session: session)
        let receiver = SyncCoordinator(store: receiverStore, vault: vault, transport: transport, nowMS: { 101 })
        let first = await receiver.synchronize(reason: .manual)
        #expect(first.state == .recoveryRequired)
        #expect(first.quarantined == 1)
        #expect(try await ProfileRepository(store: receiverStore).get(id: recordID) == nil)
        #expect(await receiver.synchronize(reason: .manual).state == .recoveryRequired)
        #expect(try await ProfileRepository(store: receiverStore).get(id: recordID) == nil)
    }

    @Test func expiredDownloadTokenReconcilesWithoutDroppingEarlierRecords() async throws {
        let (senderStore, senderDirectory) = try await device()
        let (receiverStore, receiverDirectory) = try await device()
        defer {
            try? FileManager.default.removeItem(at: senderDirectory)
            try? FileManager.default.removeItem(at: receiverDirectory)
        }
        let vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("reconcile-account".utf8))
        let sender = SyncCoordinator(store: senderStore, vault: vault, transport: transport, nowMS: { 100 })
        let receiver = SyncCoordinator(store: receiverStore, vault: vault, transport: transport, nowMS: { 101 })
        let repository = ProfileRepository(store: senderStore)
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let deviceID = UUID().uuidString
        try await repository.create(ProfileRecord(id: firstID, displayName: "First", headline: "", biography: "", updatedAtMS: 10), context: MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 10))
        #expect(await sender.synchronize(reason: .manual).state == .upToDate)
        #expect(await receiver.synchronize(reason: .manual).state == .upToDate)
        try await repository.create(ProfileRecord(id: secondID, displayName: "Second", headline: "", biography: "", updatedAtMS: 20), context: MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: 20))
        #expect(await sender.synchronize(reason: .manual).state == .upToDate)
        await transport.failNextFetch(.tokenExpired)
        #expect(await receiver.synchronize(reason: .manual).state == .upToDate)
        #expect(try await ProfileRepository(store: receiverStore).get(id: firstID)?.displayName == "First")
        #expect(try await ProfileRepository(store: receiverStore).get(id: secondID)?.displayName == "Second")
    }

    @Test func interruptedFetchResumesAfterDurableBackoff() async throws {
        let (senderStore, senderDirectory) = try await device()
        let (receiverStore, receiverDirectory) = try await device()
        defer {
            try? FileManager.default.removeItem(at: senderDirectory)
            try? FileManager.default.removeItem(at: receiverDirectory)
        }
        let vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("interrupt-account".utf8))
        let recordID = UUID().uuidString
        try await ProfileRepository(store: senderStore).create(ProfileRecord(id: recordID, displayName: "Eventually", headline: "", biography: "", updatedAtMS: 10), context: MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 10))
        #expect(await SyncCoordinator(store: senderStore, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .upToDate)
        await transport.failNextFetch(.retryable)
        let receiver = SyncCoordinator(store: receiverStore, vault: vault, transport: transport, nowMS: { 101 })
        #expect(await receiver.synchronize(reason: .manual).state == .retrying)
        #expect(try await ProfileRepository(store: receiverStore).get(id: recordID) == nil)
        #expect(await receiver.synchronize(reason: .manual).state == .retrying)
        let resumed = SyncCoordinator(store: receiverStore, vault: vault, transport: transport, nowMS: { 2_000 })
        #expect(await resumed.synchronize(reason: .foreground).state == .upToDate)
        #expect(try await ProfileRepository(store: receiverStore).get(id: recordID)?.displayName == "Eventually")
    }

    @Test func reorderedDuplicateDeliveryRemainsIdempotent() async throws {
        let (senderStore, senderDirectory) = try await device()
        let (receiverStore, receiverDirectory) = try await device()
        defer {
            try? FileManager.default.removeItem(at: senderDirectory)
            try? FileManager.default.removeItem(at: receiverDirectory)
        }
        let vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("reorder-account".utf8))
        let ids = [UUID().uuidString, UUID().uuidString]
        let deviceID = UUID().uuidString
        for (index, id) in ids.enumerated() {
            try await ProfileRepository(store: senderStore).create(ProfileRecord(id: id, displayName: "Name \(index)", headline: "", biography: "", updatedAtMS: Int64(index)), context: MutationContext(id: UUID().uuidString, deviceID: deviceID, timestamp: Int64(index)))
        }
        #expect(await SyncCoordinator(store: senderStore, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual).state == .upToDate)
        await transport.reverseNextDownload()
        await transport.duplicateNextDownload()
        let receiver = SyncCoordinator(store: receiverStore, vault: vault, transport: transport, nowMS: { 101 })
        #expect(await receiver.synchronize(reason: .manual).state == .upToDate)
        #expect(try await ProfileRepository(store: receiverStore).get(id: ids[0])?.displayName == "Name 0")
        #expect(try await ProfileRepository(store: receiverStore).get(id: ids[1])?.displayName == "Name 1")
        #expect(await receiver.synchronize(reason: .manual).downloaded == 0)
    }

    @Test func cancelledTurnLeavesLocalOutboxUntouched() async throws {
        let (store, directory) = try await device()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mutationID = UUID().uuidString
        try await ProfileRepository(store: store).create(ProfileRecord(id: UUID().uuidString, displayName: "Saved", headline: "", biography: "", updatedAtMS: 10), context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 10))
        let transport = InMemorySyncTransport(accountFingerprint: Data("cancel-account".utf8))
        let coordinator = SyncCoordinator(store: store, vault: try Vault.generate(), transport: transport, nowMS: { 100 })
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await coordinator.synchronize(reason: .manual)
        }
        #expect(await cancelled.value.state == .retrying)
        #expect(try await ChangeJournal(store: store).pending(limit: 10).map(\.id) == [mutationID])
        #expect(await transport.allChanges().isEmpty)
    }

    @Test func reservedLeaseDoesNotReportUpToDateAndExpiresForSafeReplay() async throws {
        let (store, directory) = try await device()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mutationID = UUID().uuidString
        try await ProfileRepository(store: store).create(ProfileRecord(id: UUID().uuidString, displayName: "Pending", headline: "", biography: "", updatedAtMS: 10), context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 10))
        let journal = ChangeJournal(store: store)
        #expect(try await journal.reservePending(limit: 1, at: 100, leaseDurationMS: 10).count == 1)
        let transport = InMemorySyncTransport(accountFingerprint: Data("lease-account".utf8))
        let vault = try Vault.generate()
        let beforeExpiry = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 105 })
        #expect(await beforeExpiry.synchronize(reason: .foreground).state == .retrying)
        #expect(await transport.allChanges().isEmpty)
        let afterExpiry = SyncCoordinator(store: store, vault: vault, transport: transport, nowMS: { 111 })
        #expect(await afterExpiry.synchronize(reason: .foreground).state == .upToDate)
        #expect(try await journal.state(id: mutationID) == .remotelyAcknowledged(atMS: 111))
        #expect(await transport.allChanges().count == 1)
    }

    @Test func zoneResetIsExplicitAndDoesNotEraseLocalWork() async throws {
        let (store, directory) = try await device()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mutationID = UUID().uuidString
        let recordID = UUID().uuidString
        try await ProfileRepository(store: store).create(ProfileRecord(id: recordID, displayName: "Keep", headline: "", biography: "", updatedAtMS: 10), context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 10))
        let transport = InMemorySyncTransport(accountFingerprint: Data("zone-account".utf8))
        await transport.failNextFetch(.zoneReset)
        let coordinator = SyncCoordinator(store: store, vault: try Vault.generate(), transport: transport, nowMS: { 100 })
        #expect(await coordinator.synchronize(reason: .manual).state == .zoneReset)
        #expect(try await ProfileRepository(store: store).get(id: recordID)?.displayName == "Keep")
        #expect(try await ChangeJournal(store: store).state(id: mutationID) == .remotelyAcknowledged(atMS: 100))
    }

    @Test func publicTransportAndStatusDescriptionsDoNotPrintTokensOrPayloadShapes() throws {
        let token = Data("secret-token-canary".utf8)
        let account = SyncAccountState.available(fingerprint: token)
        let page = SyncFetchPage(changes: [], token: token)
        let outcome = SyncOutcome(state: .retrying, retryAtMS: 9_999)
        #expect(!String(reflecting: account).contains("fingerprint"))
        #expect(!String(reflecting: page).contains("token"))
        #expect(!String(reflecting: outcome).contains("retryAtMS"))
        #expect(!String(describing: SyncTransportError.rateLimited(retryAfterMS: 9_999)).contains("9999"))
    }

    @Test func explicitResolutionAtomicallyQueuesOutgoingMutationAndConverges() async throws {
        let (first, firstDirectory) = try await device()
        let (second, secondDirectory) = try await device()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("resolve-account".utf8))
        let firstSync = SyncCoordinator(store: first, vault: vault, transport: transport, nowMS: { 100 })
        let secondSync = SyncCoordinator(store: second, vault: vault, transport: transport, nowMS: { 100 })
        let recordID = UUID().uuidString
        let firstDevice = UUID().uuidString
        let secondDevice = UUID().uuidString
        try await ProfileRepository(store: first).create(ProfileRecord(id: recordID, displayName: "Base", headline: "", biography: "", updatedAtMS: 10), context: MutationContext(id: UUID().uuidString, deviceID: firstDevice, timestamp: 10))
        #expect(await firstSync.synchronize(reason: .manual).state == .upToDate)
        #expect(await secondSync.synchronize(reason: .manual).state == .upToDate)
        try await ProfileRepository(store: first).update(ProfileRecord(id: recordID, displayName: "One", headline: "", biography: "", updatedAtMS: 20), context: MutationContext(id: UUID().uuidString, deviceID: firstDevice, timestamp: 20))
        try await ProfileRepository(store: second).update(ProfileRecord(id: recordID, displayName: "Two", headline: "", biography: "", updatedAtMS: 20), context: MutationContext(id: UUID().uuidString, deviceID: secondDevice, timestamp: 21))
        #expect(await firstSync.synchronize(reason: .manual).state == .upToDate)
        #expect(await secondSync.synchronize(reason: .manual).state == .conflictsNeedReview)
        #expect(await firstSync.synchronize(reason: .manual).state == .conflictsNeedReview)
        let conflict = try #require(await ConflictStore(store: first).unresolved().first { $0.fieldName == "displayName" })
        let resolutionID = UUID().uuidString
        let resolution = try conflict.resolve(value: Data("\"Chosen\"".utf8), mutationID: resolutionID, deviceID: UUID().uuidString, counter: 1, timestampMS: 30)
        try await firstSync.resolveConflict(conflict, using: resolution)
        #expect(try await ProfileRepository(store: first).get(id: recordID)?.displayName == "Chosen")
        #expect(try await ChangeJournal(store: first).pending(limit: 10).map(\.id) == [resolutionID])
        #expect(try await ConflictStore(store: first).unresolved().isEmpty)
        #expect(await firstSync.synchronize(reason: .manual).state == .upToDate)
        #expect(await secondSync.synchronize(reason: .manual).state == .upToDate)
        #expect(try await ProfileRepository(store: second).get(id: recordID)?.displayName == "Chosen")
        #expect(try await ConflictStore(store: second).unresolved().isEmpty)
        try await ProfileRepository(store: second).update(ProfileRecord(id: recordID, displayName: "Later", headline: "", biography: "", updatedAtMS: 40), context: MutationContext(id: UUID().uuidString, deviceID: secondDevice, timestamp: 40))
        let later = try #require(await ChangeJournal(store: second).pending(limit: 10).first)
        #expect(later.causality.changedFields.first { $0.fieldName == "displayName" }?.parentVersionID == resolutionID)
    }

    @Test func deleteVersusEditResolutionRestoresVisibilityOnBothDevices() async throws {
        let (first, firstDirectory) = try await device()
        let (second, secondDirectory) = try await device()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("delete-edit-account".utf8))
        let firstSync = SyncCoordinator(store: first, vault: vault, transport: transport, nowMS: { 100 })
        let secondSync = SyncCoordinator(store: second, vault: vault, transport: transport, nowMS: { 100 })
        let id = UUID().uuidString
        let firstDevice = UUID().uuidString
        let secondDevice = UUID().uuidString
        try await ProfileRepository(store: first).create(ProfileRecord(id: id, displayName: "Base", headline: "", biography: "", updatedAtMS: 10), context: MutationContext(id: UUID().uuidString, deviceID: firstDevice, timestamp: 10))
        #expect(await firstSync.synchronize(reason: .manual).state == .upToDate)
        #expect(await secondSync.synchronize(reason: .manual).state == .upToDate)
        try await ProfileRepository(store: first).update(ProfileRecord(id: id, displayName: "Offline edit", headline: "", biography: "", updatedAtMS: 20), context: MutationContext(id: UUID().uuidString, deviceID: firstDevice, timestamp: 20))
        try await ProfileRepository(store: second).delete(id: id, context: MutationContext(id: UUID().uuidString, deviceID: secondDevice, timestamp: 21))
        _ = await firstSync.synchronize(reason: .manual)
        _ = await secondSync.synchronize(reason: .manual)
        _ = await firstSync.synchronize(reason: .manual)
        let conflict = try #require(await ConflictStore(store: first).unresolved().first { $0.fieldName == "displayName" })
        let resolution = try conflict.resolve(value: Data("\"Restored\"".utf8), mutationID: UUID().uuidString, deviceID: UUID().uuidString, counter: 1, timestampMS: 30)
        try await firstSync.resolveConflict(conflict, using: resolution)
        #expect(try await ProfileRepository(store: first).get(id: id)?.displayName == "Restored")
        _ = await firstSync.synchronize(reason: .manual)
        _ = await secondSync.synchronize(reason: .manual)
        #expect(try await ProfileRepository(store: second).get(id: id)?.displayName == "Restored")
    }

    @Test func accountChangeDuringSendNeverAcknowledgesOldAccountUpload() async throws {
        let (store, directory) = try await device()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mutationID = UUID().uuidString
        let recordID = UUID().uuidString
        try await ProfileRepository(store: store).create(ProfileRecord(id: recordID, displayName: "Local private", headline: "", biography: "", updatedAtMS: 10), context: MutationContext(id: mutationID, deviceID: UUID().uuidString, timestamp: 10))
        let transport = InMemorySyncTransport(accountFingerprint: Data("old-account".utf8))
        await transport.changeAccountAfterNextSend(to: Data("new-account".utf8))
        let coordinator = SyncCoordinator(store: store, vault: try Vault.generate(), transport: transport, nowMS: { 100 })
        #expect(await coordinator.synchronize(reason: .manual).state == .accountChanged)
        #expect(try await ChangeJournal(store: store).state(id: mutationID) == .retrying(category: "account", attempts: 1))
        #expect(try await ProfileRepository(store: store).get(id: recordID)?.displayName == "Local private")
        #expect(await coordinator.synchronize(reason: .manual).state == .accountChanged)
    }

    @Test func cancellationAfterFetchLeavesTokenAndDomainUnchangedForResume() async throws {
        let (senderStore, senderDirectory) = try await device()
        let (receiverStore, receiverDirectory) = try await device()
        defer {
            try? FileManager.default.removeItem(at: senderDirectory)
            try? FileManager.default.removeItem(at: receiverDirectory)
        }
        let vault = try Vault.generate()
        let transport = InMemorySyncTransport(accountFingerprint: Data("cancel-fetch-account".utf8))
        let id = UUID().uuidString
        try await ProfileRepository(store: senderStore).create(ProfileRecord(id: id, displayName: "Wait for resume", headline: "", biography: "", updatedAtMS: 10), context: MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 10))
        _ = await SyncCoordinator(store: senderStore, vault: vault, transport: transport, nowMS: { 100 }).synchronize(reason: .manual)
        await transport.cancelNextFetch()
        let receiver = SyncCoordinator(store: receiverStore, vault: vault, transport: transport, nowMS: { 101 })
        let interrupted = Task { await receiver.synchronize(reason: .manual) }
        #expect(await interrupted.value.state == .retrying)
        #expect(try await ProfileRepository(store: receiverStore).get(id: id) == nil)
        #expect(await receiver.synchronize(reason: .foreground).state == .upToDate)
        #expect(try await ProfileRepository(store: receiverStore).get(id: id)?.displayName == "Wait for resume")
    }
}
