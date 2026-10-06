import CloudKit
import Foundation
import GRDB
import Testing
import TaisaSecurity
import TaisaStorage
import TaisaSync
@testable import TaisaCloudKit

private actor AdapterKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

private actor ScriptedCloud {
    weak var transport: CloudKitSyncTransport?
    private var fingerprint = Data("test-account".utf8)
    private(set) var calls: [(CloudKitEngineHandle, [CKRecord])] = []
    private(set) var fetchCalls: [CloudKitEngineHandle] = []
    private(set) var cancelled: [UUID] = []
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var fetchedRecords: [CKRecord] = []
    func accountState() -> SyncAccountState { .available(fingerprint: fingerprint) }
    func switchAccount(to fingerprint: Data) { self.fingerprint = fingerprint }
    func send(_ handle: CloudKitEngineHandle, records: [CKRecord]) async {
        calls.append((handle, records))
        let index = calls.count
        await withCheckedContinuation { continuations[index] = $0 }
        await transport?.recordSends(savedRecords: records, failed: [], from: handle.id)
    }
    func attach(_ transport: CloudKitSyncTransport) { self.transport = transport }
    func release(_ index: Int) { continuations.removeValue(forKey: index)?.resume() }
    func record(at index: Int) -> CKRecord { calls[index].1[0] }
    func fetch(_ handle: CloudKitEngineHandle) async {
        fetchCalls.append(handle)
        await withCheckedContinuation { fetchContinuation = $0 }
        await transport?.recordFetched(records: fetchedRecords, hasDeletions: false, from: handle.id)
    }
    func setFetchedRecords(_ records: [CKRecord]) { fetchedRecords = records }
    func releaseFetch() { fetchContinuation?.resume(); fetchContinuation = nil }
    func cancel(_ handle: CloudKitEngineHandle) {
        cancelled.append(handle.id)
        for index in calls.indices where calls[index].0.id == handle.id {
            continuations.removeValue(forKey: index + 1)?.resume()
        }
        if fetchCalls.last?.id == handle.id { releaseFetch() }
    }
}

@Suite(.serialized) struct CloudKitTransportAdapterTests {
    private func changes(_ vault: Vault) throws -> [EncryptedChange] {
        try (0..<2).map { index in
            let id = UUID()
            return EncryptedChange(id: id.uuidString, envelope: try vault.seal(Data("private-\(index)".utf8), metadata: .init(vaultID: vault.id, recordID: id, entityType: "profile", schemaVersion: 1, tombstone: false)))
        }
    }

    private func waitFor(_ count: Int, in cloud: ScriptedCloud) async {
        while await cloud.calls.count < count { await Task.yield() }
    }

