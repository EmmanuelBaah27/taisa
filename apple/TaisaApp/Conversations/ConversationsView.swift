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
        ZStack(alignment: .top) {
            content
            header
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
        TaisaPageHeader("Chats") {
            searchButton
            if hasDrafts {
                draftsButton
            }
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
            .contentMargins(
                .top,
                TaisaControlMetric.appBarHeight + TaisaSpacing.standard.rawValue,
                for: .scrollContent
            )
            .contentMargins(
                .bottom,
                TaisaControlMetric.primaryNavigationReservedHeight,
                for: .scrollContent
            )
            .listSectionSpacing(TaisaSpacing.section.rawValue)
            .environment(\.defaultMinListRowHeight, 0)
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
            .refreshable { await model.load() }
        case let .failure(issue):
            ContentUnavailableView {
                Label(issueTitle(issue, retainedContent: false), systemImage: "exclamationmark.triangle")
            } description: {
                Text(issueMessage(issue, retainedContent: false))
            } actions: {
                if case .recoveryRequired = issue {
                    Button("Open recovery", action: openRecovery).accessibilityIdentifier("conversations.recovery")
                } else {
                    Button("Try again") { Task { await model.load() } }.accessibilityIdentifier("conversations.retry")
                }
            }
        }
    }

    private var searchButton: some View {
        TaisaSecondaryIconButton(
            icon: .magnifyingGlass,
            accessibilityLabel: "Search chats",
            accessibilityHint: "Search is not available yet",
            action: {}
        )
        .disabled(true)
        .accessibilityIdentifier("chats.search")
    }

    private var draftsButton: some View {
        TaisaSecondaryCapsuleButton(action: { showsDraftsOnly.toggle() }) {
            HStack(spacing: 6) {
                Text("Drafts").font(.system(size: 16, weight: .medium))
                Circle()
                    .fill(TaisaColor.destructive.color)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, TaisaSpacing.content.rawValue)
        }
        .accessibilityValue(showsDraftsOnly ? "Showing drafts" : "Showing all chats")
        .accessibilityIdentifier("chats.drafts-filter")
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
        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
            Label(issueTitle(issue, retainedContent: true), systemImage: "exclamationmark.triangle")
                .font(TaisaTypography.navigationLabel.font)
            Text(issueMessage(issue, retainedContent: true))
                .font(TaisaTypography.metadata.font)
                .foregroundStyle(TaisaColor.mutedForeground.color)
            Button(issueActionLabel(issue)) { retry(issue) }
                .font(TaisaTypography.metadata.font.weight(.medium))
        }
        .accessibilityIdentifier(issue == .recoveryRequired ? "conversations.recovery" : "conversations.retry")
    }

    private func retry(_ issue: ConversationsIssue) {
        switch issue {
        case .storageUnavailable:
            Task { await model.load() }
        case .recoveryRequired:
            openRecovery()
        case let .renameFailed(id, title):
            Task { await model.renameConversation(id: id, title: title) }
        case let .deleteFailed(id):
            Task { await model.deleteConversation(id: id) }
        case let .discardFailed(id):
            Task { await model.discardDraft(id: id) }
        }
    }

    private func issueTitle(_ issue: ConversationsIssue, retainedContent: Bool) -> String {
        switch issue {
        case .storageUnavailable: retainedContent ? "Chats may be out of date" : "Chats couldn’t load"
        case .recoveryRequired: "Secure access needs to be restored"
        case .renameFailed: "Title wasn’t changed"
        case .deleteFailed: "Conversation wasn’t deleted"
        case .discardFailed: "Draft wasn’t discarded"
        }
    }

    private func issueMessage(_ issue: ConversationsIssue, retainedContent: Bool) -> String {
        switch issue {
        case .storageUnavailable:
            retainedContent ? "Your existing chats are still shown." : "Taisa couldn’t read your chats."
        case .recoveryRequired: "Restore secure access to read your chats."
        case .renameFailed: "The previous title is still in place."
        case .deleteFailed: "Nothing was removed."
        case .discardFailed: "Your draft is still available."
        }
    }

    private func issueActionLabel(_ issue: ConversationsIssue) -> String {
        switch issue {
        case .storageUnavailable: "Refresh"
        case .recoveryRequired: "Open recovery"
        case .renameFailed, .deleteFailed, .discardFailed: "Try again"
        }
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
