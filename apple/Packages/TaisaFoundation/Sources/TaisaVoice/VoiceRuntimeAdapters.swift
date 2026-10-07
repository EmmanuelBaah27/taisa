import Foundation
import TaisaAudio
import TaisaStorage

public struct RepositoryVoiceTurnCheckpointer: VoiceTurnCheckpointing {
    private let repository: ConversationTurnRepository
    private let deviceID: String
    private let makeMutationID: @Sendable () -> UUID
    private let nowMS: @Sendable () -> Int64

    public init(
        repository: ConversationTurnRepository,
        deviceID: UUID,
        makeMutationID: @escaping @Sendable () -> UUID = UUID.init,
        nowMS: @escaping @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.repository = repository
        self.deviceID = deviceID.uuidString.lowercased()
        self.makeMutationID = makeMutationID
        self.nowMS = nowMS
    }

    public func checkpoint(
        _ record: VoiceTurnRecord,
        messages: [MessageRecord],
        cleanup: VoiceTurnCleanup?
    ) async throws {
        try await repository.checkpoint(
            record,
            messages: messages,
            cleanup: cleanup,
            context: .init(
                id: makeMutationID().uuidString,
                deviceID: deviceID,
                timestamp: nowMS()
            )
        )
    }
}

public actor AudioCaptureController: VoiceCaptureControlling {
    private let service: AudioCaptureService

    public init(service: AudioCaptureService) { self.service = service }

    public func start(turnID: UUID) async throws { _ = try await service.start(turnID: turnID) }
    public func pause(turnID: UUID) async throws { try await service.pause(turnID: turnID) }
    public func resume(turnID: UUID) async throws { try await service.resume(turnID: turnID) }
    public func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        let audio = try await service.finalize(turnID: turnID)
        return .init(
            fileID: audio.fileID.uuidString.lowercased(),
            sha256: audio.sha256,
            durationMS: Int64(audio.duration * 1_000)
        )
    }
    public func cancel(turnID: UUID) async throws { _ = try await service.cancel(turnID: turnID) }
}
