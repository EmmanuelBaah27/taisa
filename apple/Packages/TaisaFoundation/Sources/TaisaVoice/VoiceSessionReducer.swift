import Foundation
import TaisaStorage

public enum VoiceSessionReducerError: Error, Sendable, Equatable {
    case illegalTransition
    case invalidCommand
}

public struct VoiceSessionReducer: Sendable {
    public init() {}

    public func reduce(
        state: VoiceTurnRecord,
        command: VoiceSessionCommand
    ) throws -> VoiceSessionTransition {
        switch command {
        case .startRecording:
            try require(state.state == .draft)
            return transition(copy(state, state: .recording, stage: .capture), .startRecording)

        case .pauseRecording:
            try require(state.state == .recording)
            return transition(copy(state, state: .paused, stage: .capture), .pauseRecording)

        case .resumeRecording:
            try require(state.state == .paused)
            return transition(copy(state, state: .recording, stage: .capture), .resumeRecording)

        case .send(let audio):
            try require(state.state == .recording || state.state == .paused)
            guard !audio.fileID.isEmpty, !audio.sha256.isEmpty, audio.durationMS >= 0 else {
                throw VoiceSessionReducerError.invalidCommand
            }
            return transition(copy(
                state, state: .queued, stage: .transcription,
                audioFileID: .some(audio.fileID), audioSHA256: .some(audio.sha256),
                audioDurationMS: .some(audio.durationMS), cleanupState: .pending
            ), .startTranscription)

        case .transcriptionBegan:
            try require(state.state == .queued ||
                        (state.state == .recoverableFailure && state.stage == .transcription))
            return checkpoint(copy(state, state: .transcribing, stage: .transcription))

        case .transcriptCompleted(let outcome):
            try require(state.state == .transcribing)
            switch outcome {
            case let .clear(text, receipt, userMessageID):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !receipt.isEmpty, UUID(uuidString: userMessageID) != nil else {
                    throw VoiceSessionReducerError.invalidCommand
                }
                return transition(copy(
                    state, state: .transcriptClear, stage: .coaching,
                    acceptedTranscript: .some(text), uncertainTranscript: .some(nil),
                    transcriptionReceipt: .some(receipt), userMessageID: .some(userMessageID)
                ), .startCoaching)
            case let .uncertain(text, receipt):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !receipt.isEmpty else { throw VoiceSessionReducerError.invalidCommand }
                return transition(copy(
                    state, state: .awaitingTranscriptConfirmation, stage: .transcription,
                    acceptedTranscript: .some(nil), uncertainTranscript: .some(text),
                    transcriptionReceipt: .some(receipt)
                ), .requestTranscriptConfirmation)
            case let .noSpeech(receipt):
                guard !receipt.isEmpty else { throw VoiceSessionReducerError.invalidCommand }
                return transition(copy(
                    state, state: .noSpeech, stage: .cleanup,
                    transcriptionReceipt: .some(receipt)
                ), deleteEffect(state))
            }

        case let .confirmTranscript(text, userMessageID):
            try require(state.state == .awaitingTranscriptConfirmation)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  UUID(uuidString: userMessageID) != nil else {
                throw VoiceSessionReducerError.invalidCommand
            }
            return transition(copy(
                state, state: .transcriptClear, stage: .coaching,
                acceptedTranscript: .some(text), uncertainTranscript: .some(nil),
                userMessageID: .some(userMessageID)
            ), .startCoaching)

        case .coachingBegan:
            try require(state.state == .transcriptClear ||
                        (state.state == .recoverableFailure && state.stage == .coaching))
            return checkpoint(copy(state, state: .coaching, stage: .coaching))

        case let .coachingCompleted(receipt, assistantMessageID):
            try require(state.state == .coaching)
            guard !receipt.isEmpty, UUID(uuidString: assistantMessageID) != nil else {
                throw VoiceSessionReducerError.invalidCommand
            }
            return transition(copy(
                state, state: .completed, stage: .cleanup,
                coachingReceipt: .some(receipt),
                assistantMessageID: .some(assistantMessageID), cleanupState: .pending
            ), deleteEffect(state))

        case let .fail(code, retryable, ambiguous):
            guard !state.state.isTerminal, !code.isEmpty else {
                throw VoiceSessionReducerError.illegalTransition
            }
            let nextState: VoiceTurnState = ambiguous
                ? .resumeRequiresConfirmation
                : retryable ? .recoverableFailure : .terminalFailure
            let next = copy(state, state: nextState, stage: state.stage, failureCode: .some(code))
            return ambiguous
                ? transition(next, .requestResumeConfirmation)
                : checkpoint(next)

        case .retry:
            try require(state.state == .recoverableFailure || state.state == .cancelled)
            switch state.stage {
            case .transcription:
                return transition(copy(state, state: .transcribing, stage: .transcription), .startTranscription)
            case .coaching:
                return transition(copy(state, state: .coaching, stage: .coaching), .startCoaching)
            default:
                throw VoiceSessionReducerError.illegalTransition
            }

        case .confirmResume:
            try require(state.state == .resumeRequiresConfirmation && state.stage == .coaching)
            return transition(copy(state, state: .coaching, stage: .coaching), .startCoaching)

        case .cancel:
            try require(!state.state.isTerminal)
            return transition(copy(state, state: .cancelled, stage: state.stage), .cancelWork)

        case .discard:
            try require(!state.state.isTerminal)
            let next = copy(state, state: .discarded, stage: .cleanup, cleanupState: .pending)
            var effects: [VoiceSessionEffect] = [.checkpoint(next), .cancelWork]
            if let audio = state.audioFileID { effects.append(.deleteAudio(audio)) }
            return VoiceSessionTransition(next: next, effects: effects)

        case .cleanupCompleted:
            try require(state.state.isTerminal)
            let next = copy(
                state, state: state.state, stage: .finished,
                audioFileID: .some(nil), audioSHA256: .some(nil),
                audioDurationMS: .some(nil), cleanupState: .completed
            )
            return transition(next, .conversationReady)

        case .beginNextTurn(let next):
            try require(state.state.isTerminal && state.stage == .finished)
            guard next.state == .draft, next.stage == .capture,
                  next.conversationID == state.conversationID,
                  next.id != state.id else { throw VoiceSessionReducerError.invalidCommand }
            return checkpoint(next)
        }
    }

