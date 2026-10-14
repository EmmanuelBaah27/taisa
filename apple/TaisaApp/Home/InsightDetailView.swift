import SwiftUI
import TaisaHome
import TaisaStorage

struct InsightDetailView: View {
    let model: InsightsModel
    let insight: InsightRecord

    var body: some View {
        content
            .navigationTitle("Insight")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: insight.id) { await model.loadDetail(insight: insight) }
    }

    @ViewBuilder private var content: some View {
        switch model.detailState {
        case .idle, .loading:
            ProgressView("Loading evidence…")
        case let .content(detail) where detail.insight.id == insight.id:
            List {
                Section {
                    Text(detail.insight.body)
                        .font(.title3.weight(.semibold))
                }
                Section("Sources") {
                    if detail.sources.isEmpty {
                        Text("No available sources")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(detail.sources, id: \.id) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.sourceType.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                if !source.excerpt.isEmpty {
                                    Text(source.excerpt)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("insight.detail.sources")
                Section("Revisions") {
                    if detail.revisions.isEmpty {
                        Text("No revisions")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(detail.revisions, id: \.id) { revision in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(revision.proposedBody)
                                Text(revision.status.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("insight.detail.revisions")
            }
        case .content:
            ProgressView("Loading evidence…")
        case let .failure(failedInsight) where failedInsight.id == insight.id:
            ContentUnavailableView {
                Label("Evidence unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Taisa couldn’t read the grounding for this insight.")
            } actions: {
                Button("Try again") { Task { await model.loadDetail(insight: insight) } }
            }
        case .failure:
            ProgressView("Loading evidence…")
        }
    }
}

private extension InsightRevisionStatus {
    var label: String {
        switch self {
        case .proposed: "Proposed"
        case .accepted: "Accepted"
        case .rejected: "Rejected"
        }
    }
}
