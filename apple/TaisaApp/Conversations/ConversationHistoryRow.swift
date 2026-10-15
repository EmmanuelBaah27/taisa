import SwiftUI
import TaisaDesignSystem
import TaisaStorage

struct ConversationHistoryRow: View {
    let conversation: ConversationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.tight.rawValue) {
            Text(formattedDate)
                .font(TaisaTypography.metadata.font)
                .foregroundStyle(TaisaColor.mutedForeground.color)
            Text(conversation.title)
                .font(TaisaTypography.body.font.weight(.medium))
                .foregroundStyle(TaisaColor.foreground.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, TaisaSpacing.compact.rawValue)
        .accessibilityElement(children: .combine)
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(conversation.updatedAtMS) / 1_000)
        if Calendar.current.isDateInToday(date) {
            return "Today, \(date.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
