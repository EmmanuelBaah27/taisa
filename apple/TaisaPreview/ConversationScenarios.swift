import Foundation
import SwiftUI
import TaisaConversations
import TaisaPreviewSupport
import TaisaStorage

@MainActor
enum ConversationScenarios {
    static let scenarios: [PreviewScenario] = [
        list("conversation-list.empty", "Conversations empty", state: .empty),
        list("conversation-list.multiple-drafts", "Conversations multiple drafts", state: .content(listSnapshot, isRefreshing: false, issue: nil)),
        list("conversation-list.recovered-draft", "Conversations recovered draft", state: .content(recoveredSnapshot, isRefreshing: false, issue: nil)),
        list("conversation-list.completed-history", "Conversations completed history", state: .content(historySnapshot, isRefreshing: false, issue: nil)),
        composer("conversation.recording", "Conversation recording", .recording),
        composer("conversation.paused", "Conversation paused", .paused),
        composer("conversation.typing", "Conversation typing", .typing("Prepare my performance review")),
        composer("conversation.transcribing", "Conversation transcribing", .transcribing),
        composer("conversation.coaching", "Conversation coaching", .coaching),
        composer("conversation.waiting", "Conversation waiting for Reply", .waitingForReply, messages: messages),
        composer("conversation.existing-history", "Existing conversation history", .waitingForReply, messages: longHistoryMessages),
        sentTurnAnchor,
        seniorSelfResponse,
        composer("conversation.permission-denied", "Conversation microphone denied", .failure(.unavailable)),
        composer("conversation.retry-transcription", "Conversation retry transcription", .failure(.retryable)),
        composer("conversation.retry-coaching", "Conversation retry coaching", .failure(.retryable)),
        correction,
        composer(
            "conversation.accessibility-xxxl", "Conversation Accessibility XXXL", .paused,
            accessibility: .init(contentSize: .accessibilityExtraExtraExtraLarge)
        ),
        composer("conversation.ipad", "Conversation iPad", .waitingForReply, family: .tablet, messages: messages),
    ]

    private static func composer(
        _ identifier: String,
        _ title: String,
        _ state: ComposerState,
        family: PreviewDeviceFamily = .adaptive,
        accessibility: PreviewAccessibilitySettings = .default,
        messages: [MessageRecord] = [],
        assistantResponses: [String: AssistantResponseRecord] = [:]
    ) -> PreviewScenario {
        PreviewScenario(
            identifier: identifier, title: title, deviceFamily: family,
            accessibility: accessibility, readiness: .ready
        ) {
            AnyView(ConversationView(model: .preview(
                composer: state, messages: messages, assistantResponses: assistantResponses
            )))
        }
    }

    private static var seniorSelfResponse: PreviewScenario {
        let responseMessageID = messages[1].id
        let metadata = AssistantResponseMetadataRecord(
            responseMessageID: responseMessageID,
            requestID: "50000000-0000-4000-8000-000000000001",
            idempotencyReceipt: "preview-senior-self-response",
            mode: .coach,
            relevance: "career-relevant",
            contextSufficiency: "sufficient",
            stance: "nudge",
            inference: "You have evidence of impact, but the review story needs one concrete next step.",
            confidence: "high",
            approach: "Connect the evidence to a practical action without overstating certainty.",
            createdAtMS: 2
        )
        let source = AssistantResponseSourceRecord(
            id: "60000000-0000-4000-8000-000000000001",
            responseMessageID: responseMessageID,
            ordinal: 0,
            sourceID: messages[0].id,
            sourceType: "message",
            excerpt: "Help me prepare for my review."
        )
        let proposal = AssistantProposalRecord(
            id: "70000000-0000-4000-8000-000000000001",
            responseMessageID: responseMessageID,
            kind: "action",
            canonicalPayload: Data(
                #"{"kind":"action","title":"Draft three evidence-backed review points","description":null,"priority":"medium","dueAt":null,"goalId":null}"#.utf8
            ),
            payloadDigest: "preview-action-digest",
            state: .pending,
            targetType: nil,
            targetID: nil,
            targetVersionID: nil,
            decisionReceipt: nil,
            createdAtMS: 2,
            resolvedAtMS: nil
        )
        return composer(
            "conversation.senior-self-response",
            "Senior Self response",
            .waitingForReply,
            messages: messages,
            assistantResponses: [responseMessageID: AssistantResponseRecord(
                metadata: metadata, sources: [source], proposal: proposal, feedback: nil
            )]
        )
    }

