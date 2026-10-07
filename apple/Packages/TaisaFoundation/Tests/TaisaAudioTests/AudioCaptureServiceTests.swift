import Foundation
import Testing
@testable import TaisaAudio

@Suite("Recoverable audio capture")
struct AudioCaptureServiceTests {
    @Test("pause and resume keep one turn, file, and recording timeline")
    func pauseAndResumeKeepOneTurnAndOneTimeline() async throws {
        let session = SessionSpy()
        let recorder = RecorderSpy()
        let files = FileStoreSpy()
        let service = AudioCaptureService(session: session, recorder: recorder, files: files)
        let turnID = UUID()

        let started = try await service.start(turnID: turnID)
        try await service.pause(turnID: turnID)
        try await service.resume(turnID: turnID)
        let finalized = try await service.finalize(turnID: turnID)

        #expect(started.turnID == turnID)
        #expect(finalized.fileID == started.fileID)
        #expect(await recorder.startCount == 1)
        #expect(await recorder.pauseCount == 1)
        #expect(await recorder.resumeCount == 1)
        #expect(await files.allocationCount == 1)
    }

    @Test("interruption and route loss never create another recording")
    func interruptionAndRouteLossNeverSilentlyCreateANewRecording() async throws {
        let recorder = RecorderSpy()
        let service = AudioCaptureService(session: SessionSpy(), recorder: recorder, files: FileStoreSpy())
        let turnID = UUID()
        _ = try await service.start(turnID: turnID)

        let interrupted = try await service.handle(.interruptionBegan, turnID: turnID)
        let routeLost = try await service.handle(.routeLost, turnID: turnID)

        #expect(interrupted == .paused(turnID: turnID, reason: .interruption))
        #expect(routeLost == .blocked(turnID: turnID, reason: .routeUnavailable))
        #expect(await recorder.startCount == 1)
        #expect(await recorder.pauseCount == 1)
    }

