import Testing
import TaisaStorage
@testable import TaisaVoice

struct VoiceSessionReducerTests {
    private let reducer = VoiceSessionReducer()

    @Test func recordPauseResumeAndSendCheckpointBeforeEveryEffect() throws {
        let draft = turn(state: .draft, stage: .capture)
        let recording = try reducer.reduce(state: draft, command: .startRecording)
        #expect(recording.next.state == .recording)
        #expect(recording.effects == [.checkpoint(recording.next), .startRecording])

        let paused = try reducer.reduce(state: recording.next, command: .pauseRecording)
        #expect(paused.next.state == .paused)
        #expect(paused.effects == [.checkpoint(paused.next), .pauseRecording])

        let resumed = try reducer.reduce(state: paused.next, command: .resumeRecording)
        #expect(resumed.next.state == .recording)
        #expect(resumed.effects == [.checkpoint(resumed.next), .resumeRecording])

        let sent = try reducer.reduce(
            state: resumed.next,
            command: .send(.init(fileID: "local-audio", sha256: "digest", durationMS: 900))
        )
        #expect(sent.next.state == .queued)
        #expect(sent.next.audioFileID == "local-audio")
        #expect(sent.effects == [.checkpoint(sent.next), .startTranscription])
    }

    @Test func clearTranscriptThenCoachingCompletionCommitsBeforeCleanup() throws {
        let transcribing = turn(state: .transcribing, stage: .transcription, audio: true)
        let clear = try reducer.reduce(
            state: transcribing,
            command: .transcriptCompleted(.clear(
                text: "Accepted transcript", receipt: "transcript-receipt",
                userMessageID: "00000000-0000-0000-0000-000000000111"
            ))
        )
        #expect(clear.next.state == .transcriptClear)
        #expect(clear.effects == [.checkpoint(clear.next), .startCoaching])

        let coaching = try reducer.reduce(state: clear.next, command: .coachingBegan)
        let completed = try reducer.reduce(
            state: coaching.next,
            command: .coachingCompleted(
                receipt: "coaching-receipt",
                assistantMessageID: "00000000-0000-0000-0000-000000000112"
            )
        )
        #expect(completed.next.state == .completed)
        #expect(completed.next.coachingReceipt == "coaching-receipt")
        #expect(completed.effects == [.checkpoint(completed.next), .deleteAudio("local-audio")])
    }

    @Test func uncertainTranscriptRequiresExplicitConfirmation() throws {
        let transcribing = turn(state: .transcribing, stage: .transcription, audio: true)
        let uncertain = try reducer.reduce(
            state: transcribing,
            command: .transcriptCompleted(.uncertain(text: "Draft?", receipt: "receipt"))
        )
        #expect(uncertain.next.state == .awaitingTranscriptConfirmation)
        #expect(uncertain.effects == [.checkpoint(uncertain.next), .requestTranscriptConfirmation])

        let confirmed = try reducer.reduce(
            state: uncertain.next,
            command: .confirmTranscript(
                text: "Corrected", userMessageID: "00000000-0000-0000-0000-000000000113"
            )
        )
        #expect(confirmed.next.acceptedTranscript == "Corrected")
        #expect(confirmed.next.uncertainTranscript == nil)
        #expect(confirmed.effects == [.checkpoint(confirmed.next), .startCoaching])
    }

