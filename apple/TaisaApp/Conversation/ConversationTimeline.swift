import SwiftUI
import TaisaDesignSystem
import TaisaStorage
import UIKit

enum ConversationTimelineLayout {
    static let userBubbleWidthFraction: CGFloat = 0.85
    static let jumpIconSize: CGFloat = 20
}

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
                        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: TaisaSpacing.tight.rawValue) {
                            if message.role == "user" {
                                ExpandableUserMessage(
                                    message: message,
                                    isExpanded: expandedUserMessages.contains(message.id),
                                    toggleExpansion: { toggleExpansion(for: message.id) }
                                )
                                .containerRelativeFrame(.horizontal, alignment: .trailing) { width, _ in
                                    width * ConversationTimelineLayout.userBubbleWidthFraction
                                        - TaisaSpacing.standard.rawValue
                                }
                                .padding(.trailing, TaisaSpacing.standard.rawValue)
                                .contextMenu { messageActions(for: message) }
                            } else {
                                messageText(message)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                                    .contextMenu { messageActions(for: message) }
                            }
                            if updatingResponseAfter == message.id {
                                Text("Updating response…")
                                    .font(TaisaTypography.metadata.font)
                                    .foregroundStyle(TaisaColor.mutedForeground.color)
                                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("conversation.message.\(message.id)")
                        .id(message.id)
                    }
                }
                .padding(.vertical, TaisaSpacing.standard.rawValue)
                .background(NativeConversationScrollPhysics())
            }
            .contentMargins(
                .top,
                TaisaControlMetric.appBarHeight + TaisaSpacing.standard.rawValue,
                for: .scrollContent
            )
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 48
            } action: { _, away in isAwayFromLatest = away }
            .overlay(alignment: .bottom) {
                if isAwayFromLatest, let latest = messages.last?.id {
                    TaisaSecondaryCapsuleButton(action: {
                        withAnimation(.easeOut(duration: TaisaMotion.fast)) {
                            proxy.scrollTo(latest, anchor: .bottom)
                        }
                    }) {
                        HStack(spacing: TaisaSpacing.compact.rawValue) {
                            Text("Jump to latest").font(TaisaTypography.navigationLabel.font)
                            CentralIcon(.chevronDown)
                                .frame(
                                    width: ConversationTimelineLayout.jumpIconSize,
                                    height: ConversationTimelineLayout.jumpIconSize
                                )
                        }
                        .padding(.horizontal, TaisaSpacing.standard.rawValue)
                    }
                    .padding(.bottom, TaisaSpacing.standard.rawValue)
                    .accessibilityIdentifier("conversation.jump-to-latest")
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

    private func toggleExpansion(for messageID: String) {
        if expandedUserMessages.contains(messageID) {
            expandedUserMessages.remove(messageID)
        } else {
            expandedUserMessages.insert(messageID)
        }
    }

    @ViewBuilder private func messageActions(for message: MessageRecord) -> some View {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.body }
        if message.role == "user" {
            Button("Edit", systemImage: "pencil") { correct(message) }
                .accessibilityIdentifier("conversation.correct-transcript")
        }
    }
}

private struct ExpandableUserMessage: View {
    let message: MessageRecord
    let isExpanded: Bool
    let toggleExpansion: () -> Void
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > limitedHeight + 1 }

    var body: some View {
        VStack(alignment: .trailing, spacing: TaisaSpacing.compact.rawValue) {
            Text(message.body)
                .lineLimit(isExpanded ? nil : ConversationTimeline.userPreviewLineLimit)
                .background { measuredFullText }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: LimitedMessageHeightKey.self, value: proxy.size.height)
                    }
                }

            if isExpanded || isTruncated {
                Button(isExpanded ? "Show less" : "Show more", action: toggleExpansion)
                    .font(TaisaTypography.metadata.font.weight(.medium))
                    .foregroundStyle(TaisaColor.mutedForeground.color)
                    .accessibilityIdentifier("conversation.message.\(message.id).expansion")
            }
        }
        .padding(TaisaSpacing.control.rawValue)
        .background(TaisaColor.subtleSurface.color, in: RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue))
        .onPreferenceChange(LimitedMessageHeightKey.self) { limitedHeight = $0 }
        .onPreferenceChange(FullMessageHeightKey.self) { fullHeight = $0 }
    }

    private var measuredFullText: some View {
        Text(message.body)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: FullMessageHeightKey.self, value: proxy.size.height)
                }
            }
    }
}

private struct LimitedMessageHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct FullMessageHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct NativeConversationScrollPhysics: UIViewRepresentable {
    func makeUIView(context: Context) -> NativeConversationScrollPhysicsView {
        NativeConversationScrollPhysicsView()
    }

    func updateUIView(_ uiView: NativeConversationScrollPhysicsView, context: Context) {
        uiView.applyToContainingScrollView()
    }
}

private final class NativeConversationScrollPhysicsView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyToContainingScrollView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyToContainingScrollView()
    }

    func applyToContainingScrollView() {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                scrollView.decelerationRate = .normal
                scrollView.bounces = true
                scrollView.alwaysBounceVertical = true
                return
            }
            candidate = view.superview
        }
    }
}

enum ConversationTimelineMotion {
    static func animatesNewMessage(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
