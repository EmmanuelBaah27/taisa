import SwiftUI
import TaisaStorage

struct ConversationTimeline: View {
    let messages: [MessageRecord]
    let correct: (MessageRecord) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(messages, id: \.id) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role == "assistant" ? "Taisa" : "You").font(.caption).foregroundStyle(.secondary)
                        Text(message.body).textSelection(.enabled)
                        if message.role == "user" {
                            Button("Correct transcript") { correct(message) }
                                .font(.caption)
                                .accessibilityIdentifier("conversation.correct-transcript")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .accessibilityIdentifier("conversation.timeline")
    }
}
