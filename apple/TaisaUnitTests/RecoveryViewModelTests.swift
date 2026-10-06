import XCTest
import SwiftUI
import TaisaRecovery
import TaisaSecurity
import TaisaStorage
@testable import Taisa

@MainActor
final class RecoveryViewModelTests: XCTestCase {
    // Break caught: an unauthenticated caller can submit or reveal recovery material.
    func testAuthenticationFailureNeverAcceptsKey() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let model = RecoveryViewModel(backend: fixture.backend, authenticate: { false })
        await model.beginBackup()
        XCTAssertEqual(model.state, .failure)
        await model.submitKey(try RecoveryKey.generate().formatted)
        XCTAssertNil(model.document)
        XCTAssertFalse(model.acceptsKey)
    }

    // Break caught: archive publication before verification or stale export after cancel.
    func testBackupExportAndCancellation() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        XCTAssertEqual(model.state, .idle)
        await model.beginBackup()
        XCTAssertEqual(model.state, .awaitingKey)
        await model.submitKey(try RecoveryKey.generate().formatted)
        XCTAssertEqual(model.state, .exportReady)
        XCTAssertNotNil(model.document)
        await model.cancel()
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.document)
        XCTAssertTrue(try fixture.transferFiles().isEmpty)
    }

    // Break caught: wrong-key failure loses retry or bypasses explicit replacement.
    func testWrongKeyRetryAndExplicitReplacement() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let key = try RecoveryKey.generate()
        let archive = fixture.root.appendingPathComponent("source.taisa-backup")
        _ = try await fixture.snapshot.createPortableArchive(at: archive, recoveryKey: key)
        let model = fixture.model()
        await model.selectImport(archive)
        XCTAssertEqual(model.state, .importSelected)
        await model.authenticateImport()
        await model.submitKey(try RecoveryKey.generate().formatted)
        XCTAssertEqual(model.state, .awaitingKey)
        XCTAssertNil(model.document)
        await model.submitKey(key.formatted)
        XCTAssertEqual(model.state, .confirmation)
        XCTAssertEqual(model.replacementWarning, "Restoring replaces this device’s current Taisa data")
        XCTAssertTrue(model.divergenceWarning.contains("independently"))
        await model.confirmRestore(replace: false)
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(try fixture.transferFiles().isEmpty)
        await model.selectImport(archive)
        await model.authenticateImport()
        await model.submitKey(key.formatted)
        await model.confirmRestore(replace: true)
        XCTAssertEqual(model.state, .success)
        XCTAssertTrue(try fixture.transferFiles().isEmpty)
        _ = try await fixture.backend.openStore()
    }

    // Break caught: double tap starts concurrent work or late auth revives a hidden scene.
    func testDoubleTapAndInactiveRedaction() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let gate = AuthenticationGate()
        let model = RecoveryViewModel(backend: fixture.backend, authenticate: { await gate.wait() })
        let first = Task { await model.beginBackup() }
        await Task.yield()
        while !gate.waiting { await Task.yield() }
        XCTAssertTrue(model.isBusy)
        await model.beginBackup()
        await model.sceneBecameInactive()
        gate.finish()
        await first.value
        XCTAssertTrue(model.isShielded)
        XCTAssertFalse(model.acceptsKey)
        XCTAssertNil(model.document)
        model.sceneBecameActive()
        XCTAssertEqual(model.state, .idle)
    }

    func testGeneratedKeyRequiresSavedCopiesAndReentry() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.beginBackup()
        try model.generateRecoveryKey()
        let key = try XCTUnwrap(model.ceremonyKey)
        await model.completeCeremony(enteredKey: key, passwordsSaved: false, offlineSaved: true)
        XCTAssertNil(model.document)
        await model.completeCeremony(enteredKey: key, passwordsSaved: true, offlineSaved: true)
        XCTAssertEqual(model.state, .exportReady)
        XCTAssertNil(model.ceremonyKey)
        await model.exportFinished(success: true)
        XCTAssertEqual(model.state, .success)
        XCTAssertNil(model.document)
    }

    func testCancelledCreationNeverPublishesAndCleansPrivateFiles() async throws {
        let audio = PausedAudioGuard()
        let fixture = try await RecoveryFixture(audioGuard: audio)
        defer { fixture.remove() }
        let model = fixture.model()
        await model.beginBackup()
        let text = try RecoveryKey.generate().formatted
        let creating = Task { await model.submitKey(text) }
        while !(await audio.started) { await Task.yield() }
        XCTAssertEqual(model.state, .creating)
        XCTAssertTrue(model.isBusy)
        await model.submitKey(text)
        await model.cancel()
        await creating.value
        XCTAssertNil(model.document)
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(try fixture.transferFiles().isEmpty)
    }

    func testAuthenticationSystemInterruptionShieldsWithoutDiscardingSuccessfulAuthentication() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let gate = AuthenticationGate()
        let model = RecoveryViewModel(backend: fixture.backend, authenticate: { await gate.wait() })
        let first = Task { await model.beginBackup() }
        while !gate.waiting { await Task.yield() }
        model.shieldForSystemInterruption()
        gate.finish()
        await first.value
        XCTAssertTrue(model.isShielded)
        XCTAssertFalse(model.acceptsKey)
        model.sceneBecameActive()
        XCTAssertTrue(model.acceptsKey)
        await model.sceneBecameInactive()
        XCTAssertFalse(model.acceptsKey)
    }

    func testManualSaveCanReturnFromPasswordsOnlyAfterFreshAuthentication() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let decision = AuthenticationDecision()
        let model = RecoveryViewModel(backend: fixture.backend, authenticate: { decision.allowed })
        await model.beginBackup()
        try model.generateRecoveryKey()
        let original = try XCTUnwrap(model.ceremonyKey)
        await model.sceneBecameInactive()
        XCTAssertNil(model.ceremonyKey)
        model.sceneBecameActive()
        XCTAssertNil(model.ceremonyKey)
        decision.allowed = false
        await model.resumeCeremony()
        XCTAssertNil(model.ceremonyKey)
        XCTAssertFalse(model.canStart, "Suspended key setup must be resumed or cancelled before another transfer")
        decision.allowed = true
        await model.resumeCeremony()
        XCTAssertEqual(model.ceremonyKey, original)
        await model.completeCeremony(enteredKey: original, passwordsSaved: true, offlineSaved: true)
        XCTAssertEqual(model.state, .exportReady)
        await model.cancel()
    }

    func testNarrowIPadLargestTypeRender() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        let host = UIHostingController(rootView: RecoveryView(model: model)
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.scenePhase, .active))
        host.traitOverrides.userInterfaceIdiom = .pad
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 720))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.width, 375)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in
            host.view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "recovery-narrow-ipad-accessibility5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }

    func testDuplicateExporterCompletionCannotEraseSuccess() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        for _ in 0..<20 {
            await model.beginBackup()
            await model.submitKey(try RecoveryKey.generate().formatted)
            let first = Task { await model.exportFinished(success: true) }
            let dismissal = Task { await model.exportFinished(success: false) }
            await first.value; await dismissal.value
            XCTAssertEqual(model.state, .success)
        }
    }

    func testBackgroundDuringConfirmedRestoreRetainsTruthfulOutcome() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let key = try RecoveryKey.generate()
        let archive = fixture.root.appendingPathComponent("restore.taisa-backup")
        _ = try await fixture.snapshot.createPortableArchive(at: archive, recoveryKey: key)
        let model = fixture.model()
        await model.selectImport(archive); await model.authenticateImport(); await model.submitKey(key.formatted)
        let readerStarted = DispatchSemaphore(value: 0)
        let releaseReader = DispatchSemaphore(value: 0)
        let store = try await fixture.backend.openStore()
        let reader = Task { try await store.read { _ in
            readerStarted.signal(); releaseReader.wait(); return true
        } }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { readerStarted.wait(); continuation.resume() }
        }
        let restoring = Task { await model.confirmRestore(replace: true) }
        while model.state != .restoring { await Task.yield() }
        let inactive = Task { await model.sceneBecameInactive() }
        while !model.isShielded { await Task.yield() }
        releaseReader.signal()
        _ = try await reader.value
        await restoring.value; await inactive.value
        model.sceneBecameActive()
        XCTAssertEqual(model.state, .success)
        XCTAssertEqual(model.message, "Backup restored. Stored securely on this device.")
    }

    func testExportFailureIsReportedAndPrivateArchiveRemoved() async throws {
        let fixture = try await RecoveryFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.beginBackup()
        await model.submitKey(try RecoveryKey.generate().formatted)
        await model.exportFinished(success: false, failed: true)
        XCTAssertEqual(model.state, .failure)
        XCTAssertEqual(model.message, "Encrypted backup export failed. Create a backup and try again.")
        XCTAssertNil(model.document)
        XCTAssertTrue(try fixture.transferFiles().isEmpty)
    }
}

