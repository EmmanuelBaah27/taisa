import SwiftUI
import TaisaDesignSystem
import TaisaStorage

struct LeadInsightSection: View {
    let insight: InsightRecord
    let openInsights: () -> Void

    var body: some View {
        Section("Worth your attention") {
            Button(action: openInsights) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Insight", systemImage: "lightbulb.fill")
                        .font(TaisaTypography.label.font)
                        .foregroundStyle(.secondary)
                    Text(insight.body)
                        .font(TaisaTypography.childHeaderTitle.font)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("View insight")
                        .font(TaisaTypography.label.font)
                }
                .padding(.vertical, 4)
            }
        }
        .accessibilityIdentifier("home.lead-insight")
    }
}