    @Test func noSpeechCancelAndDiscardRemainDistinct() throws {
        let transcribing = turn(state: .transcribing, stage: .transcription, audio: true)
        let noSpeech = try reducer.reduce(
            state: transcribing,
            command: .transcriptCompleted(.noSpeech(receipt: "receipt"))
        )
        #expect(noSpeech.next.state == .noSpeech)
        #expect(noSpeech.effects == [.checkpoint(noSpeech.next), .deleteAudio("local-audio")])

        let cancelled = try reducer.reduce(state: transcribing, command: .cancel)
        #expect(cancelled.next.state == .cancelled)
        #expect(cancelled.next.audioFileID == "local-audio")
        #expect(cancelled.effects == [.checkpoint(cancelled.next), .cancelWork])

        let discarded = try reducer.reduce(state: transcribing, command: .discard)
        #expect(discarded.next.state == .discarded)
        #expect(discarded.effects == [
            .checkpoint(discarded.next), .cancelWork, .deleteAudio("local-audio"),
        ])
    }

    @Test func failureClassificationAndRetryRespectSavedStage() throws {
        let coaching = turn(state: .coaching, stage: .coaching, audio: true)
        let retryable = try reducer.reduce(
            state: coaching, command: .fail(code: "OFFLINE", retryable: true, ambiguous: false)
        )
        #expect(retryable.next.state == .recoverableFailure)
        let retried = try reducer.reduce(state: retryable.next, command: .retry)
        #expect(retried.next.state == .coaching)
        #expect(retried.effects == [.checkpoint(retried.next), .startCoaching])

        let terminal = try reducer.reduce(
            state: coaching, command: .fail(code: "AUTH", retryable: false, ambiguous: false)
        )
        #expect(terminal.next.state == .terminalFailure)

        let ambiguous = try reducer.reduce(
            state: coaching, command: .fail(code: "AMBIGUOUS", retryable: false, ambiguous: true)
        )
        #expect(ambiguous.next.state == .resumeRequiresConfirmation)
        #expect(ambiguous.effects == [.checkpoint(ambiguous.next), .requestResumeConfirmation])
        let approved = try reducer.reduce(state: ambiguous.next, command: .confirmResume)
        #expect(approved.next.state == .coaching)
        #expect(approved.effects == [.checkpoint(approved.next), .startCoaching])

        let cancelled = try reducer.reduce(state: coaching, command: .cancel)
        let resumed = try reducer.reduce(state: cancelled.next, command: .retry)
        #expect(resumed.next.state == .coaching)
        #expect(resumed.effects == [.checkpoint(resumed.next), .startCoaching])
    }

    @Test func cleanupAndNextTurnStayInTheSameConversation() throws {
        let completed = turn(state: .completed, stage: .cleanup, audio: true)
        let cleaned = try reducer.reduce(state: completed, command: .cleanupCompleted)
        #expect(cleaned.next.cleanupState == .completed)
        #expect(cleaned.next.audioFileID == nil)
        #expect(cleaned.effects == [.checkpoint(cleaned.next), .conversationReady])

        let next = turn(
            id: "00000000-0000-0000-0000-000000000099",
            state: .draft, stage: .capture
        )
        let prepared = try reducer.reduce(state: cleaned.next, command: .beginNextTurn(next))
        #expect(prepared.next.conversationID == cleaned.next.conversationID)
        #expect(prepared.effects == [.checkpoint(next)])
    }

    @Test func illegalCommandThrowsWithoutChangingValue() throws {
        let draft = turn(state: .draft, stage: .capture)
        #expect(throws: VoiceSessionReducerError.illegalTransition) {
            _ = try reducer.reduce(state: draft, command: .pauseRecording)
        }
        #expect(draft.state == .draft)
    }

    private func turn(
        id: String = "00000000-0000-0000-0000-000000000101",
        state: VoiceTurnState,
        stage: VoiceTurnStage,
        audio: Bool = false
    ) -> VoiceTurnRecord {
        VoiceTurnRecord(
            id: id,
            conversationID: "00000000-0000-0000-0000-000000000102",
            transcriptionRequestID: "00000000-0000-0000-0000-000000000103",
            transcriptionIdempotencyKey: "transcription-key",
            coachingRequestID: "00000000-0000-0000-0000-000000000104",
            coachingIdempotencyKey: "coaching-key",
            state: state, stage: stage,
            audioFileID: audio ? "local-audio" : nil,
            audioSHA256: audio ? "digest" : nil,
            audioDurationMS: audio ? 900 : nil,
            retryCount: 0,
            cleanupState: audio ? .pending : .notRequired,
            createdAtMS: 1, updatedAtMS: 1
        )
    }
}
