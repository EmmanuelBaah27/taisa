import Foundation

public struct AudioMeterSample: Sendable, Equatable {
    public let averagePower: Float
    public let peakPower: Float

    public init(averagePower: Float, peakPower: Float) {
        self.averagePower = averagePower
        self.peakPower = peakPower
    }
}

public struct AudioRecordingSummary: Sendable, Equatable {
    public let duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = duration
    }
}

public enum AudioCaptureLifecycleEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded
    case routeLost
    case mediaServicesReset
    case storagePressure
    case appBackgrounded
}

public enum AudioCapturePauseReason: Sendable, Equatable {
    case user
    case interruption
    case appLifecycle
}

public enum AudioCaptureBlockReason: Sendable, Equatable {
    case routeUnavailable
    case mediaServicesReset
    case storagePressure
}

public enum AudioCaptureEvent: Sendable, Equatable {
    case started(turnID: UUID, fileID: UUID)
    case paused(turnID: UUID, reason: AudioCapturePauseReason)
    case resumed(turnID: UUID)
    case blocked(turnID: UUID, reason: AudioCaptureBlockReason)
    case finalized(turnID: UUID, fileID: UUID)
    case finalizedAudioPreserved(turnID: UUID, fileID: UUID)
    case cancelledAudioPreserved(turnID: UUID, fileID: UUID)
    case discarded(turnID: UUID, fileID: UUID)
}

public enum AudioCaptureError: Error, Sendable, Equatable {
    case permissionDenied
    case turnAlreadyOwned(expected: UUID, received: UUID)
    case noActiveCapture
    case invalidState
    case audioNotFinalized
    case unsupportedPlatform
}

