import SwiftUI
import TaisaDesignSystem
import TaisaStorage
import UIKit

enum ConversationTimelineLayout {
    static let userBubbleWidthFraction: CGFloat = 0.85
    static let jumpIconSize: CGFloat = 20
    static let jumpVisibilityThreshold: CGFloat = 160

    static func shouldShowJumpToLatest(distanceFromBottom: CGFloat) -> Bool {
        distanceFromBottom >= jumpVisibilityThreshold
    }

    static func userBubbleWidth(
        intrinsicWidth: CGFloat,
        containerWidth: CGFloat,
        trailingInset: CGFloat
    ) -> CGFloat {
        min(intrinsicWidth, max(0, containerWidth * userBubbleWidthFraction - trailingInset))
    }
}

private struct TrailingMaximumWidthLayout: Layout {
    let trailingInset: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let containerWidth = proposal.width ?? subview.sizeThatFits(.unspecified).width + trailingInset
        let intrinsicWidth = subview.sizeThatFits(.unspecified).width
        let bubbleWidth = ConversationTimelineLayout.userBubbleWidth(
            intrinsicWidth: intrinsicWidth,
            containerWidth: containerWidth,
            trailingInset: trailingInset
        )
        let bubbleSize = subview.sizeThatFits(ProposedViewSize(width: bubbleWidth, height: proposal.height))
        return CGSize(width: containerWidth, height: bubbleSize.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let intrinsicWidth = subview.sizeThatFits(.unspecified).width
        let bubbleWidth = ConversationTimelineLayout.userBubbleWidth(
            intrinsicWidth: intrinsicWidth,
            containerWidth: bounds.width,
            trailingInset: trailingInset
        )
        let bubbleSize = subview.sizeThatFits(ProposedViewSize(width: bubbleWidth, height: proposal.height))
        subview.place(
            at: CGPoint(x: bounds.maxX - trailingInset - bubbleSize.width, y: bounds.minY),
            proposal: ProposedViewSize(bubbleSize)
        )
    }
}

struct ConversationTimeline: View {
    static let userPreviewLineLimit = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let messages: [MessageRecord]
    let updatingResponseAfter: String?
    let streamingResponse: String
    let correct: (MessageRecord) -> Void
    @State private var isAwayFromLatest = false
    @State private var expandedUserMessages: Set<String> = []

    init(
        messages: [MessageRecord],
        updatingResponseAfter: String? = nil,
        streamingResponse: String = "",
        correct: @escaping (MessageRecord) -> Void
    ) {
        self.messages = messages
        self.updatingResponseAfter = updatingResponseAfter
        self.streamingResponse = streamingResponse
        self.correct = correct
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TaisaSpacing.control.rawValue) {
                    ForEach(messages, id: \.id) { message in
                        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: TaisaSpacing.tight.rawValue) {
                            if message.role == "user" {
                                TrailingMaximumWidthLayout(
                                    trailingInset: TaisaSpacing.standard.rawValue
                                ) {
                                    ExpandableUserMessage(
                                        message: message,
                                        isExpanded: expandedUserMessages.contains(message.id),
                                        toggleExpansion: { toggleExpansion(for: message.id) }
                                    )
                                    .contextMenu { messageActions(for: message) }
                                }
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
                    if !streamingResponse.isEmpty {
                        Text((try? AttributedString(markdown: streamingResponse)) ?? AttributedString(streamingResponse))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TaisaSpacing.standard.rawValue)
                            .accessibilityIdentifier("conversation.streaming-response")
                            .id("conversation.streaming-response")
                    }
                }
                .padding(.vertical, TaisaSpacing.standard.rawValue)
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .contentMargins(
                .top,
                TaisaControlMetric.appBarHeight + TaisaSpacing.standard.rawValue,
                for: .scrollContent
            )
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height
                    - geometry.containerSize.height
                    - geometry.contentOffset.y
                return ConversationTimelineLayout.shouldShowJumpToLatest(
                    distanceFromBottom: distanceFromBottom
                )
            } action: { _, away in isAwayFromLatest = away }
            .overlay(alignment: .bottom) {
                if isAwayFromLatest, !messages.isEmpty {
                    TaisaSecondaryCapsuleButton(action: {
                        isAwayFromLatest = false
                        scrollToLatest(using: proxy, animated: !reduceMotion)
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
            .onChange(of: messages.last?.id) { _, _ in
                guard !isAwayFromLatest else { return }
                scrollToLatest(using: proxy, animated: ConversationTimelineMotion.animatesNewMessage(reduceMotion: reduceMotion))
            }
            .onChange(of: streamingResponse) { _, _ in
                guard !isAwayFromLatest else { return }
                scrollToLatest(using: proxy, animated: false)
            }
        }
        .accessibilityIdentifier("conversation.timeline")
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        let anchorID = streamingResponse.isEmpty ? messages.last?.id : "conversation.streaming-response"
        guard let anchorID else { return }
        if animated {
            withAnimation(.smooth(duration: TaisaMotion.settle)) {
                proxy.scrollTo(anchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(anchorID, anchor: .bottom)
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
        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
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

enum ConversationTimelineMotion {
    static func animatesNewMessage(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