    private static var sentTurnAnchor: PreviewScenario {
        PreviewScenario(
            identifier: "conversation.sent-turn-anchor",
            title: "Sent turn anchor",
            deviceFamily: .adaptive,
            accessibility: .default,
            readiness: .ready
        ) {
            let store = ConversationScrollQAStore(messages: longHistoryMessages)
            let model = ConversationViewModel(
                conversationID: "20000000-0000-4000-8000-000000000010",
                title: "Scroll anchor",
                entryIntent: nil,
                composer: .typing("Anchor this message"),
                text: "Anchor this message",
                client: ConversationScreenClient(
                    loadMessages: { await store.loadMessages() },
                    beginVoice: {}, pauseVoice: {}, resumeVoice: {}, sendVoice: { _ in },
                    sendText: { text, messageAvailable in
                        await store.appendUserMessage(text)
                        await messageAvailable()
                        try? await Task.sleep(for: .seconds(5))
                    },
                    retry: {}, saveDraft: { _ in }, discardDraft: {}
                )
            )
            return AnyView(ConversationView(model: model))
        }
    }

    private static func list(
        _ identifier: String,
        _ title: String,
        state: ConversationsState
    ) -> PreviewScenario {
        PreviewScenario(
            identifier: identifier, title: title, deviceFamily: .adaptive,
            accessibility: .default, readiness: .ready
        ) {
            AnyView(
                NavigationStack {
                    ConversationsView(
                        model: ConversationsModel(
                            client: ConversationsClient(load: { .init(drafts: [], conversations: []) }),
                            initialState: state
                        ),
                        resume: { _ in }, open: { _ in }, openRecovery: {}
                    )
                }
            )
        }
    }

    private static var correction: PreviewScenario {
        PreviewScenario(
            identifier: "conversation.correction", title: "Conversation correction",
            deviceFamily: .adaptive, accessibility: .default, readiness: .ready
        ) {
            let model = ConversationViewModel.preview(composer: .waitingForReply, messages: messages)
            model.requestCorrection(messages[0])
            return AnyView(ConversationView(model: model))
        }
    }

    private static let messages: [MessageRecord] = [
        .init(id: "10000000-0000-4000-8000-000000000001", conversationID: "20000000-0000-4000-8000-000000000001", role: "user", body: "Help me prepare for my review.", createdAtMS: 1),
        .init(id: "10000000-0000-4000-8000-000000000002", conversationID: "20000000-0000-4000-8000-000000000001", role: "assistant", body: "Start with the impact you can support with evidence.", createdAtMS: 2),
    ]

    private static let longHistoryMessages: [MessageRecord] = (0..<14).map { index in
        MessageRecord(
            id: String(format: "90000000-0000-4000-8000-%012d", index),
            conversationID: "20000000-0000-4000-8000-000000000009",
            role: index.isMultiple(of: 2) ? "user" : "assistant",
            body: index == 13 ? "Latest rendered conversation message" : "Existing conversation message \(index + 1) with enough text to require scrolling.",
            createdAtMS: Int64(index + 1)
        )
    }

    private static let listSnapshot = ConversationIndexSnapshot(
        drafts: [draft("30000000-0000-4000-8000-000000000001", .saved, 4), draft("30000000-0000-4000-8000-000000000002", .saved, 3)],
        conversations: [conversation("40000000-0000-4000-8000-000000000001", "Review preparation", 2)]
    )
    private static let recoveredSnapshot = ConversationIndexSnapshot(
        drafts: [draft("30000000-0000-4000-8000-000000000003", .recovered, 4)], conversations: []
    )
    private static let historySnapshot = ConversationIndexSnapshot(
        drafts: [], conversations: [conversation("40000000-0000-4000-8000-000000000002", "Career direction", 4)]
    )

    private static func draft(_ id: String, _ recovery: DraftRecoveryKind, _ updated: Int64) -> ConversationDraftRecord {
        .init(
            id: id, conversationID: UUID().uuidString, inputMode: .text,
            text: "Prepare my review", voiceTurnID: nil, recoveryKind: recovery,
            createdAtMS: 1, updatedAtMS: updated
        )
    }

    private static func conversation(_ id: String, _ title: String, _ updated: Int64) -> ConversationRecord {
        .init(id: id, title: title, createdAtMS: 1, updatedAtMS: updated)
    }
}

private actor ConversationScrollQAStore {
    private var messages: [MessageRecord]

    init(messages: [MessageRecord]) {
        self.messages = messages
    }

    func loadMessages() -> [MessageRecord] {
        messages
    }

    func appendUserMessage(_ body: String) {
        messages.append(MessageRecord(
            id: "sent-turn-anchor",
            conversationID: "20000000-0000-4000-8000-000000000010",
            role: "user",
            body: body,
            createdAtMS: 100
        ))
    }
}