    @Test("low storage preserves finalized audio and blocks incomplete upload")
    func lowStoragePreservesValidFinalizedAudioAndBlocksIncompleteUpload() async throws {
        let files = FileStoreSpy()
        let service = AudioCaptureService(session: SessionSpy(), recorder: RecorderSpy(), files: files)
        let turnID = UUID()
        _ = try await service.start(turnID: turnID)
        let finalized = try await service.finalize(turnID: turnID)

        let event = try await service.handle(.storagePressure, turnID: turnID)

        #expect(event == .finalizedAudioPreserved(turnID: turnID, fileID: finalized.fileID))
        #expect(try await service.audioReadyForUpload(turnID: turnID) == finalized)
        #expect(await files.deleteCount == 0)

        let other = AudioCaptureService(session: SessionSpy(), recorder: RecorderSpy(), files: FileStoreSpy())
        let incompleteTurnID = UUID()
        _ = try await other.start(turnID: incompleteTurnID)
        await #expect(throws: AudioCaptureError.audioNotFinalized) {
            _ = try await other.audioReadyForUpload(turnID: incompleteTurnID)
        }
    }

    @Test("permission is requested only by start and a turn cannot be replaced")
    func permissionAndOwnershipAreDeliberate() async throws {
        let session = SessionSpy()
        let service = AudioCaptureService(session: session, recorder: RecorderSpy(), files: FileStoreSpy())
        let firstTurnID = UUID()
        let otherTurnID = UUID()

        await #expect(throws: AudioCaptureError.noActiveCapture) {
            try await service.pause(turnID: firstTurnID)
        }
        #expect(await session.permissionRequestCount == 0)

        _ = try await service.start(turnID: firstTurnID)
        _ = try await service.start(turnID: firstTurnID)
        #expect(await session.permissionRequestCount == 1)
        await #expect(throws: AudioCaptureError.turnAlreadyOwned(expected: firstTurnID, received: otherTurnID)) {
            _ = try await service.start(turnID: otherTurnID)
        }
    }

    @Test("discard is terminal, deletes once, and is idempotent")
    func discardDeletesOnce() async throws {
        let files = FileStoreSpy()
        let service = AudioCaptureService(session: SessionSpy(), recorder: RecorderSpy(), files: files)
        let turnID = UUID()
        _ = try await service.start(turnID: turnID)

        let first = try await service.discard(turnID: turnID)
        let replay = try await service.discard(turnID: turnID)

        #expect(first == replay)
        #expect(await files.deleteCount == 1)
        await #expect(throws: AudioCaptureError.audioNotFinalized) {
            _ = try await service.audioReadyForUpload(turnID: turnID)
        }
    }

    @Test("protected file store finalizes immutable upload metadata")
    func protectedFileStoreFinalizesMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProtectedAudioFileStore(directory: directory)
        let pending = try await store.allocate(turnID: UUID())
        try Data("audio".utf8).write(to: pending.url)

        let finalized = try await store.finalize(pending, duration: 1.5)

        #expect(finalized.byteCount == 5)
        #expect(finalized.duration == 1.5)
        #expect(finalized.sha256 == "6ed8919ce20490a5e3ad8630a4fab69475297abd07db73918dd5f36fcfaeb11b")
        #expect(try pending.url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test("audio session notifications map to content-free lifecycle events")
    func audioSessionNotificationsMapToLifecycleEvents() {
        let interruption = Notification.Name("test.interruption")
        let route = Notification.Name("test.route")
        let reset = Notification.Name("test.reset")
        let mapper = AudioSessionNotificationMapper(
            interruption: interruption, routeChange: route, mediaServicesReset: reset,
            interruptionTypeKey: "type", routeChangeReasonKey: "reason",
            interruptionBeganValue: 1, oldDeviceUnavailableValue: 2
        )

        #expect(mapper.event(for: .init(name: interruption, userInfo: ["type": 1])) == .interruptionBegan)
        #expect(mapper.event(for: .init(name: interruption, userInfo: ["type": 0])) == .interruptionEnded)
        #expect(mapper.event(for: .init(name: route, userInfo: ["reason": 2])) == .routeLost)
        #expect(mapper.event(for: .init(name: route, userInfo: ["reason": 1])) == nil)
        #expect(mapper.event(for: .init(name: reset)) == .mediaServicesReset)
    }
}

private actor SessionSpy: AudioSessionAdapting {
    private(set) var permissionRequestCount = 0
    func requestRecordPermission() async -> Bool {
        permissionRequestCount += 1
        return true
    }
    func activate() async throws {}
    func deactivate() async {}
}

private actor RecorderSpy: AudioRecorderAdapting {
    private(set) var startCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0

    func start(at url: URL) async throws { startCount += 1 }
    func pause() async { pauseCount += 1 }
    func resume() async throws { resumeCount += 1 }
    func stop() async throws -> AudioRecordingSummary {
        AudioRecordingSummary(duration: 4.25)
    }
    func cancel() async {}
    func meter() async -> AudioMeterSample { .init(averagePower: -18, peakPower: -6) }
}

private actor FileStoreSpy: AudioFileStoring {
    private(set) var allocationCount = 0
    private(set) var deleteCount = 0

    func allocate(turnID: UUID) async throws -> PendingAudioFile {
        allocationCount += 1
        return PendingAudioFile(turnID: turnID, fileID: UUID(), url: URL(fileURLWithPath: "/tmp/taisa-test-audio.m4a"))
    }

    func finalize(_ pending: PendingAudioFile, duration: TimeInterval) async throws -> FinalizedAudio {
        FinalizedAudio(fileID: pending.fileID, url: pending.url, duration: duration, byteCount: 64, sha256: String(repeating: "a", count: 64))
    }

    func delete(_ pending: PendingAudioFile) async throws { deleteCount += 1 }
}
