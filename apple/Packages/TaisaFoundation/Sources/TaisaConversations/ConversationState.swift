import TaisaStorage

public enum ConversationInput: Sendable, Equatable {
    case voice
    case text(String)
}

public enum ConversationReplyMode: Sendable, Equatable { case voice, text }

public enum ConversationFailure: Error, Sendable, Equatable {
    case invalidInput
    case retryable
    case unavailable
    case noPendingRetry
    case busy
}

public enum ComposerState: Sendable, Equatable {
    case preparingVoice
    case recording
    case paused
    case typing(String)
    case transcribing
    case coaching
    case waitingForReply
    case failure(ConversationFailure)
}

public struct ConversationReply: Sendable, Equatable {
    public let text: String
    public let titleSuggestion: String?

    public init(text: String, titleSuggestion: String?) {
        self.text = text
        self.titleSuggestion = titleSuggestion
    }
}

public struct ConversationCoordinatorSnapshot: Sendable, Equatable {
    public let conversationID: String
    public let composer: ComposerState
    public let latestReply: ConversationReply?
    public let title: String?
    public let titleAuthority: TitleAuthority

    public init(
        conversationID: String,
        composer: ComposerState,
        latestReply: ConversationReply?,
        title: String?,
        titleAuthority: TitleAuthority
    ) {
        self.conversationID = conversationID
        self.composer = composer
        self.latestReply = latestReply
        self.title = title
        self.titleAuthority = titleAuthority
    }
}
