public struct ConversationIndexSnapshot: Sendable, Equatable {
    public let drafts: [ConversationDraftRecord]
    public let conversations: [ConversationRecord]
    public let lastMessagePreviews: [String: String]

    public init(
        drafts: [ConversationDraftRecord],
        conversations: [ConversationRecord],
        lastMessagePreviews: [String: String] = [:]
    ) {
        self.drafts = drafts
        self.conversations = conversations
        self.lastMessagePreviews = lastMessagePreviews
    }

    public func lastMessagePreview(for conversationID: String) -> String? {
        lastMessagePreviews[UUIDIdentity.normalizedOrOriginal(conversationID)]
    }
}

public struct ConversationSnapshot: Sendable, Equatable {
    public let conversation: ConversationRecord
    public let visibleMessages: [MessageRecord]
    public let revisions: [MessageRevisionRecord]
    public let drafts: [ConversationDraftRecord]
    public let assistantResponses: [String: AssistantResponseRecord]

    public init(
        conversation: ConversationRecord,
        visibleMessages: [MessageRecord],
        revisions: [MessageRevisionRecord],
        drafts: [ConversationDraftRecord],
        assistantResponses: [String: AssistantResponseRecord] = [:]
    ) {
        self.conversation = conversation
        self.visibleMessages = visibleMessages
        self.revisions = revisions
        self.drafts = drafts
        self.assistantResponses = assistantResponses
    }
}

public struct ConversationCorrection: Sendable, Equatable {
    public let revisionID: String
    public let originalUserMessageID: String
    public let originalAssistantMessageID: String
    public let correctedUserMessage: MessageRecord
    public let regeneratedAssistantMessage: MessageRecord
    public let createdAtMS: Int64

    public init(
        revisionID: String,
        originalUserMessageID: String,
        originalAssistantMessageID: String,
        correctedUserMessage: MessageRecord,
        regeneratedAssistantMessage: MessageRecord,
        createdAtMS: Int64
    ) {
        self.revisionID = UUIDIdentity.normalizedOrOriginal(revisionID)
        self.originalUserMessageID = UUIDIdentity.normalizedOrOriginal(originalUserMessageID)
        self.originalAssistantMessageID = UUIDIdentity.normalizedOrOriginal(originalAssistantMessageID)
        self.correctedUserMessage = correctedUserMessage
        self.regeneratedAssistantMessage = regeneratedAssistantMessage
        self.createdAtMS = createdAtMS
    }
}
