import SwiftUI
import TaisaHome
import TaisaStorage

struct ThisWeekSection: View {
    let items: [WeeklyWorkItem]
    let unresolvedPriorWeekCount: Int
    let model: HomeModel

    @State private var planningItem: WeeklyWorkItem?
    @State private var showsPriorWeekReview = false

    var body: some View {
        Section {
            if unresolvedPriorWeekCount > 0 {
                Button {
                    showsPriorWeekReview = true
                } label: {
                    Label(
                        "Review \(unresolvedPriorWeekCount) unfinished \(unresolvedPriorWeekCount == 1 ? "item" : "items")",
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .accessibilityIdentifier("home.prior-week.review")
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "A clear week",
                    systemImage: "checkmark.circle",
                    description: Text("Add work when you decide what matters next.")
                )
            } else {
                ForEach(items, id: \.action.id) { item in
                    weeklyRow(item)
                }
            }

            if model.canUndoCompletion {
                Button("Undo completion", systemImage: "arrow.uturn.backward") {
                    Task { await model.undoCompletion() }
                }
                .accessibilityIdentifier("home.this-week.undo")
            }
        } header: {
            Text("This Week")
        }
        .accessibilityIdentifier("home.this-week")
        .sheet(item: $planningItem) { item in
            WeeklyPlanningSheet(item: item, model: model)
        }
        .sheet(isPresented: $showsPriorWeekReview) {
            PriorWeekReviewSheet(unresolvedCount: unresolvedPriorWeekCount)
        }
    }

    private func weeklyRow(_ item: WeeklyWorkItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                Task { await model.complete(actionID: item.action.id) }
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.action.title)")
            .accessibilityIdentifier("home.this-week.complete")

            Button {
                planningItem = item
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.action.title)
                        .foregroundStyle(.primary)
                    if !item.action.detail.isEmpty {
                        Text(item.action.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let plannedDayMS = item.placement.plannedDayMS {
                        Text(Date(timeIntervalSince1970: Double(plannedDayMS) / 1_000), format: .dateTime.weekday(.wide))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change when this is planned")
        }
    }
}

private struct WeeklyPlanningSheet: View {
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

private struct PriorWeekReviewSheet: View {
    let unresolvedCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Unfinished work", systemImage: "clock.arrow.circlepath")
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

extension WeeklyWorkItem: @retroactive Identifiable {
    public var id: String { action.id }
}
