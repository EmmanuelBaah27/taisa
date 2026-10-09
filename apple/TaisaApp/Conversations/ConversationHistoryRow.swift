import SwiftUI
import TaisaStorage

struct ConversationHistoryRow: View {
    let conversation: ConversationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title).font(.headline)
            Text(Date(timeIntervalSince1970: Double(conversation.updatedAtMS) / 1_000), style: .relative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