    @Test func overlappingAdapterSendsReturnOnlyTheirOwnAcknowledgementsAndAssets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("taisa-adapter-overlap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: AdapterKeys())
        let fingerprint = Data("test-account".utf8), vault = try Vault.generate(), cloud = ScriptedCloud()
        try await store.write { db in
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, 0)", arguments: [vault.id.uuidString, fingerprint, Data("{}".utf8)])
        }
        let runtime = CloudKitTransportRuntime(
            accountState: { await cloud.accountState() },
            makeEngine: { _, _ in CloudKitEngineHandle() },
            send: { handle, records in await cloud.send(handle, records: records) },
            fetch: { _ in }, cancel: { _ in }
        )
        let transport = try CloudKitSyncTransport(containerIdentifier: "iCloud.com.taisa.app.dev", bundleIdentifier: "com.taisa.app.dev", store: store, runtime: runtime, assetRoot: directory.appendingPathComponent("assets"))
        await cloud.attach(transport)
        let session = try await transport.bind(expectedFingerprint: fingerprint)
        let changes = try changes(vault)
        let first = Task { try await transport.send([changes[0]], session: session) }
        await waitFor(1, in: cloud)
        let firstAsset = try #require((await cloud.record(at: 0)["ciphertext"] as? CKAsset)?.fileURL)
        #expect(FileManager.default.fileExists(atPath: firstAsset.path))
        let second = Task { try await transport.send([changes[1]], session: session) }
        for _ in 0..<100 { await Task.yield() }
        #expect(await cloud.calls.count == 1)
        await cloud.release(1)
        let firstResult = try await first.value
        await waitFor(2, in: cloud)
        let secondAsset = try #require((await cloud.record(at: 1)["ciphertext"] as? CKAsset)?.fileURL)
        #expect(!FileManager.default.fileExists(atPath: firstAsset.path))
        #expect(FileManager.default.fileExists(atPath: secondAsset.path))
        await cloud.release(2)
        let secondResult = try await second.value
        #expect(firstResult.acknowledgedIDs == [changes[0].id])
        #expect(secondResult.acknowledgedIDs == [changes[1].id])
        #expect(!FileManager.default.fileExists(atPath: secondAsset.path))
    }

    @Test func adapterFetchWaitsForSendAndReturnsInjectedCiphertext() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("taisa-adapter-fetch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: AdapterKeys())
        let fingerprint = Data("test-account".utf8), vault = try Vault.generate(), cloud = ScriptedCloud()
        try await store.write { db in
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, 0)", arguments: [vault.id.uuidString, fingerprint, Data("{}".utf8)])
        }
        let runtime = CloudKitTransportRuntime(
            accountState: { await cloud.accountState() },
            makeEngine: { _, _ in CloudKitEngineHandle() },
            send: { handle, records in await cloud.send(handle, records: records) },
            fetch: { handle in await cloud.fetch(handle) }, cancel: { _ in }
        )
        let transport = try CloudKitSyncTransport(containerIdentifier: "iCloud.com.taisa.app.dev", bundleIdentifier: "com.taisa.app.dev", store: store, runtime: runtime)
        await cloud.attach(transport)
        let session = try await transport.bind(expectedFingerprint: fingerprint)
        let change = try #require(changes(vault).first)
        let send = Task { try await transport.send([change], session: session) }
        await waitFor(1, in: cloud)
        let fetch = Task { try await transport.fetch(after: nil, session: session) }
        for _ in 0..<100 { await Task.yield() }
        #expect(await cloud.fetchCalls.isEmpty)
        await cloud.release(1)
        let sent = try await send.value
        #expect(sent.acknowledgedIDs == [change.id])
        while await cloud.fetchCalls.isEmpty { await Task.yield() }
        let remoteAssetDirectory = directory.appendingPathComponent("remote-assets")
        let remoteRecord = try CloudRecordMapper.makeRecord(change, assetDirectory: remoteAssetDirectory)
        await cloud.setFetchedRecords([remoteRecord])
        await cloud.releaseFetch()
        let page = try await fetch.value
        #expect(page.changes == [change])
    }

    @Test func cancelledQueuedSendCannotConsumeAnotherOperationsResultOrAsset() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("taisa-adapter-queued-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: AdapterKeys())
        let fingerprint = Data("test-account".utf8), vault = try Vault.generate(), cloud = ScriptedCloud()
        try await store.write { db in
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, 0)", arguments: [vault.id.uuidString, fingerprint, Data("{}".utf8)])
        }
        let runtime = CloudKitTransportRuntime(
            accountState: { await cloud.accountState() },
            makeEngine: { _, _ in CloudKitEngineHandle() },
            send: { handle, records in await cloud.send(handle, records: records) },
            fetch: { _ in }, cancel: { handle in await cloud.cancel(handle) }
        )
        let transport = try CloudKitSyncTransport(containerIdentifier: "iCloud.com.taisa.app.dev", bundleIdentifier: "com.taisa.app.dev", store: store, runtime: runtime, assetRoot: directory.appendingPathComponent("assets"))
        await cloud.attach(transport)
        let session = try await transport.bind(expectedFingerprint: fingerprint)
        let changes = try changes(vault)
        let first = Task { try await transport.send([changes[0]], session: session) }
        await waitFor(1, in: cloud)
        let firstAsset = try #require((await cloud.record(at: 0)["ciphertext"] as? CKAsset)?.fileURL)
        let queued = Task { try await transport.send([changes[1]], session: session) }
        for _ in 0..<100 { await Task.yield() }
        queued.cancel()
        #expect(await cloud.calls.count == 1)
        #expect(FileManager.default.fileExists(atPath: firstAsset.path))
        await cloud.release(1)
        let firstResult = try await first.value
        await #expect(throws: CancellationError.self) { try await queued.value }
        #expect(await cloud.calls.count == 1)
        #expect(firstResult.acknowledgedIDs == [changes[0].id])
        #expect(!FileManager.default.fileExists(atPath: firstAsset.path))
        let next = Task { try await transport.send([changes[1]], session: session) }
        await waitFor(2, in: cloud)
        await cloud.release(2)
        #expect(try await next.value.acknowledgedIDs == [changes[1].id])
    }

    @Test func cancellingActiveSendCancelsOwningEngineAndCleansOnlyItsAsset() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("taisa-adapter-active-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: AdapterKeys())
        let fingerprint = Data("test-account".utf8), vault = try Vault.generate(), cloud = ScriptedCloud()
        try await store.write { db in
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, 0)", arguments: [vault.id.uuidString, fingerprint, Data("{}".utf8)])
        }
        let runtime = CloudKitTransportRuntime(
            accountState: { await cloud.accountState() },
            makeEngine: { _, _ in CloudKitEngineHandle() },
            send: { handle, records in await cloud.send(handle, records: records) },
            fetch: { _ in }, cancel: { handle in await cloud.cancel(handle) }
        )
        let transport = try CloudKitSyncTransport(containerIdentifier: "iCloud.com.taisa.app.dev", bundleIdentifier: "com.taisa.app.dev", store: store, runtime: runtime, assetRoot: directory.appendingPathComponent("assets"))
        await cloud.attach(transport)
        let session = try await transport.bind(expectedFingerprint: fingerprint)
        let changes = try changes(vault)
        let active = Task { try await transport.send([changes[0]], session: session) }
        await waitFor(1, in: cloud)
        let oldEngineID = await cloud.calls[0].0.id
        let oldAsset = try #require((await cloud.record(at: 0)["ciphertext"] as? CKAsset)?.fileURL)
        active.cancel()
        for _ in 0..<1000 where await cloud.cancelled.isEmpty { await Task.yield() }
        #expect(await cloud.cancelled.contains(oldEngineID))
        await cloud.release(1) // Do not strand the test if cancellation regresses.
        await #expect(throws: CancellationError.self) { try await active.value }
        #expect(!FileManager.default.fileExists(atPath: oldAsset.path))
        let rebound = try await transport.bind(expectedFingerprint: fingerprint)
        let next = Task { try await transport.send([changes[1]], session: rebound) }
        await waitFor(2, in: cloud)
        let newEngineID = await cloud.calls[1].0.id
        #expect(newEngineID != oldEngineID)
        let newAsset = try #require((await cloud.record(at: 1)["ciphertext"] as? CKAsset)?.fileURL)
        #expect(FileManager.default.fileExists(atPath: newAsset.path))
        await cloud.release(2)
        #expect(try await next.value.acknowledgedIDs == [changes[1].id])
        #expect(!FileManager.default.fileExists(atPath: newAsset.path))
    }

    @Test func retiredEngineCallbacksCannotContaminateNewAccountGeneration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("taisa-adapter-retired-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: AdapterKeys())
        let firstFingerprint = Data("test-account".utf8), secondFingerprint = Data("next-account".utf8)
        let vault = try Vault.generate(), cloud = ScriptedCloud()
        try await store.write { db in
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, 0)", arguments: [vault.id.uuidString, firstFingerprint, Data("{}".utf8)])
        }
        let runtime = CloudKitTransportRuntime(
            accountState: { await cloud.accountState() },
            makeEngine: { _, _ in CloudKitEngineHandle() },
            send: { handle, records in await cloud.send(handle, records: records) },
            fetch: { handle in await cloud.fetch(handle) },
            cancel: { handle in await cloud.cancel(handle) }
        )
        let transport = try CloudKitSyncTransport(containerIdentifier: "iCloud.com.taisa.app.dev", bundleIdentifier: "com.taisa.app.dev", store: store, runtime: runtime)
        await cloud.attach(transport)
        let firstSession = try await transport.bind(expectedFingerprint: firstFingerprint)
        let changes = try changes(vault)
        let oldSend = Task { try await transport.send([changes[0]], session: firstSession) }
        await waitFor(1, in: cloud)
        let oldEngineID = await cloud.calls[0].0.id
        await cloud.switchAccount(to: secondFingerprint)
        #expect(await transport.accountState() == .available(fingerprint: secondFingerprint))
        await #expect(throws: SyncTransportError.accountChanged) { try await oldSend.value }
        try await store.write { db in
            try db.execute(sql: "UPDATE sync_state SET account_fingerprint = ?, engine_state = ?, change_token = NULL WHERE id = 1", arguments: [secondFingerprint, Data("{}".utf8)])
        }
        let secondSession = try await transport.bind(expectedFingerprint: secondFingerprint)
        #expect(secondSession.generation != firstSession.generation)
        let newSend = Task { try await transport.send([changes[1]], session: secondSession) }
        await waitFor(2, in: cloud)
        let newRecord = await cloud.record(at: 1)
        let newEngineID = await cloud.calls[1].0.id
        #expect(newEngineID != oldEngineID)
        await transport.recordSends(savedRecords: [newRecord], failed: [], from: oldEngineID)
        await transport.recordEngineState(Data("stale-engine-state".utf8), from: oldEngineID)
        await transport.recordFetched(records: [newRecord], hasDeletions: false, from: oldEngineID)
        let persistence = SyncTransportPersistence(store: store)
        #expect(try await persistence.engineState(for: secondFingerprint) == nil)
        #expect(try await persistence.page(after: nil, for: secondFingerprint).changes.isEmpty)
        await cloud.release(2)
        #expect(try await newSend.value.acknowledgedIDs == [changes[1].id])
    }

    @Test func adapterCanBindWithInjectedAccountWithoutLiveCloudKitContainer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("taisa-adapter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: AdapterKeys())
        let fingerprint = Data("test-account".utf8), vault = try Vault.generate()
        try await store.write { db in
            try db.execute(sql: "INSERT INTO sync_state (id, vault_id, account_fingerprint, engine_state, updated_at_ms) VALUES (1, ?, ?, ?, 0)", arguments: [vault.id.uuidString, fingerprint, Data("{}".utf8)])
        }
        let runtime = CloudKitTransportRuntime(
            accountState: { .available(fingerprint: fingerprint) },
            makeEngine: { _, _ in CloudKitEngineHandle() },
            send: { _, _ in }, fetch: { _ in }, cancel: { _ in }
        )
        let transport = try CloudKitSyncTransport(containerIdentifier: "iCloud.com.taisa.app.dev", bundleIdentifier: "com.taisa.app.dev", store: store, runtime: runtime)
        let session = try await transport.bind(expectedFingerprint: fingerprint)
        #expect(session.fingerprint == fingerprint)
    }
}
