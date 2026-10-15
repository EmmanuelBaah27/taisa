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

            searchButton
            if hasDrafts {
                draftsButton
            }
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: 64)
        .background {
            PageEdgeFade(.header)
        }
        .overlay(alignment: .bottom) {
            PageEdgeFade(.header)
                .frame(height: TaisaSpacing.section.rawValue)
                .offset(y: TaisaSpacing.section.rawValue)
        }
        .zIndex(1)
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
                                .contextMenu {
                                    Button("Discard", role: .destructive) { confirmation = .discard(draft) }
                                }
                        }
                    }
                    .accessibilityIdentifier("conversations.drafts")
                }
                if !showsDraftsOnly || snapshot.drafts.isEmpty {
                    ForEach(groupedConversations(snapshot.conversations), id: \.month) { group in
                        Section {
                            monthHeader(group.month)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            ForEach(Array(group.conversations.enumerated()), id: \.element.id) { index, conversation in
                            Button { open(conversation) } label: {
                                ConversationHistoryRow(
                                    conversation: conversation,
                                    preview: snapshot.lastMessagePreview(for: conversation.id)
                                )
                            }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(historyRowBackground(index: index, count: group.conversations.count))
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    Button("Rename") { beginRename(conversation) }
                                    Button("Delete", role: .destructive) { confirmation = .delete(conversation) }
                                }
                            }
                        }
                        .listSectionMargins(.horizontal, 0)
                    }
                }
                if isRefreshing { ProgressView().frame(maxWidth: .infinity) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .contentMargins(.top, TaisaSpacing.section.rawValue, for: .scrollContent)
            .contentMargins(.bottom, 152, for: .scrollContent)
            .listSectionSpacing(TaisaSpacing.standard.rawValue)
            .environment(\.defaultMinListRowHeight, 0)
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
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

    @ViewBuilder private var searchButton: some View {
        let button = Button(action: {}) {
            CentralIcon(.magnifyingGlass)
                .frame(width: 24, height: 24)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Search chats")
        .accessibilityHint("Search is not available yet")
        .accessibilityIdentifier("chats.search")

        if #available(iOS 26.0, macOS 26.0, *) {
            button.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            button.buttonStyle(.plain).background(.regularMaterial, in: Circle())
        }
    }

    @ViewBuilder private var draftsButton: some View {
        let button = Button { showsDraftsOnly.toggle() } label: {
            HStack(spacing: 6) {
                Text("Drafts").font(.system(size: 16, weight: .medium))
                Circle()
                    .fill(TaisaColor.destructive.color)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, TaisaSpacing.content.rawValue)
            .frame(height: 48)
        }
        .accessibilityValue(showsDraftsOnly ? "Showing drafts" : "Showing all chats")
        .accessibilityIdentifier("chats.drafts-filter")

        if #available(iOS 26.0, macOS 26.0, *) {
            button.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            button.buttonStyle(.plain).background(.regularMaterial, in: Capsule())
        }
    }

    private func monthHeader(_ month: String) -> some View {
        Text(month)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(TaisaColor.mutedForeground.color)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, TaisaSpacing.compact.rawValue)
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("conversations.history")
    }

    private func historyRowBackground(index: Int, count: Int) -> some View {
        let radius = TaisaRadius.historyGroup.rawValue
        return TaisaColor.subtleSurface.color
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: index == 0 ? radius : 0,
                    bottomLeadingRadius: index == count - 1 ? radius : 0,
                    bottomTrailingRadius: index == count - 1 ? radius : 0,
                    topTrailingRadius: index == 0 ? radius : 0
                )
            )
    }

    private var hasDrafts: Bool {
        guard case let .content(snapshot, _, _) = model.state else { return false }
        return !snapshot.drafts.isEmpty
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
