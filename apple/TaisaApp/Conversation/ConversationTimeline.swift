import SwiftUI
import TaisaStorage

struct ConversationTimeline: View {
    let messages: [MessageRecord]
    let correct: (MessageRecord) -> Void

    var body: some View {
        ScrollViewReader { proxy in
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
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onAppear { scrollToLatest(using: proxy, animated: false) }
            .onChange(of: messages.last?.id) { _, _ in
                scrollToLatest(using: proxy, animated: true)
            }
        }
        .accessibilityIdentifier("conversation.timeline")
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        guard let messageID = messages.last?.id else { return }
        if animated {
            withAnimation { proxy.scrollTo(messageID, anchor: .bottom) }
        } else {
            proxy.scrollTo(messageID, anchor: .bottom)
        }
    }
}
