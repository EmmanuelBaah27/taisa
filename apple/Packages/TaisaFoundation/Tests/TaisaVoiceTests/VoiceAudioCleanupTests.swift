import Foundation
import Testing
import TaisaStorage
@testable import TaisaVoice

@Suite("Voice audio cleanup")
struct VoiceAudioCleanupTests {
    @Test("recoverable audio is retained while terminal audio is deleted and checkpointed")
    func retainsRecoverableAndDeletesTerminal() async throws {
        let inventory = CleanupInventorySpy(items: [
            .init(fileID: "recoverable-audio", discoveredAtMS: 0),
            .init(fileID: "terminal-audio", discoveredAtMS: 0),
        ])
        let checkpoints = CleanupCheckpointSpy()
        let cleanup = VoiceAudioCleanup(
            inventory: inventory, checkpoints: checkpoints, orphanQuarantineMS: 100
        )

        let report = await cleanup.reconcile(turns: [
            turn(state: .recoverableFailure, stage: .transcription, audio: "recoverable-audio"),
            turn(state: .completed, stage: .cleanup, audio: "terminal-audio"),
        ], nowMS: 1_000)

        #expect(await inventory.deleted == ["terminal-audio"])
        #expect(await checkpoints.completed == ["terminal-audio"])
        #expect(report.retainedCount == 1)
        #expect(report.deletedCount == 1)
        #expect(report.retryCount == 0)
    }

    @Test("unknown files are quarantined before bounded orphan deletion")
    func quarantinesUnknownFilesBeforeDeletion() async {
        let inventory = CleanupInventorySpy(items: [
            .init(fileID: "recent-orphan", discoveredAtMS: 950),
            .init(fileID: "old-orphan", discoveredAtMS: 100),
        ])
        let cleanup = VoiceAudioCleanup(
            inventory: inventory, checkpoints: CleanupCheckpointSpy(), orphanQuarantineMS: 200
        )

        let report = await cleanup.reconcile(turns: [], nowMS: 1_000)

        #expect(await inventory.deleted == ["old-orphan"])
        #expect(report.quarantinedCount == 1)
        #expect(report.deletedCount == 1)
    }

    @Test("cleanup failure checkpoints a content-free retry")
    func failureCheckpointsRetry() async {
        let inventory = CleanupInventorySpy(
            items: [.init(fileID: "failed-audio", discoveredAtMS: 0)],
            failingIDs: ["failed-audio"]
        )
        let checkpoints = CleanupCheckpointSpy()
        let cleanup = VoiceAudioCleanup(
            inventory: inventory, checkpoints: checkpoints, orphanQuarantineMS: 0
        )

        let report = await cleanup.reconcile(
            turns: [turn(state: .discarded, stage: .cleanup, audio: "failed-audio")],
            nowMS: 1_000
        )

        #expect(await checkpoints.pending == ["failed-audio"])
        #expect(report.retryCount == 1)
        #expect(report.deletedCount == 0)
    }
}

private enum CleanupFailure: Error { case expected }

private actor CleanupInventorySpy: VoiceAudioInventorying {
    let items: [VoiceAudioInventoryItem]
    let failingIDs: Set<String>
    private(set) var deleted: [String] = []

    init(items: [VoiceAudioInventoryItem], failingIDs: Set<String> = []) {
        self.items = items
        self.failingIDs = failingIDs
    }

    func inventory() async throws -> [VoiceAudioInventoryItem] { items }

    func delete(fileID: String) async throws {
        if failingIDs.contains(fileID) { throw CleanupFailure.expected }
        deleted.append(fileID)
    }
}

private actor CleanupCheckpointSpy: VoiceAudioCleanupCheckpointing {
    private(set) var completed: [String] = []
    private(set) var pending: [String] = []

    func checkpointCleanup(turnID: String, fileID: String, completedAtMS: Int64?) async throws {
        if completedAtMS == nil { pending.append(fileID) }
        else { completed.append(fileID) }
    }
}

private func turn(
    state: VoiceTurnState, stage: VoiceTurnStage, audio: String
) -> VoiceTurnRecord {
    VoiceTurnRecord(
        id: UUID().uuidString, conversationID: UUID().uuidString,
        transcriptionRequestID: UUID().uuidString, transcriptionIdempotencyKey: "t",
        coachingRequestID: UUID().uuidString, coachingIdempotencyKey: "c",
        state: state, stage: stage, audioFileID: audio, audioSHA256: "digest",
        audioDurationMS: 1, cleanupState: .pending, createdAtMS: 0, updatedAtMS: 0
    )
}