    private func require(_ condition: @autoclosure () -> Bool) throws {
        guard condition() else { throw VoiceSessionReducerError.illegalTransition }
    }

    private func checkpoint(_ next: VoiceTurnRecord) -> VoiceSessionTransition {
        VoiceSessionTransition(next: next, effects: [.checkpoint(next)])
    }

    private func transition(
        _ next: VoiceTurnRecord,
        _ effect: VoiceSessionEffect
    ) -> VoiceSessionTransition {
        VoiceSessionTransition(next: next, effects: [.checkpoint(next), effect])
    }

    private func deleteEffect(_ state: VoiceTurnRecord) -> VoiceSessionEffect {
        state.audioFileID.map(VoiceSessionEffect.deleteAudio) ?? .conversationReady
    }

    private func copy(
        _ source: VoiceTurnRecord,
        state: VoiceTurnState,
        stage: VoiceTurnStage,
        audioFileID: String?? = nil,
        audioSHA256: String?? = nil,
        audioDurationMS: Int64?? = nil,
        acceptedTranscript: String?? = nil,
        uncertainTranscript: String?? = nil,
        failureCode: String?? = nil,
        transcriptionReceipt: String?? = nil,
        coachingReceipt: String?? = nil,
        userMessageID: String?? = nil,
        assistantMessageID: String?? = nil,
        cleanupState: VoiceTurnCleanupState? = nil
    ) -> VoiceTurnRecord {
        func resolve<T>(_ override: T??, _ current: T?) -> T? {
            switch override { case .none: current; case .some(let value): value }
        }
        return VoiceTurnRecord(
            id: source.id, conversationID: source.conversationID,
            transcriptionRequestID: source.transcriptionRequestID,
            transcriptionIdempotencyKey: source.transcriptionIdempotencyKey,
            coachingRequestID: source.coachingRequestID,
            coachingIdempotencyKey: source.coachingIdempotencyKey,
            state: state, stage: stage,
            audioFileID: resolve(audioFileID, source.audioFileID),
            audioSHA256: resolve(audioSHA256, source.audioSHA256),
            audioDurationMS: resolve(audioDurationMS, source.audioDurationMS),
            acceptedTranscript: resolve(acceptedTranscript, source.acceptedTranscript),
            uncertainTranscript: resolve(uncertainTranscript, source.uncertainTranscript),
            retryCount: source.retryCount,
            nextRetryAtMS: source.nextRetryAtMS,
            failureCode: resolve(failureCode, source.failureCode),
            transcriptionReceipt: resolve(transcriptionReceipt, source.transcriptionReceipt),
            coachingReceipt: resolve(coachingReceipt, source.coachingReceipt),
            userMessageID: resolve(userMessageID, source.userMessageID),
            assistantMessageID: resolve(assistantMessageID, source.assistantMessageID),
            cleanupState: cleanupState ?? source.cleanupState,
            createdAtMS: source.createdAtMS, updatedAtMS: source.updatedAtMS
        )
    }
}