public actor AudioCaptureService {
    private enum State {
        case idle
        case recording(PendingAudioFile)
        case paused(PendingAudioFile)
        case blocked(PendingAudioFile)
        case finalized(PendingAudioFile, FinalizedAudio)
        case cancelled(PendingAudioFile)
        case discarded(UUID)
    }

    private let session: any AudioSessionAdapting
    private let recorder: any AudioRecorderAdapting
    private let files: any AudioFileStoring
    private var turnID: UUID?
    private var state: State = .idle

    public init(
        session: any AudioSessionAdapting,
        recorder: any AudioRecorderAdapting,
        files: any AudioFileStoring
    ) {
        self.session = session
        self.recorder = recorder
        self.files = files
    }

    @discardableResult
    public func start(turnID: UUID) async throws -> PendingAudioFile {
        if self.turnID != nil {
            try requireOwned(turnID)
            if let pending = pendingFile { return pending }
            throw AudioCaptureError.invalidState
        }

        guard await session.requestRecordPermission() else {
            throw AudioCaptureError.permissionDenied
        }
        let pending = try await files.allocate(turnID: turnID)
        do {
            try await session.activate()
            try await recorder.start(at: pending.url)
        } catch {
            try? await files.delete(pending)
            await session.deactivate()
            throw error
        }
        self.turnID = turnID
        state = .recording(pending)
        return pending
    }

    public func pause(turnID: UUID) async throws {
        try requireOwned(turnID)
        switch state {
        case .recording(let pending):
            await recorder.pause()
            state = .paused(pending)
        case .paused, .blocked:
            return
        default:
            throw AudioCaptureError.invalidState
        }
    }

    public func resume(turnID: UUID) async throws {
        try requireOwned(turnID)
        switch state {
        case .paused(let pending), .blocked(let pending):
            try await session.activate()
            try await recorder.resume()
            state = .recording(pending)
        case .recording:
            return
        default:
            throw AudioCaptureError.invalidState
        }
    }

    public func finalize(turnID: UUID) async throws -> FinalizedAudio {
        try requireOwned(turnID)
        if case .finalized(_, let audio) = state { return audio }
        guard let pending = pendingFile else { throw AudioCaptureError.invalidState }
        let summary = try await recorder.stop()
        let audio = try await files.finalize(pending, duration: summary.duration)
        state = .finalized(pending, audio)
        await session.deactivate()
        return audio
    }

    public func cancel(turnID: UUID) async throws -> AudioCaptureEvent {
        try requireOwned(turnID)
        if case .cancelled(let pending) = state {
            return .cancelledAudioPreserved(turnID: turnID, fileID: pending.fileID)
        }
        if case .finalized(let pending, _) = state {
            return .cancelledAudioPreserved(turnID: turnID, fileID: pending.fileID)
        }
        guard let pending = pendingFile else { throw AudioCaptureError.invalidState }
        await recorder.cancel()
        await session.deactivate()
        state = .cancelled(pending)
        return .cancelledAudioPreserved(turnID: turnID, fileID: pending.fileID)
    }

    public func discard(turnID: UUID) async throws -> AudioCaptureEvent {
        try requireOwned(turnID)
        if case .discarded(let fileID) = state {
            return .discarded(turnID: turnID, fileID: fileID)
        }
        guard let pending = pendingFile else { throw AudioCaptureError.invalidState }
        await recorder.cancel()
        await session.deactivate()
        try await files.delete(pending)
        state = .discarded(pending.fileID)
        return .discarded(turnID: turnID, fileID: pending.fileID)
    }

    public func release(turnID: UUID) throws {
        guard self.turnID != nil else {
            state = .idle
            return
        }
        try requireOwned(turnID)
        switch state {
        case .finalized, .cancelled, .discarded:
            self.turnID = nil
            state = .idle
        case .idle, .recording, .paused, .blocked:
            throw AudioCaptureError.invalidState
        }
    }

    public func meter(turnID: UUID) async throws -> AudioMeterSample {
        try requireOwned(turnID)
        guard case .recording = state else { throw AudioCaptureError.invalidState }
        return await recorder.meter()
    }

    public func audioReadyForUpload(turnID: UUID) throws -> FinalizedAudio {
        try requireOwned(turnID)
        guard case .finalized(_, let audio) = state else {
            throw AudioCaptureError.audioNotFinalized
        }
        return audio
    }

    public func handle(_ event: AudioCaptureLifecycleEvent, turnID: UUID) async throws -> AudioCaptureEvent {
        try requireOwned(turnID)
        switch event {
        case .interruptionBegan:
            if case .recording(let pending) = state {
                await recorder.pause()
                state = .paused(pending)
            }
            return .paused(turnID: turnID, reason: .interruption)
        case .appBackgrounded:
            if case .recording(let pending) = state {
                await recorder.pause()
                state = .paused(pending)
            }
            return .paused(turnID: turnID, reason: .appLifecycle)
        case .interruptionEnded:
            return .paused(turnID: turnID, reason: .interruption)
        case .routeLost:
            if let pending = pendingFile, !isFinalized {
                if case .recording = state { await recorder.pause() }
                state = .blocked(pending)
            }
            return .blocked(turnID: turnID, reason: .routeUnavailable)
        case .mediaServicesReset:
            if let pending = pendingFile, !isFinalized {
                await recorder.cancel()
                await session.deactivate()
                state = .blocked(pending)
            }
            return .blocked(turnID: turnID, reason: .mediaServicesReset)
        case .storagePressure:
            if case .finalized(_, let audio) = state {
                return .finalizedAudioPreserved(turnID: turnID, fileID: audio.fileID)
            }
            if let pending = pendingFile {
                if case .recording = state { await recorder.pause() }
                state = .blocked(pending)
            }
            return .blocked(turnID: turnID, reason: .storagePressure)
        }
    }

    private var pendingFile: PendingAudioFile? {
        switch state {
        case .recording(let file), .paused(let file), .blocked(let file), .cancelled(let file), .finalized(let file, _):
            return file
        case .idle, .discarded:
            return nil
        }
    }

    private var isFinalized: Bool {
        if case .finalized = state { return true }
        return false
    }

    private func requireOwned(_ received: UUID) throws {
        guard let expected = turnID else { throw AudioCaptureError.noActiveCapture }
        guard expected == received else {
            throw AudioCaptureError.turnAlreadyOwned(expected: expected, received: received)
        }
    }
}
