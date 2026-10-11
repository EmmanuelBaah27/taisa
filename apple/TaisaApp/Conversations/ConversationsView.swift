import SwiftUI
import TaisaConversations
import TaisaStorage

struct ConversationsView: View {
    private enum Confirmation: Identifiable {
        case discard(ConversationDraftRecord)
        case delete(ConversationRecord)
        var id: String {
            switch self { case .discard(let draft): "discard-\(draft.id)"; case .delete(let conversation): "delete-\(conversation.id)" }
        }
    }

    @State private var model: ConversationsModel
    @State private var confirmation: Confirmation?
    @State private var renameTarget: ConversationRecord?
    @State private var renameText = ""
    let resume: (ConversationDraftRecord) -> Void
    let open: (ConversationRecord) -> Void
    let openRecovery: () -> Void

    init(
        model: ConversationsModel,
        resume: @escaping (ConversationDraftRecord) -> Void,
        open: @escaping (ConversationRecord) -> Void,
        openRecovery: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.resume = resume
        self.open = open
        self.openRecovery = openRecovery
    }

    var body: some View {
        content
            .navigationTitle("Conversations")
            .accessibilityIdentifier("conversations.root")
            .task { if model.state == .idle { await model.load() } }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(
                    get: { confirmation != nil },
                    set: { if !$0 { confirmation = nil } }
                )
            ) {
                if let confirmation {
                    switch confirmation {
                case .discard(let draft):
                    Button("Discard draft", role: .destructive) { Task { await model.discardDraft(id: draft.id) } }
                case .delete(let conversation):
                    Button("Delete conversation", role: .destructive) { Task { await model.deleteConversation(id: conversation.id) } }
                        .accessibilityIdentifier("conversation.delete-confirmation")
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename conversation", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Title", text: $renameText)
                Button("Rename") {
                    guard let target = renameTarget else { return }
                    Task { await model.renameConversation(id: target.id, title: renameText) }
                    renameTarget = nil
                }
                .accessibilityIdentifier("conversation.rename")
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading conversations…")
        case .empty:
            ContentUnavailableView(
                "No conversations yet",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Completed conversations and saved drafts will appear here.")
            )
            .accessibilityIdentifier("conversations.empty")
        case let .content(snapshot, isRefreshing, issue):
            List {
                if let issue { issueRow(issue) }
                if !snapshot.drafts.isEmpty {
                    Section("Drafts") {
                        ForEach(snapshot.drafts) { draft in
                            Button { resume(draft) } label: { DraftRow(draft: draft) }
                                .swipeActions {
                                    Button("Discard", role: .destructive) { confirmation = .discard(draft) }
                                }
                        }
                    }
                    .accessibilityIdentifier("conversations.drafts")
                }
                if !snapshot.conversations.isEmpty {
                    Section("History") {
                        ForEach(snapshot.conversations, id: \.id) { conversation in
                            Button { open(conversation) } label: { ConversationHistoryRow(conversation: conversation) }
                                .swipeActions {
                                    Button("Delete", role: .destructive) { confirmation = .delete(conversation) }
                                    Button("Rename") { beginRename(conversation) }.tint(.accentColor)
                                }
                                .contextMenu {
                                    Menu("Actions") {
                                        Button("Rename") { beginRename(conversation) }
                                        Button("Delete", role: .destructive) { confirmation = .delete(conversation) }
                                    }
                                }
                        }
                    }
                    .accessibilityIdentifier("conversations.history")
                }
                if isRefreshing { ProgressView().frame(maxWidth: .infinity) }
            }
            .refreshable { await model.load() }
        case let .failure(issue):
            ContentUnavailableView {
                Label(issue == .recoveryRequired ? "Recovery required" : "Conversations unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(issue == .recoveryRequired ? "Restore secure access to read your conversations." : "Taisa couldn’t read your conversations securely.")
            } actions: {
                if issue == .recoveryRequired {
                    Button("Open recovery", action: openRecovery).accessibilityIdentifier("conversations.recovery")
                } else {
                    Button("Try again") { Task { await model.load() } }.accessibilityIdentifier("conversations.retry")
                }
            }
        }
    }

    private func issueRow(_ issue: ConversationsIssue) -> some View {
        Button {
            if issue == .recoveryRequired { openRecovery() } else { Task { await model.load() } }
        } label: {
            Label(issue == .recoveryRequired ? "Open recovery" : "Try refresh again", systemImage: "exclamationmark.triangle")
        }
        .accessibilityIdentifier(issue == .recoveryRequired ? "conversations.recovery" : "conversations.retry")
    }

    private func beginRename(_ conversation: ConversationRecord) {
        renameText = conversation.title
        renameTarget = conversation
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .discard: "Discard this draft?"
        case .delete: "Delete this conversation?"
        case nil: "Confirm action"
        }
    }
}