@MainActor private final class AuthenticationDecision { var allowed = true }

@MainActor private final class AuthenticationGate {
    var continuation: CheckedContinuation<Bool, Never>?
    var waiting: Bool { continuation != nil }
    func wait() async -> Bool { await withCheckedContinuation { continuation = $0 } }
    func finish() { continuation?.resume(returning: true); continuation = nil }
}

private actor RecoveryTestKeys: DatabaseKeyStore {
    var key: Data?
    func loadKey() -> Data? { key }
    func saveKey(_ key: Data) { self.key = key }
    func replaceKey(_ key: Data) { self.key = key }
}

private struct NoPendingAudio: AudioExportGuard {
    func assertNoPendingAudioReferences() async throws {}
}

private actor PausedAudioGuard: AudioExportGuard {
    private(set) var started = false
    func assertNoPendingAudioReferences() async throws {
        started = true
        try await Task.sleep(for: .seconds(60))
    }
}

@MainActor private struct RecoveryFixture {
    let root: URL
    let backend: PersonalRecoveryBackend
    let snapshot: SnapshotService
    init(audioGuard: any AudioExportGuard = NoPendingAudio()) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let keys = RecoveryTestKeys()
        let storeURL = root.appendingPathComponent("active.sqlite")
        let store = try await TaisaStore.open(at: storeURL, keyStore: keys)
        snapshot = SnapshotService(store: store, audioGuard: NoPendingAudio(), sourceInstallationID: UUID())
        backend = PersonalRecoveryBackend(storeURL: storeURL, keyStore: keys, installationID: UUID(), transferRoot: root.appendingPathComponent("transfers"), audioGuard: audioGuard)
    }
    func model() -> RecoveryViewModel { RecoveryViewModel(backend: backend, authenticate: { true }) }
    func transferFiles() throws -> [URL] {
        let folder = root.appendingPathComponent("transfers")
        return FileManager.default.fileExists(atPath: folder.path) ? try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) : []
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
