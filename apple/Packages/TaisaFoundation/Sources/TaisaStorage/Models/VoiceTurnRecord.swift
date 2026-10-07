import Foundation

public enum VoiceTurnState: String, Codable, Sendable, CaseIterable {
    case draft, recording, paused, queued, transcribing
    case transcriptClear, transcriptUncertain, awaitingTranscriptConfirmation
    case coaching, completed, noSpeech, recoverableFailure, terminalFailure
    case cancelled, discarded, resumeRequiresConfirmation

    public var isTerminal: Bool {
        switch self {
        case .completed, .noSpeech, .terminalFailure, .discarded: true
        default: false
        }
    }
}

public enum VoiceTurnStage: String, Codable, Sendable, CaseIterable {
    case capture, transcription, coaching, cleanup, finished
}

public enum VoiceTurnCleanupState: String, Codable, Sendable, CaseIterable {
    case notRequired, pending, completed
}

public struct VoiceTurnCleanup: Codable, Sendable, Equatable {
    public let audioFileID: String
    public let completedAtMS: Int64?

    public init(audioFileID: String, completedAtMS: Int64?) {
        self.audioFileID = audioFileID
        self.completedAtMS = completedAtMS
    }
}

public struct VoiceTurnRecord: Codable, Sendable, Equatable, DomainRecord {
    public let id: String
    public let conversationID: String
    public let transcriptionRequestID: String
    public let transcriptionIdempotencyKey: String
    public let coachingRequestID: String
    public let coachingIdempotencyKey: String
    public let state: VoiceTurnState
    public let stage: VoiceTurnStage
    public let audioFileID: String?
    public let audioSHA256: String?
    public let audioDurationMS: Int64?
    public let acceptedTranscript: String?
    public let uncertainTranscript: String?
    public let retryCount: Int
    public let nextRetryAtMS: Int64?
    public let failureCode: String?
    public let transcriptionReceipt: String?
    public let coachingReceipt: String?
    public let userMessageID: String?
    public let assistantMessageID: String?
    public let cleanupState: VoiceTurnCleanupState
    public let createdAtMS: Int64
    public let updatedAtMS: Int64

    public init(
        id: String,
        conversationID: String,
        transcriptionRequestID: String,
        transcriptionIdempotencyKey: String,
        coachingRequestID: String,
        coachingIdempotencyKey: String,
        state: VoiceTurnState,
        stage: VoiceTurnStage,
        audioFileID: String? = nil,
        audioSHA256: String? = nil,
        audioDurationMS: Int64? = nil,
        acceptedTranscript: String? = nil,
        uncertainTranscript: String? = nil,
        retryCount: Int = 0,
        nextRetryAtMS: Int64? = nil,
        failureCode: String? = nil,
        transcriptionReceipt: String? = nil,
        coachingReceipt: String? = nil,
        userMessageID: String? = nil,
        assistantMessageID: String? = nil,
        cleanupState: VoiceTurnCleanupState = .notRequired,
        createdAtMS: Int64,
        updatedAtMS: Int64
    ) {
        self.id = UUIDIdentity.normalizedOrOriginal(id)
        self.conversationID = UUIDIdentity.normalizedOrOriginal(conversationID)
        self.transcriptionRequestID = UUIDIdentity.normalizedOrOriginal(transcriptionRequestID)
        self.transcriptionIdempotencyKey = transcriptionIdempotencyKey
        self.coachingRequestID = UUIDIdentity.normalizedOrOriginal(coachingRequestID)
        self.coachingIdempotencyKey = coachingIdempotencyKey
        self.state = state
        self.stage = stage
        self.audioFileID = audioFileID
        self.audioSHA256 = audioSHA256
        self.audioDurationMS = audioDurationMS
        self.acceptedTranscript = acceptedTranscript
        self.uncertainTranscript = uncertainTranscript
        self.retryCount = retryCount
        self.nextRetryAtMS = nextRetryAtMS
        self.failureCode = failureCode
        self.transcriptionReceipt = transcriptionReceipt
        self.coachingReceipt = coachingReceipt
        self.userMessageID = userMessageID.map(UUIDIdentity.normalizedOrOriginal)
        self.assistantMessageID = assistantMessageID.map(UUIDIdentity.normalizedOrOriginal)
        self.cleanupState = cleanupState
        self.createdAtMS = createdAtMS
        self.updatedAtMS = updatedAtMS
    }

    public func completing(
        acceptedTranscript: String,
        transcriptionReceipt: String,
        coachingReceipt: String,
        userMessageID: String,
        assistantMessageID: String,
        updatedAtMS: Int64
    ) -> VoiceTurnRecord {
        VoiceTurnRecord(
            id: id, conversationID: conversationID,
            transcriptionRequestID: transcriptionRequestID,
            transcriptionIdempotencyKey: transcriptionIdempotencyKey,
            coachingRequestID: coachingRequestID,
            coachingIdempotencyKey: coachingIdempotencyKey,
            state: .completed, stage: .cleanup,
            audioFileID: audioFileID, audioSHA256: audioSHA256,
            audioDurationMS: audioDurationMS, acceptedTranscript: acceptedTranscript,
            retryCount: retryCount, transcriptionReceipt: transcriptionReceipt,
            coachingReceipt: coachingReceipt, userMessageID: userMessageID,
            assistantMessageID: assistantMessageID, cleanupState: .completed,
            createdAtMS: createdAtMS, updatedAtMS: updatedAtMS
        )
    }
}
