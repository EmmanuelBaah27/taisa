import SwiftUI
import TaisaStorage

struct LeadInsightSection: View {
    let insight: InsightRecord
    let openInsights: () -> Void

    var body: some View {
        Section("Worth your attention") {
            Button(action: openInsights) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Insight", systemImage: "lightbulb.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(insight.body)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("View insight")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 4)
            }
        }
        .accessibilityIdentifier("home.lead-insight")
    }
}
