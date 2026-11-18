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
        TaisaPressable(action: { send(.action(item.action.id)) }) {
            TaisaRow(title: item.action.title, supporting: supportingText(for: item), icon: .action)
        }
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
    let actions: [ActionRecord]
    let totalCount: Int
    let send: (HomeIntent) -> Void
    let add: () -> Void

    var body: some View {
        VStack(spacing: TaisaSpacing.tight.rawValue) {
            HStack(spacing: TaisaSpacing.compact.rawValue) {
                TaisaText(role: .taskSupporting, color: .mutedForeground, content: "Tasks this week")
                Spacer()
                TaisaSecondaryIconButton(icon: .add, accessibilityLabel: "Add task", size: TaisaControlMetric.taskControl, action: add)
            }
            VStack(spacing: TaisaSpacing.tight.rawValue) {
            if actions.isEmpty {
                TaisaTaskRow(title: "No tasks this week")
            } else {
                ForEach(actions.prefix(3), id: \.id) { action in
                    TaisaPressable(action: { send(.action(action.id)) }) {
                        TaisaTaskRow(title: action.title, dueLabel: dueLabel(for: action))
                    }
                }
            }
            }
            .clipShape(RoundedRectangle(cornerRadius: TaisaRadius.taskGroup))
            TaisaPressable(action: { send(.actions) }) { TaisaTaskSummaryRow(count: totalCount) }
                .accessibilityIdentifier("home.actions.view-all")
        }
        .accessibilityIdentifier("home.actions.preview")
    }

    private func dueLabel(for action: ActionRecord) -> String? {
        guard let raw = action.dueDay?.rawValue else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: raw) else { return nil }
        return date.formatted(.dateTime.weekday(.abbreviated))
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
            TaisaPressable(action: { send(.goals) }) { TaisaNavigationRow(label: "View all goals", icon: .goal) }
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
            TaisaPressable(action: { open(unresolvedCount) }) {
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
