import SwiftUI
import TaisaDesignSystem
import TaisaStorage

struct ConversationHistoryRow: View {
    let conversation: ConversationRecord
    let preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TaisaText(role: .metadata, color: .mutedForeground, content: formattedDate)
            TaisaText(role: .taskTitle, color: .foreground, content: conversation.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let preview, !preview.isEmpty {
                TaisaText(role: .taskSupporting, color: .mutedForeground, content: preview)
                    .lineLimit(1)
                    .frame(height: TaisaControlMetric.chatPreviewLineHeight, alignment: .topLeading)
                    .clipped()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .padding(.vertical, TaisaSpacing.control.rawValue)
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
