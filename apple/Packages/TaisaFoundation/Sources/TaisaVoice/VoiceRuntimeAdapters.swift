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

public protocol VoiceFinalizedAudioLoading: Sendable {
    func audio(for turn: VoiceTurnRecord) async throws -> FinalizedAudio
}

public actor AudioCaptureController: VoiceCaptureControlling, VoiceAudioDeleting, VoiceFinalizedAudioLoading {
    private let service: AudioCaptureService
    private let files: any AudioFileStoring
    private let lifecycle: (any AudioSessionLifecycleObserving)?
    private var lifecycleTask: Task<Void, Never>?
    private let eventStream: AsyncStream<AudioCaptureEvent>
    private let eventContinuation: AsyncStream<AudioCaptureEvent>.Continuation

    public init(
        service: AudioCaptureService,
        files: any AudioFileStoring,
        lifecycle: (any AudioSessionLifecycleObserving)? = nil
    ) {
        (eventStream, eventContinuation) = AsyncStream.makeStream(
            of: AudioCaptureEvent.self, bufferingPolicy: .bufferingNewest(8)
        )
        self.service = service
        self.files = files
        self.lifecycle = lifecycle
    }

    public func events() -> AsyncStream<AudioCaptureEvent> { eventStream }

    public func start(turnID: UUID) async throws {
        _ = try await service.start(turnID: turnID)
        lifecycleTask?.cancel()
        guard let lifecycle else { return }
        lifecycleTask = Task {
            for await event in lifecycle.events() {
                guard !Task.isCancelled else { return }
                if let result = try? await service.handle(event, turnID: turnID) {
                    eventContinuation.yield(result)
                }
            }
        }
    }
    public func pause(turnID: UUID) async throws { try await service.pause(turnID: turnID) }
    public func resume(turnID: UUID) async throws { try await service.resume(turnID: turnID) }
    public func finalize(turnID: UUID) async throws -> FinalizedVoiceAudio {
        let audio = try await service.finalize(turnID: turnID)
        lifecycleTask?.cancel()
        lifecycleTask = nil
        return .init(
            fileID: audio.fileID.uuidString.lowercased(),
            sha256: audio.sha256,
            durationMS: Int64(audio.duration * 1_000)
        )
    }
    public func cancel(turnID: UUID) async throws {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        _ = try await service.cancel(turnID: turnID)
    }
    public func discard(turnID: UUID) async throws {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        _ = try await service.discard(turnID: turnID)
    }
    public func release(turnID: UUID) async throws {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        try await service.release(turnID: turnID)
    }

    public func audio(for turn: VoiceTurnRecord) async throws -> FinalizedAudio {
        guard let turnID = UUID(uuidString: turn.id),
              let file = turn.audioFileID.flatMap(UUID.init(uuidString:)),
              let durationMS = turn.audioDurationMS else {
            throw AudioCaptureError.audioNotFinalized
        }
        let audio = try await files.load(
            turnID: turnID, fileID: file, duration: TimeInterval(durationMS) / 1_000
        )
        guard audio.sha256 == turn.audioSHA256 else { throw AudioCaptureError.audioNotFinalized }
        return audio
    }

    public func delete(fileID: String) async throws {
        guard let id = UUID(uuidString: fileID) else { throw AudioCaptureError.invalidState }
        try await files.delete(fileID: id)
    }
}
