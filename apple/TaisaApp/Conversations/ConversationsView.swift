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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmation: Confirmation?
    @State private var renameTarget: ConversationRecord?
    @State private var renameText = ""
    @State private var showsDrafts = false
    let resetID: Int
    let resume: (ConversationDraftRecord) -> Void
    let open: (ConversationRecord) -> Void
    let openRecovery: () -> Void

    init(
        model: ConversationsModel,
        resetID: Int = 0,
        resume: @escaping (ConversationDraftRecord) -> Void,
        open: @escaping (ConversationRecord) -> Void,
        openRecovery: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.resetID = resetID
        self.resume = resume
        self.open = open
        self.openRecovery = openRecovery
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    header
                }
            if let notice = model.notices.first {
                toast(notice)
                    .id(notice.id)
                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                    .padding(.top, TaisaControlMetric.appBarHeight - TaisaSpacing.control.rawValue)
                    .transition(toastTransition)
                    .zIndex(2)
            }
        }
        .animation(toastAnimation, value: model.notices.first?.id)
        .background(TaisaColor.background.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversations.root")
        .task { if model.state == .idle { await model.load() } }
        .navigationDestination(isPresented: $showsDrafts) {
            DraftsView(
                drafts: model.snapshot.drafts,
                resume: resume,
                discard: { confirmation = .discard($0) }
            )
        }
        .modifier(TaisaNativeConfirmationDialog(
            title: confirmationTitle,
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            actions: {
                if let confirmation {
                    switch confirmation {
                case .discard(let draft):
                    TaisaSystemButton("Discard draft", role: .destructive) { Task { await model.discardDraft(id: draft.id) } }
                case .delete(let conversation):
                    TaisaSystemButton("Delete conversation", role: .destructive) { Task { await model.deleteConversation(id: conversation.id) } }
                        .accessibilityIdentifier("conversation.delete-confirmation")
                    }
                }
                TaisaSystemButton("Cancel", role: .cancel) {}
            },
            message: { EmptyView() }
        ))
        .modifier(TaisaTextEntryAlert(
            title: "Rename conversation",
            prompt: "Title",
            text: $renameText,
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            ),
            actions: {
                TaisaSystemButton("Rename") {
                    guard let target = renameTarget else { return }
                    Task { await model.renameConversation(id: target.id, title: renameText) }
                    renameTarget = nil
                }
                .accessibilityIdentifier("conversation.rename")
                TaisaSystemButton("Cancel", role: .cancel) { renameTarget = nil }
            },
            message: { EmptyView() }
        ))
    }

    private var header: some View {
        TaisaPageHeader("Chats") {
            if hasDrafts {
                draftsButton
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView { TaisaText(role: .body, content: "Loading chats…") }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView {
                VStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                    TaisaText(role: .heading, content: "No chats yet")
                }
            } description: {
                TaisaText(role: .supporting, color: .mutedForeground, content: "Completed chats and saved drafts will appear here.")
            }
            .accessibilityIdentifier("conversations.empty")
        case let .content(snapshot, isRefreshing, _):
            List {
                ForEach(groupedConversations(snapshot.conversations), id: \.month) { group in
                        Section {
                            monthHeader(group.month)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            ForEach(Array(group.conversations.enumerated()), id: \.element.id) { index, conversation in
                            TaisaButtonControl(style: TaisaButtonStyle(presentation: .content), action: { open(conversation) }) {
                                ConversationHistoryRow(
                                    conversation: conversation,
                                    preview: snapshot.lastMessagePreview(for: conversation.id)
                                )
                            }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(historyRowBackground(index: index, count: group.conversations.count))
                                .listRowSeparatorTint(TaisaColor.background.color)
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    TaisaSystemButton("Rename") { beginRename(conversation) }
                                    TaisaSystemButton("Delete", role: .destructive) { confirmation = .delete(conversation) }
                                }
                            }
                        }
                        .listSectionMargins(.horizontal, 0)
                }
                if isRefreshing { ProgressView().frame(maxWidth: .infinity) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .contentMargins(
                .bottom,
                TaisaControlMetric.primaryNavigationReservedHeight,
                for: .scrollContent
            )
            .listSectionSpacing(TaisaSpacing.section.rawValue)
            .environment(\.defaultMinListRowHeight, 0)
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
            .refreshable { await model.load() }
            .id(resetID)
        case let .failure(issue):
            ContentUnavailableView {
                VStack { Image(systemName: "exclamationmark.triangle"); TaisaText(role: .heading, content: issueTitle(issue, retainedContent: false)) }
            } description: {
                TaisaText(role: .supporting, color: .mutedForeground, content: issueMessage(issue, retainedContent: false))
            } actions: {
                if case .recoveryRequired = issue {
                    TaisaButtonControl("Open recovery", action: { openRecovery() }).accessibilityIdentifier("conversations.recovery")
                } else {
                    TaisaButtonControl("Try again") { Task { await model.load() } }.accessibilityIdentifier("conversations.retry")
                }
            }
        }
    }

    private var draftsButton: some View {
        TaisaSecondaryCapsuleButton(size: .standard, action: { showsDrafts = true }) {
            HStack(spacing: 6) {
                TaisaText(role: .navigationLabel, content: "Drafts")
                Circle()
                    .fill(TaisaColor.destructive.color)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityIdentifier("chats.drafts")
    }

    private func monthHeader(_ month: String) -> some View {
        TaisaText(role: .label, color: .mutedForeground, content: month)
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

    private var toastTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .top).combined(with: .opacity)
    }

    private var toastAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: TaisaMotion.fast)
    }

    private func toast(_ notice: ConversationsNotice) -> some View {
        TaisaToast(
            message: issueTitle(notice.issue, retainedContent: true),
            actionLabel: issueActionLabel(notice.issue),
            action: {
                model.dismissNotice(id: notice.id)
                retry(notice.issue)
            },
            dismiss: { model.dismissNotice(id: notice.id) }
        )
        .accessibilityIdentifier("conversations.toast")
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
        case .storageUnavailable: retainedContent ? "Couldn’t refresh chats" : "Couldn’t load chats"
        case .recoveryRequired: "Unlock your chats to continue"
        case .renameFailed: "Couldn’t rename conversation"
        case .deleteFailed: "Couldn’t delete conversation"
        case .discardFailed: "Couldn’t discard draft"
        }
    }

    private func issueMessage(_ issue: ConversationsIssue, retainedContent: Bool) -> String {
        switch issue {
        case .storageUnavailable:
            retainedContent ? "You’re seeing the last saved version." : "Check your connection and try again."
        case .recoveryRequired: "Open Recovery to restore secure access."
        case .renameFailed: "Your original title is unchanged."
        case .deleteFailed: "It’s still in your chat history."
        case .discardFailed: "Your draft is still saved."
        }
    }

    private func issueActionLabel(_ issue: ConversationsIssue) -> String {
        switch issue {
        case .storageUnavailable: "Refresh"
        case .renameFailed, .deleteFailed, .discardFailed: "Try again"
        case .recoveryRequired: "Open Recovery"
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

private struct DraftsView: View {
    @Environment(\.dismiss) private var dismiss
    let drafts: [ConversationDraftRecord]
    let resume: (ConversationDraftRecord) -> Void
    let discard: (ConversationDraftRecord) -> Void

    var body: some View {
        List(drafts) { draft in
            TaisaButtonControl(style: TaisaButtonStyle(presentation: .content), action: { resume(draft) }) { DraftRow(draft: draft) }
                .contextMenu {
                    TaisaSystemButton("Discard", role: .destructive) { discard(draft) }
                }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .safeAreaInset(edge: .top, spacing: 0) {
            TaisaChildPageHeader("Drafts") {
                dismiss()
            }
        }
        .background(TaisaColor.background.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("conversations.drafts")
    }
}
