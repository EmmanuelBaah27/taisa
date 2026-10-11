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
        messages: [MessageRecord] = []
    ) -> PreviewScenario {
        PreviewScenario(
            identifier: identifier, title: title, deviceFamily: family,
            accessibility: accessibility, readiness: .ready
        ) {
            AnyView(ConversationView(model: .preview(composer: state, messages: messages)))
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
