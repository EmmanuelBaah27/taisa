import SwiftUI
import TaisaDesignSystem
import TaisaStorage

struct LeadInsightSection: View {
    let insight: InsightRecord
    let openInsights: () -> Void

    var body: some View {
        TaisaSection("Worth your attention") {
            TaisaPressable(action: { openInsights() }) {
                VStack(alignment: .leading, spacing: 8) {
                    TaisaIconLabel("Insight", icon: .insights)
                        .font(TaisaTypography.label.font)
                        .foregroundStyle(.secondary)
                    TaisaText(role: .childHeaderTitle, color: .foreground, content: insight.body)
                        .multilineTextAlignment(.leading)
                    TaisaText(role: .label, content: "View insight")
                }
                .padding(.vertical, 4)
            }
        }
        .accessibilityIdentifier("home.lead-insight")
    }
}
