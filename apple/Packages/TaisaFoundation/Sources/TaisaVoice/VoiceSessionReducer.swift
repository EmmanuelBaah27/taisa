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

        case .captureStarted(let fileID):
            try require(state.state == .recording && state.stage == .capture)
            guard UUID(uuidString: fileID) != nil else { throw VoiceSessionReducerError.invalidCommand }
            return checkpoint(copy(
                state, state: .recording, stage: .capture,
                audioFileID: .some(fileID), cleanupState: .pending
            ))

        case .pauseRecording:
            try require(state.state == .recording)
            return transition(copy(state, state: .paused, stage: .capture), .pauseRecording)

        case .resumeRecording:
            try require(state.state == .paused)
            return transition(copy(state, state: .recording, stage: .capture), .resumeRecording)

        case .capturePaused:
            try require(state.state == .recording && state.stage == .capture)
            return checkpoint(copy(state, state: .paused, stage: .capture))

        case .captureFailed(let code):
            try require((state.state == .recording || state.state == .paused) && state.stage == .capture)
            guard !code.isEmpty else { throw VoiceSessionReducerError.invalidCommand }
            let next = copy(
                state, state: .terminalFailure, stage: .cleanup,
                failureCode: .some(code), cleanupState: .pending
            )
            return transition(next, deleteEffect(state))

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
                cleanupState: .pending, assistantMessageID: .some(assistantMessageID)
            ), deleteEffect(state))

        case let .fail(code, retryable, ambiguous):
            guard !state.state.isTerminal, !code.isEmpty else {
                throw VoiceSessionReducerError.illegalTransition
            }
            let nextState: VoiceTurnState = ambiguous
                ? .resumeRequiresConfirmation
                : retryable ? .recoverableFailure : .terminalFailure
            if !ambiguous && !retryable {
                let next = copy(
                    state, state: nextState, stage: .cleanup,
                    failureCode: .some(code), cleanupState: .pending
                )
                return transition(next, deleteEffect(state))
            }
            let next = copy(state, state: nextState, stage: state.stage, failureCode: .some(code))
            return ambiguous ? transition(next, .requestResumeConfirmation) : checkpoint(next)

        case let .scheduleRetry(code, nextRetryAtMS):
            guard !state.state.isTerminal, !code.isEmpty, nextRetryAtMS >= 0 else {
                throw VoiceSessionReducerError.invalidCommand
            }
            return checkpoint(copy(
                state, state: .recoverableFailure, stage: state.stage,
                retryCount: state.retryCount + 1,
                nextRetryAtMS: .some(nextRetryAtMS), failureCode: .some(code)
            ))

        case .retry:
            try require(state.state == .recoverableFailure || state.state == .cancelled)
            switch state.stage {
            case .transcription:
                return transition(copy(
                    state, state: .transcribing, stage: .transcription,
                    nextRetryAtMS: .some(nil)
                ), .startTranscription)
            case .coaching:
                return transition(copy(
                    state, state: .coaching, stage: .coaching,
                    nextRetryAtMS: .some(nil)
                ), .startCoaching)
            default:
                throw VoiceSessionReducerError.illegalTransition
            }

        case .confirmResume:
            try require(state.state == .resumeRequiresConfirmation)
            switch state.stage {
            case .transcription:
                return transition(
                    copy(state, state: .transcribing, stage: .transcription),
                    .authorizeTranscriptionRetry
                )
            case .coaching:
                return transition(
                    copy(state, state: .coaching, stage: .coaching),
                    .authorizeCoachingRetry
                )
            default:
                throw VoiceSessionReducerError.illegalTransition
            }

        case .cancel:
            try require(!state.state.isTerminal)
            return transition(copy(state, state: .cancelled, stage: state.stage), .cancelWork)

        case .discard:
            try require(!state.state.isTerminal)
            let next = copy(state, state: .discarded, stage: .cleanup, cleanupState: .pending)
            var effects: [VoiceSessionEffect] = [.checkpoint(next), .cancelWork]
            if state.stage != .capture {
                effects.append(state.audioFileID.map(VoiceSessionEffect.deleteAudio) ?? .completeCleanup)
            }
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
            return VoiceSessionTransition(
                next: next,
                effects: [.conversationReady, .checkpoint(next)]
            )
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
        state.audioFileID.map(VoiceSessionEffect.deleteAudio) ?? .completeCleanup
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
        retryCount: Int? = nil,
        nextRetryAtMS: Int64?? = nil,
        failureCode: String?? = nil,
        transcriptionReceipt: String?? = nil,
        coachingReceipt: String?? = nil,
        cleanupState: VoiceTurnCleanupState? = nil,
        userMessageID: String?? = nil,
        assistantMessageID: String?? = nil
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
            retryCount: retryCount ?? source.retryCount,
            nextRetryAtMS: resolve(nextRetryAtMS, source.nextRetryAtMS),
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
