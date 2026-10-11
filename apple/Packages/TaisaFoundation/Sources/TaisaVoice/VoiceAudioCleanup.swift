import Foundation
import TaisaStorage

public struct VoiceAudioInventoryItem: Sendable, Equatable {
    public let fileID: String
    public let discoveredAtMS: Int64

    public init(fileID: String, discoveredAtMS: Int64) {
        self.fileID = fileID
        self.discoveredAtMS = discoveredAtMS
    }
}
public protocol VoiceAudioInventorying: Sendable {
    func inventory() async throws -> [VoiceAudioInventoryItem]
    func delete(fileID: String) async throws
}

public protocol VoiceAudioCleanupCheckpointing: Sendable {
    func checkpointCleanup(
        turnID: String,
        fileID: String,
        completedAtMS: Int64?
    ) async throws
}

public struct VoiceAudioCleanupReport: Sendable, Equatable, CustomStringConvertible {
    public let retainedCount: Int
    public let quarantinedCount: Int
    public let deletedCount: Int
    public let retryCount: Int

    public var description: String {
        "VoiceAudioCleanupReport(retained: \(retainedCount), quarantined: \(quarantinedCount), deleted: \(deletedCount), retry: \(retryCount))"
    }
}

/// Reconciles protected audio by opaque identity. Paths and conversation content
/// never enter its inputs, report, or diagnostic representation.
public struct VoiceAudioCleanup: Sendable {
    private let inventory: any VoiceAudioInventorying
    private let checkpoints: any VoiceAudioCleanupCheckpointing
    private let orphanQuarantineMS: Int64

    public init(
        inventory: any VoiceAudioInventorying,
        checkpoints: any VoiceAudioCleanupCheckpointing,
        orphanQuarantineMS: Int64 = 24 * 60 * 60 * 1_000
    ) {
        self.inventory = inventory
        self.checkpoints = checkpoints
        self.orphanQuarantineMS = max(0, orphanQuarantineMS)
    }

    public func reconcile(
        turns: [VoiceTurnRecord],
        nowMS: Int64
    ) async -> VoiceAudioCleanupReport {
        guard let items = try? await inventory.inventory() else {
            return .init(retainedCount: 0, quarantinedCount: 0, deletedCount: 0, retryCount: 1)
        }

        let turnsByAudioID = Dictionary(
            turns.compactMap { turn in turn.audioFileID.map { ($0, turn) } },
            uniquingKeysWith: { first, _ in first }
        )
        var retained = 0
        var quarantined = 0
        var deleted = 0
        var retries = 0

        for item in items.sorted(by: { $0.fileID < $1.fileID }) {
            if let turn = turnsByAudioID[item.fileID] {
                guard shouldDelete(turn) else {
                    retained += 1
                    continue
                }
                do {
                    try await inventory.delete(fileID: item.fileID)
                    try await checkpoints.checkpointCleanup(
                        turnID: turn.id, fileID: item.fileID, completedAtMS: nowMS
                    )
                    deleted += 1
                } catch {
                    retries += 1
                    try? await checkpoints.checkpointCleanup(
                        turnID: turn.id, fileID: item.fileID, completedAtMS: nil
                    )
                }
            } else if isQuarantined(item, nowMS: nowMS) {
                quarantined += 1
            } else {
                do {
                    try await inventory.delete(fileID: item.fileID)
                    deleted += 1
                } catch {
                    retries += 1
                }
            }
        }

        return .init(
            retainedCount: retained,
            quarantinedCount: quarantined,
            deletedCount: deleted,
            retryCount: retries
        )
    }

    private func shouldDelete(_ turn: VoiceTurnRecord) -> Bool {
        turn.state.isTerminal || turn.state == .discarded
    }

    private func isQuarantined(_ item: VoiceAudioInventoryItem, nowMS: Int64) -> Bool {
        let age = nowMS >= item.discoveredAtMS ? nowMS - item.discoveredAtMS : 0
        return age < orphanQuarantineMS
    }
}
