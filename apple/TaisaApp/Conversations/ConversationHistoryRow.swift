import SwiftUI
import TaisaDesignSystem
import TaisaStorage

struct ConversationHistoryRow: View {
    let conversation: ConversationRecord
    let preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedDate)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(TaisaColor.mutedForeground.color)
            Text(conversation.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(TaisaColor.foreground.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(TaisaColor.mutedForeground.color)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(TaisaSpacing.standard.rawValue)
        .background(TaisaColor.subtleSurface.color)
        .overlay(alignment: .bottom) {
            TaisaColor.background.color
                .frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("conversation.history.row.\(conversation.id)")
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(conversation.updatedAtMS) / 1_000)
        if Calendar.current.isDateInToday(date) {
            return "Today, \(date.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
