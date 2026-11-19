import SwiftUI
import TaisaDesignSystem
import TaisaHome
import TaisaStorage

struct ThisWeekSection: View {
    let items: [WeeklyWorkItem]
    let unresolvedPriorWeekCount: Int
    let model: HomeModel
    let openPlanning: (WeeklyWorkItem) -> Void
    let openPriorWeekReview: (Int) -> Void

    var body: some View {
        Section {
            if unresolvedPriorWeekCount > 0 {
                TaisaButtonControl(action: { openPriorWeekReview(unresolvedPriorWeekCount) }) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        TaisaText(role: .label, content: "Review \(unresolvedPriorWeekCount) unfinished \(unresolvedPriorWeekCount == 1 ? "item" : "items")")
                    }
                }
                .accessibilityIdentifier("home.prior-week.review")
            }

            if items.isEmpty {
                ContentUnavailableView {
                    VStack { Image(systemName: "checkmark.circle"); TaisaText(role: .heading, content: "A clear week") }
                } description: {
                    TaisaText(role: .supporting, color: .mutedForeground, content: "Add work when you decide what matters next.")
                }
            } else {
                ForEach(items, id: \.action.id) { item in
                    weeklyRow(item)
                }
            }

            if model.canUndoCompletion {
                TaisaButtonControl(action: { Task { await model.undoCompletion() } }) {
                    HStack { Image(systemName: "arrow.uturn.backward"); TaisaText(role: .label, content: "Undo completion") }
                }
                .accessibilityIdentifier("home.this-week.undo")
            }
        } header: {
            TaisaText(role: .heading, content: "This Week")
        }
        .accessibilityIdentifier("home.this-week")
    }

    private func weeklyRow(_ item: WeeklyWorkItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TaisaButtonControl(style: TaisaButtonStyle(shape: .circle), action: {
                Task { await model.complete(actionID: item.action.id) }
            }) {
                Image(systemName: "circle")
                    .font(TaisaTypography.heading.font)
                    .frame(minWidth: TaisaControlMetric.headerActionHeight, minHeight: TaisaControlMetric.headerActionHeight)
            }
            .accessibilityLabel("Complete \(item.action.title)")
            .accessibilityIdentifier("home.this-week.complete")

            TaisaButtonControl(style: TaisaButtonStyle(presentation: .content), action: { openPlanning(item) }) {
                VStack(alignment: .leading, spacing: 3) {
                    TaisaText(role: .body, content: item.action.title)
                        .foregroundStyle(.primary)
                    if !item.action.detail.isEmpty {
                        TaisaText(role: .supporting, color: .mutedForeground, content: item.action.detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let plannedDayMS = item.placement.plannedDayMS {
                        TaisaText(role: .metadata, color: .mutedForeground, content: Date(timeIntervalSince1970: Double(plannedDayMS) / 1_000).formatted(.dateTime.weekday(.wide)))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHint("Change when this is planned")
        }
    }
}

enum ThisWeekSheet: Identifiable {
    case planning(WeeklyWorkItem)
    case priorWeekReview(unresolvedCount: Int)

    var id: String {
        switch self {
        case let .planning(item): "planning-\(item.id)"
        case .priorWeekReview: "prior-week-review"
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
                    TaisaButtonControl("Plan for today") { move(to: Date()) }
                    TaisaButtonControl("Keep flexible") { move(to: nil) }
                } footer: {
                    TaisaText(role: .supporting, color: .mutedForeground, content: "Choose deliberately. You can change this again at any time.")
                }
            }
            .navigationTitle(item.action.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { TaisaButtonControl("Cancel") { dismiss() } }
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
                VStack { Image(systemName: "clock.arrow.circlepath"); TaisaText(role: .heading, content: "Unfinished work") }
            } description: {
                TaisaText(role: .supporting, color: .mutedForeground, content: "You have \(unresolvedCount) unfinished \(unresolvedCount == 1 ? "item" : "items") from an earlier week. Decide what still belongs before planning more work.")
            }
            .navigationTitle("Review prior week")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { TaisaButtonControl("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

extension WeeklyWorkItem: @retroactive Identifiable {
    public var id: String { action.id }
}
