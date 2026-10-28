import SwiftUI
import TaisaDesignSystem
import TaisaHome
import TaisaStorage

struct ThisWeekSection: View {
    let items: [WeeklyWorkItem]
    let unresolvedPriorWeekCount: Int
    let model: HomeModel
    let openPlanning: (WeeklyWorkItem) -> Void
    let openCompletion: (WeeklyWorkItem) -> Void
    let openPriorWeekReview: (Int) -> Void

    var body: some View {
        Section {
            if unresolvedPriorWeekCount > 0 {
                Button {
                    openPriorWeekReview(unresolvedPriorWeekCount)
                } label: {
                    TaisaRow(title: "Review \(unresolvedPriorWeekCount) unfinished \(unresolvedPriorWeekCount == 1 ? "item" : "items")", icon: .history, emphasis: .attention)
                }
                .accessibilityIdentifier("home.prior-week.review")
            }

            if items.isEmpty {
                ContentUnavailableView {
                    VStack { CentralIcon(.completed).frame(width: 32, height: 32); Text("A clear week") }
                } description: { Text("Add work when you decide what matters next.") }
            } else {
                ForEach(items, id: \.action.id) { item in
                    weeklyRow(item)
                }
            }

            if model.canUndoCompletion {
                TaisaButton(role: .secondary, label: "Correct mistaken completion", icon: .undo) {
                    Task { await model.undoCompletion() }
                }
                .accessibilityIdentifier("home.this-week.undo")
            }
        } header: {
            Text("This Week")
        }
        .accessibilityIdentifier("home.this-week")
    }

    private func weeklyRow(_ item: WeeklyWorkItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button { openCompletion(item) } label: { CentralIcon(.completeAction).frame(width: 24, height: 24) }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.action.title)")
            .accessibilityIdentifier("home.this-week.complete")

            Button {
                openPlanning(item)
            } label: {
                TaisaRow(title: item.action.title, supporting: supportingText(for: item), icon: .action)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change when this is planned")
        }
    }

    private func supportingText(for item: WeeklyWorkItem) -> String? {
        let day = item.placement.plannedDayMS.map { Date(timeIntervalSince1970: Double($0) / 1_000).formatted(.dateTime.weekday(.wide)) }
        return [item.action.detail.isEmpty ? nil : item.action.detail, day].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }
}

enum ThisWeekSheet: Identifiable {
    case planning(WeeklyWorkItem)
    case completion(WeeklyWorkItem)
    case priorWeekReview(unresolvedCount: Int)

    var id: String {
        switch self {
        case let .planning(item): "planning-\(item.id)"
        case let .completion(item): "completion-\(item.id)"
        case .priorWeekReview: "prior-week-review"
        }
    }
}

struct HomeActionAttentionSection: View {
    let overdue: [ActionRecord]
    let reopened: [ActionRecord]
    let reviewFacts: HomeActionReviewFacts
    let send: (HomeIntent) -> Void

    var body: some View {
        if !overdue.isEmpty || !reopened.isEmpty {
            Section("Needs attention") {
                ForEach(overdue, id: \.id) { action in
                    Button { send(.action(action.id)) } label: { TaisaRow(title: action.title, supporting: "Overdue", icon: .warning, emphasis: .attention) }
                }
                .accessibilityIdentifier("home.actions.overdue")
                ForEach(reopened, id: \.id) { action in
                    Button { send(.action(action.id)) } label: { TaisaRow(title: action.title, supporting: "Reopened this week", icon: .undo, emphasis: .attention) }
                }
                .accessibilityIdentifier("home.actions.reopened")
            }
            .accessibilityIdentifier("home.action-attention")
            .accessibilityHint("\(reviewFacts.active) active, \(reviewFacts.completed) completed, \(reviewFacts.dropped) dropped, \(reviewFacts.reopened) reopened")
        }
    }
}

struct WeeklyPlanningSheet: View {
    let item: WeeklyWorkItem
    let model: HomeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Plan for today") { move(to: Date()) }
                    Button("Keep flexible") { move(to: nil) }
                } footer: {
                    Text("Choose deliberately. You can change this again at any time.")
                }
            }
            .navigationTitle(item.action.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func move(to day: Date?) {
        Task {
            await model.move(actionID: item.action.id, weekContaining: Date(), plannedDay: day)
            dismiss()
        }
    }
}

struct PriorWeekReviewSheet: View {
    let unresolvedCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                VStack { CentralIcon(.history).frame(width: 32, height: 32); Text("Unfinished work") }
            } description: {
                Text("You have \(unresolvedCount) unfinished \(unresolvedCount == 1 ? "item" : "items") from an earlier week. Decide what still belongs before planning more work.")
            }
            .navigationTitle("Review prior week")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

extension WeeklyWorkItem: @retroactive Identifiable {
    public var id: String { action.id }
}
