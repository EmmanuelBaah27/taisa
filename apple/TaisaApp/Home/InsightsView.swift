import SwiftUI
import TaisaDesignSystem
import TaisaHome
import TaisaStorage

struct InsightsView: View {
    @State private var model: InsightsModel

    init(model: InsightsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        content
            .taisaNavigationTitle("Insights")
            .accessibilityIdentifier("insights.root")
            .task { if model.state == .idle { await model.load() } }
            .refreshable { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .loading:
            TaisaProgressView("Loading insights…")
        case .empty:
            ContentUnavailableView {
                    TaisaIconLabel("No insights yet", icon: .insights, role: .heading)
                } description: {
                    TaisaText(role: .body, content: "Confirmed patterns grounded in your work will appear here.")
                }
        case let .content(snapshot):
            List {
                insightSection("Current", identifier: "insights.current", records: snapshot.current)
                insightSection("Needs review", identifier: "insights.review", records: snapshot.reviewNeeded)
                insightSection("History", identifier: "insights.history", records: snapshot.history)
            }
        case .failure:
            ContentUnavailableView {
                TaisaIconLabel("Insights unavailable", icon: .warning)
            } description: {
                TaisaText(role: .body, content: "Taisa couldn’t read your encrypted insights.")
            } actions: {
                TaisaButtonControl("Try again") { Task { await model.load() } }
            }
        }
    }

    private func insightSection(
        _ title: String,
        identifier: String,
        records: [InsightRecord]
    ) -> some View {
        TaisaSection(title) {
            if records.isEmpty {
                TaisaText(role: .body, color: .mutedForeground, content: "None")
            } else {
                ForEach(records, id: \.id) { insight in
                    NavigationLink {
                        InsightDetailView(model: model, insight: insight)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            TaisaText(role: .body, color: .foreground, content: insight.body)
                                .multilineTextAlignment(.leading)
                            TaisaText(role: .metadata, color: .mutedForeground, content: insight.updatedAt.formatted(.dateTime.day().month().year()))
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
