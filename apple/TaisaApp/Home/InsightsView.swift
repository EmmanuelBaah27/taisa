import SwiftUI
import TaisaHome
import TaisaStorage

struct InsightsView: View {
    @State private var model: InsightsModel

    init(model: InsightsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        content
            .navigationTitle("Insights")
            .accessibilityIdentifier("insights.root")
            .task { if model.state == .idle { await model.load() } }
            .refreshable { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading insights…")
        case .empty:
            ContentUnavailableView(
                "No insights yet",
                systemImage: "lightbulb",
                description: Text("Confirmed patterns grounded in your work will appear here.")
            )
        case let .content(snapshot):
            List {
                insightSection("Current", identifier: "insights.current", records: snapshot.current)
                insightSection("Needs review", identifier: "insights.review", records: snapshot.reviewNeeded)
                insightSection("History", identifier: "insights.history", records: snapshot.history)
            }
        case .failure:
            ContentUnavailableView {
                Label("Insights unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Taisa couldn’t read your encrypted insights.")
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        }
    }

    private func insightSection(
        _ title: String,
        identifier: String,
        records: [InsightRecord]
    ) -> some View {
        Section(title) {
            if records.isEmpty {
                Text("None")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(records, id: \.id) { insight in
                    NavigationLink {
                        InsightDetailView(model: model, insight: insight)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(insight.body)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(insight.updatedAt, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

private extension InsightRecord {
    var updatedAt: Date { Date(timeIntervalSince1970: Double(updatedAtMS) / 1_000) }
}
