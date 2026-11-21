import SwiftUI
import TaisaDesignSystem
import TaisaHome
import TaisaStorage

struct ThisWeekSection: View {
    let items: [WeeklyWorkItem]
    let send: (HomeIntent) -> Void

    var body: some View {
        Section {
            if items.isEmpty {
                ContentUnavailableView {
                    VStack {
                        CentralIcon(.completed).frame(width: 32, height: 32)
                        TaisaText(role: .heading, content: "Nothing needs focus right now")
                    }
                } description: {
                    TaisaText(role: .body, color: .mutedForeground, content: "Your chosen work for this week will appear here.")
                }
            } else {
                ForEach(items, id: \.action.id) { item in
                    weeklyRow(item)
                }
            }
        } header: {
            TaisaText(role: .label, content: "Current focus")
        }
        .accessibilityIdentifier("home.this-week")
    }

    private func weeklyRow(_ item: WeeklyWorkItem) -> some View {
        Button { send(.action(item.action.id)) } label: {
            TaisaRow(title: item.action.title, supporting: supportingText(for: item), icon: .action)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open this action")
    }

    private func supportingText(for item: WeeklyWorkItem) -> String? {
        let day = item.placement.plannedDayMS.map { Date(timeIntervalSince1970: Double($0) / 1_000).formatted(.dateTime.weekday(.wide)) }
        return [item.action.detail.isEmpty ? nil : item.action.detail, day].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }
}

enum ThisWeekSheet: Identifiable {
    case priorWeekReview(unresolvedCount: Int)

    var id: String {
        switch self {
        case .priorWeekReview: "prior-week-review"
        }
    }
}

struct HomeActionsPreviewSection: View {
    let prompts: [HomeActionPrompt]
    let send: (HomeIntent) -> Void

    var body: some View {
        Section("Actions") {
            if prompts.isEmpty {
                TaisaRow(title: "No actions need attention", supporting: "Open Actions when you want to add or review work.", icon: .action)
            } else {
                ForEach(Array(prompts.enumerated()), id: \.element.action.id) { _, prompt in
                    Button { send(.action(prompt.action.id)) } label: {
                        TaisaRow(title: prompt.action.title, supporting: label(prompt.reason), icon: icon(prompt.reason), emphasis: prompt.reason == .overdue || prompt.reason == .blocked ? .attention : .standard)
                    }
                }
            }
            Button { send(.actions) } label: { TaisaNavigationRow(label: "View all actions", icon: .action) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.actions.view-all")
        }
        .accessibilityIdentifier("home.actions.preview")
    }

    private func label(_ reason: HomeActionPromptReason) -> String {
        switch reason {
        case .overdue: "Overdue"
        case .dueSoon: "Due soon"
        case .blocked: "Blocked"
        case .recentlyReopened: "Recently reopened"
        case .thisWeek: "This week"
        }
    }

    private func icon(_ reason: HomeActionPromptReason) -> CentralIconName {
        switch reason {
        case .overdue, .blocked: .warning
        case .recentlyReopened: .undo
        case .dueSoon, .thisWeek: .action
        }
    }
}

struct HomeGoalsSummarySection: View {
    let goals: [GoalRecord]
    let send: (HomeIntent) -> Void

    var body: some View {
        Section("Goals") {
            if goals.isEmpty {
                TaisaRow(title: "No active goals", supporting: "Create a goal when an outcome needs more than one action.", icon: .goal)
            } else {
                ForEach(goals.prefix(3), id: \.id) { GoalRow(goal: $0, send: send) }
            }
            Button { send(.goals) } label: { TaisaNavigationRow(label: "View all goals", icon: .goal) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.goals.view-all")
        }
        .accessibilityIdentifier("home.goals.summary")
    }
}

struct HomeReviewSection: View {
    let unresolvedCount: Int
    let open: (Int) -> Void

    var body: some View {
        Section("Review") {
            Button { open(unresolvedCount) } label: {
                TaisaRow(title: "Review \(unresolvedCount) unfinished \(unresolvedCount == 1 ? "item" : "items")", icon: .history, emphasis: .attention)
            }
            .accessibilityIdentifier("home.prior-week.review")
        }
    }
}

struct PriorWeekReviewSheet: View {
    let unresolvedCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                VStack {
                    CentralIcon(.history).frame(width: 32, height: 32)
                    TaisaText(role: .heading, content: "Unfinished work")
                }
            } description: {
                TaisaText(role: .body, color: .mutedForeground, content: "You have \(unresolvedCount) unfinished \(unresolvedCount == 1 ? "item" : "items") from an earlier week. Decide what still belongs before planning more work.")
            }
            .navigationTitle("Review prior week")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    TaisaToolbarAction(label: "Done", icon: .completed) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

extension WeeklyWorkItem: @retroactive Identifiable {
    public var id: String { action.id }
}
