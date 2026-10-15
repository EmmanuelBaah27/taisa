import SwiftUI
import TaisaConversations
import TaisaDesignSystem
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
    @State private var showsDraftsOnly = false
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
        VStack(spacing: 0) {
            header
            content
        }
        .background(TaisaColor.background.color)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
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

    private var header: some View {
        HStack(spacing: TaisaSpacing.standard.rawValue) {
            Text("Chats")
                .font(.system(.title, weight: .semibold))
                .foregroundStyle(TaisaColor.foreground.color)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 24, height: 24)
                    .padding(12)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search chats")
            .accessibilityHint("Search is not available yet")
            .accessibilityIdentifier("chats.search")

            Button { showsDraftsOnly.toggle() } label: {
                HStack(spacing: 6) {
                    Text("Drafts").font(.system(size: 16, weight: .medium))
                    Circle()
                        .fill(TaisaColor.destructive.color)
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 20)
                .frame(height: 48)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsDraftsOnly ? "Showing drafts" : "Showing all chats")
            .accessibilityIdentifier("chats.drafts-filter")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading chats…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView(
                "No chats yet",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Completed chats and saved drafts will appear here.")
            )
            .accessibilityIdentifier("conversations.empty")
        case let .content(snapshot, isRefreshing, issue):
            List {
                if let issue { issueRow(issue) }
                if !snapshot.drafts.isEmpty {
                    Section("Drafts") {
                        ForEach(snapshot.drafts) { draft in
                            Button { resume(draft) } label: { DraftRow(draft: draft) }
                                .buttonStyle(.plain)
                                .listRowSeparatorTint(TaisaColor.background.color)
                                .swipeActions {
                                    Button("Discard", role: .destructive) { confirmation = .discard(draft) }
                                }
                        }
                    }
                    .accessibilityIdentifier("conversations.drafts")
                }
                if !showsDraftsOnly {
                    ForEach(groupedConversations(snapshot.conversations), id: \.month) { group in
                        Section {
                            ForEach(group.conversations, id: \.id) { conversation in
                            Button { open(conversation) } label: {
                                ConversationHistoryRow(
                                    conversation: conversation,
                                    preview: snapshot.lastMessagePreview(for: conversation.id)
                                )
                            }
                                .buttonStyle(.plain)
                                .listRowBackground(TaisaColor.selectedSurface.color)
                                .listRowSeparatorTint(TaisaColor.background.color)
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
                        } header: {
                            monthHeader(group.month)
                        }
                    }
                    .accessibilityIdentifier("conversations.history")
                }
                if isRefreshing { ProgressView().frame(maxWidth: .infinity) }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .clipShape(RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue))
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

    private func monthHeader(_ month: String) -> some View {
        Text(month)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(TaisaColor.mutedForeground.color)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct MonthGroup {
        let month: String
        let conversations: [ConversationRecord]
    }

    private func groupedConversations(_ conversations: [ConversationRecord]) -> [MonthGroup] {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        let grouped = Dictionary(grouping: conversations) { conversation in
            let date = Date(timeIntervalSince1970: Double(conversation.updatedAtMS) / 1_000)
            return formatter.string(from: date)
        }
        return grouped.map { MonthGroup(month: $0.key, conversations: $0.value) }
            .sorted { lhs, rhs in
                let left = lhs.conversations.map(\.updatedAtMS).max() ?? 0
                let right = rhs.conversations.map(\.updatedAtMS).max() ?? 0
                return left > right
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
