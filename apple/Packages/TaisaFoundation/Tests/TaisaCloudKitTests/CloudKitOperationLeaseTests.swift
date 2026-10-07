import Foundation
import Testing
import TaisaSecurity
import TaisaSync
@testable import TaisaCloudKit

private actor LeaseProbe {
    private(set) var started: [String] = []
    private(set) var active = 0
    private(set) var maxActive = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    func run(_ name: String) async {
        started.append(name)
        active += 1
        maxActive = max(maxActive, active)
        let index = started.count
        await withCheckedContinuation { continuations[index] = $0 }
        active -= 1
    }
    func release(_ index: Int) { continuations.removeValue(forKey: index)?.resume() }
}

@Suite(.serialized) struct CloudKitOperationLeaseTests {
    @Test func accountChangesAndRetirementInvalidateOnlyPriorSessions() {
        var binding = CloudKitAccountBinding()
        let first = Data("first-account".utf8), second = Data("second-account".utf8)
        let initialChange = binding.observeAvailable(first)
        #expect(!initialChange)
        let firstSession = SyncAccountSession(fingerprint: first, generation: binding.generation)
        #expect(binding.matches(firstSession))
        let sameAccountChange = binding.observeAvailable(first)
        #expect(!sameAccountChange)
        #expect(binding.matches(firstSession))
        let switched = binding.observeAvailable(second)
        #expect(switched)
        #expect(!binding.matches(firstSession))
        let secondSession = SyncAccountSession(fingerprint: second, generation: binding.generation)
        #expect(binding.matches(secondSession))
        binding.rotateGeneration()
        #expect(!binding.matches(secondSession))
        #expect(binding.fingerprint == second)
        let rebound = SyncAccountSession(fingerprint: second, generation: binding.generation)
        #expect(binding.matches(rebound))
        let signedOut = binding.observeNoAccount()
        #expect(signedOut)
        #expect(!binding.matches(rebound))
        let repeatedSignOut = binding.observeNoAccount()
        #expect(!repeatedSignOut)
    }

    @Test func completingOneUploadCannotDeleteAnotherUploadsCiphertext() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("taisa-assets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try Vault.generate()
        func change() throws -> EncryptedChange {
            let id = UUID()
            return EncryptedChange(id: id.uuidString, envelope: try vault.seal(Data("private".utf8), metadata: .init(vaultID: vault.id, recordID: id, entityType: "message", schemaVersion: 1, tombstone: false)))
        }
        let first = CloudKitAssetLease(root: root), second = CloudKitAssetLease(root: root)
        let firstRecord = try CloudRecordMapper.makeRecord(change(), assetDirectory: first.directory)
        let secondRecord = try CloudRecordMapper.makeRecord(change(), assetDirectory: second.directory)
        #expect(try CloudRecordMapper.change(from: firstRecord).envelope.ciphertext.count >= 28)
        first.cleanup()
        #expect(throws: CloudRecordMappingError.self) { _ = try CloudRecordMapper.change(from: firstRecord) }
        #expect(try CloudRecordMapper.change(from: secondRecord).envelope.ciphertext.count >= 28)
        second.cleanup()
        #expect(throws: CloudRecordMappingError.self) { _ = try CloudRecordMapper.change(from: secondRecord) }
    }

    private func waitFor(_ count: Int, in probe: LeaseProbe) async {
        while await probe.started.count < count { await Task.yield() }
    }

    @Test func completeSendOperationsAreExclusive() async throws {
        let isolation = CloudKitOperationIsolation(), probe = LeaseProbe()
        let first = Task { try await isolation.run { await probe.run("send-1") } }
        await waitFor(1, in: probe)
        let second = Task { try await isolation.run { await probe.run("send-2") } }
        for _ in 0..<100 { await Task.yield() }
        #expect(await probe.started == ["send-1"])
        await probe.release(1)
        _ = try await first.value
        await waitFor(2, in: probe)
        await probe.release(2)
        _ = try await second.value
        #expect(await probe.maxActive == 1)
    }

    @Test func fetchWaitsForSendToFinish() async throws {
        let isolation = CloudKitOperationIsolation(), probe = LeaseProbe()
        let send = Task { try await isolation.run { await probe.run("send") } }
        await waitFor(1, in: probe)
        let fetch = Task { try await isolation.run { await probe.run("fetch") } }
        for _ in 0..<100 { await Task.yield() }
        #expect(await probe.started == ["send"])
        await probe.release(1)
        _ = try await send.value
        await waitFor(2, in: probe)
        await probe.release(2)
        _ = try await fetch.value
        #expect(await probe.started == ["send", "fetch"])
        #expect(await probe.maxActive == 1)
    }

    @Test func cancelledQueuedOperationCannotRunOrBlockNextOperation() async throws {
        let isolation = CloudKitOperationIsolation(), probe = LeaseProbe()
        let first = Task { try await isolation.run { await probe.run("send") } }
        await waitFor(1, in: probe)
        let cancelled = Task { try await isolation.run { await probe.run("cancelled") } }
        cancelled.cancel()
        await probe.release(1)
        _ = try await first.value
        do { _ = try await cancelled.value; Issue.record("Cancelled operation ran") }
        catch is CancellationError { }
        let next = Task { try await isolation.run { await probe.run("fetch") } }
        await waitFor(2, in: probe)
        await probe.release(2)
        _ = try await next.value
        #expect(await probe.started == ["send", "fetch"])
    }

    @Test func cancelledInflightOperationCannotReturnSuccess() async throws {
        let isolation = CloudKitOperationIsolation(), probe = LeaseProbe()
        let send = Task { try await isolation.run { await probe.run("send") } }
        await waitFor(1, in: probe)
        send.cancel()
        await probe.release(1)
        do { _ = try await send.value; Issue.record("Cancelled send returned success") }
        catch is CancellationError { }
    }
}
