import SwiftUI
import TaisaStorage
import UIKit

struct ConversationTimeline: View {
    static let userPreviewLineLimit = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let messages: [MessageRecord]
    let updatingResponseAfter: String?
    let correct: (MessageRecord) -> Void
    @State private var isAwayFromLatest = false
    @State private var expandedUserMessages: Set<String> = []

    init(messages: [MessageRecord], updatingResponseAfter: String? = nil, correct: @escaping (MessageRecord) -> Void) {
        self.messages = messages; self.updatingResponseAfter = updatingResponseAfter; self.correct = correct
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages, id: \.id) { message in
                        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                            Text(message.role == "assistant" ? "Taisa" : "You").font(.caption).foregroundStyle(.secondary)
                            messageText(message)
                                .lineLimit(userLineLimit(for: message))
                                .padding(message.role == "user" ? 12 : 0)
                                .background(message.role == "user" ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                                .contextMenu {
                                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.body }
                                    if message.role == "user" {
                                        Button("Edit", systemImage: "pencil") { correct(message) }
                                            .accessibilityIdentifier("conversation.correct-transcript")
                                    }
                                }
                            if message.role == "user", message.body.split(separator: "\n").count > Self.userPreviewLineLimit || message.body.count > 320 {
                                Button(expandedUserMessages.contains(message.id) ? "Show less" : "Show more") {
                                    if expandedUserMessages.contains(message.id) {
                                        expandedUserMessages.remove(message.id)
                                    } else {
                                        expandedUserMessages.insert(message.id)
                                    }
                                }
                                .font(.caption.weight(.medium))
                                .accessibilityIdentifier("conversation.message.\(message.id).expansion")
                            }
                            if updatingResponseAfter == message.id {
                                Text("Updating response…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("conversation.message.\(message.id)")
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 48
            } action: { _, away in isAwayFromLatest = away }
            .overlay(alignment: .bottomTrailing) {
                if isAwayFromLatest, let latest = messages.last?.id {
                    Button("Jump to latest") { proxy.scrollTo(latest, anchor: .bottom) }
                        .buttonStyle(.borderedProminent).padding()
                }
            }
            .onAppear { scrollToLatest(using: proxy, animated: false) }
            .onChange(of: messages.last?.id) { _, _ in
                guard !isAwayFromLatest else { return }
                scrollToLatest(using: proxy, animated: ConversationTimelineMotion.animatesNewMessage(reduceMotion: reduceMotion))
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

    private func messageText(_ message: MessageRecord) -> Text {
        if message.role == "assistant", let markdown = try? AttributedString(markdown: message.body) { return Text(markdown) }
        return Text(message.body)
    }

    private func userLineLimit(for message: MessageRecord) -> Int? {
        guard message.role == "user", !expandedUserMessages.contains(message.id) else { return nil }
        return Self.userPreviewLineLimit
    }
}

enum ConversationTimelineMotion {
    static func animatesNewMessage(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
