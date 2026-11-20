import SwiftUI
import TaisaDesignSystem
import TaisaHome
import TaisaStorage

struct InsightDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let model: InsightsModel
    let insight: InsightRecord

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                TaisaChildPageHeader("Insight") { dismiss() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(TaisaColor.background.color.ignoresSafeArea())
            .task(id: insight.id) { await model.loadDetail(insight: insight) }
    }

    @ViewBuilder private var content: some View {
        switch model.detailState {
        case .idle, .loading:
            TaisaProgressView("Loading evidence…")
        case let .content(detail) where detail.insight.id == insight.id:
            List {
                Section {
                    TaisaText(role: .heading, content: detail.insight.body)
                }
                TaisaSection("Sources") {
                    if detail.sources.isEmpty {
                        TaisaText(role: .body, color: .mutedForeground, content: "No available sources")
                    } else {
                        ForEach(detail.sources, id: \.id) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                TaisaText(role: .label, content: source.sourceType.capitalized)
                                if !source.excerpt.isEmpty {
                                    TaisaText(role: .body, color: .mutedForeground, content: source.excerpt)
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("insight.detail.sources")
                TaisaSection("Revisions") {
                    if detail.revisions.isEmpty {
                        TaisaText(role: .body, color: .mutedForeground, content: "No revisions")
                    } else {
                        ForEach(detail.revisions, id: \.id) { revision in
                            VStack(alignment: .leading, spacing: 4) {
                                TaisaText(role: .body, content: revision.proposedBody)
                                TaisaText(role: .metadata, color: .mutedForeground, content: revision.status.label)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("insight.detail.revisions")
            }
        case .content:
            TaisaProgressView("Loading evidence…")
        case let .failure(failedInsight) where failedInsight.id == insight.id:
            ContentUnavailableView {
                TaisaIconLabel("Evidence unavailable", icon: .warning)
            } description: {
                TaisaText(role: .body, content: "Taisa couldn’t read the grounding for this insight.")
            } actions: {
                TaisaButtonControl("Try again") { Task { await model.loadDetail(insight: insight) } }
            }
        case .failure:
            TaisaProgressView("Loading evidence…")
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
