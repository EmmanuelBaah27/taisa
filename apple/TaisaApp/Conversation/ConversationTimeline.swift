import SwiftUI
import TaisaDesignSystem
import TaisaStorage
import UIKit

enum ConversationTimelineLayout {
    static let userBubbleWidthFraction: CGFloat = 0.85
    static let jumpIconSize: CGFloat = 20
    static let jumpVisibilityThreshold: CGFloat = 160
    static let ordinaryMessageSpacing: CGFloat = 12
    static let userToAssistantSpacing: CGFloat = 32
    static let firstMessageTopSpacing: CGFloat = 8

    static func spacing(afterRole: String, beforeRole: String?) -> CGFloat {
        guard beforeRole != nil else { return 0 }
        return afterRole == "user" && beforeRole == "assistant"
            ? userToAssistantSpacing
            : ordinaryMessageSpacing
    }

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
    let layoutDirection: LayoutDirection

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
        let originX = layoutDirection == .rightToLeft
            ? bounds.minX + trailingInset
            : bounds.maxX - trailingInset - bubbleSize.width
        subview.place(
            at: CGPoint(x: originX, y: bounds.minY),
            proposal: ProposedViewSize(bubbleSize)
        )
    }
}

struct ConversationTimeline: View {
    static let userPreviewLineLimit = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    let messages: [MessageRecord]
    let assistantResponses: [String: AssistantResponseRecord]
    let updatingResponseAfter: String?
    let streamingResponse: String
    let isThinking: Bool
    let correct: (MessageRecord) -> Void
    let saveFeedback: (String, ResponseFeedbackDirection?, [ResponseQualityFactor], String?) -> Void
    let acceptProposal: (String) -> Void
    let dismissProposal: (String) -> Void
    @State private var isAwayFromLatest = false
    @State private var hasPositionedInitialMessages = false
    @State private var expandedUserMessages: Set<String> = []

    init(
        messages: [MessageRecord],
        assistantResponses: [String: AssistantResponseRecord] = [:],
        updatingResponseAfter: String? = nil,
        streamingResponse: String = "",
        isThinking: Bool = false,
        correct: @escaping (MessageRecord) -> Void,
        saveFeedback: @escaping (String, ResponseFeedbackDirection?, [ResponseQualityFactor], String?) -> Void = { _, _, _, _ in },
        acceptProposal: @escaping (String) -> Void = { _ in },
        dismissProposal: @escaping (String) -> Void = { _ in }
    ) {
        self.messages = messages
        self.assistantResponses = assistantResponses
        self.updatingResponseAfter = updatingResponseAfter
        self.streamingResponse = streamingResponse
        self.isThinking = isThinking
        self.correct = correct
        self.saveFeedback = saveFeedback
        self.acceptProposal = acceptProposal
        self.dismissProposal = dismissProposal
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: TaisaSpacing.tight.rawValue) {
                            if message.role == "user" {
                                TrailingMaximumWidthLayout(
                                    trailingInset: TaisaSpacing.standard.rawValue,
                                    layoutDirection: layoutDirection
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
                                if let response = assistantResponses[message.id] {
                                    AssistantResponseActions(
                                        response: response,
                                        saveFeedback: { direction, factors, detail in
                                            saveFeedback(message.id, direction, factors, detail)
                                        },
                                        acceptProposal: acceptProposal,
                                        dismissProposal: dismissProposal
                                    )
                                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                                }
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
                        .padding(
                            .bottom,
                            ConversationTimelineLayout.spacing(
                                afterRole: message.role,
                                beforeRole: messages.indices.contains(index + 1)
                                    ? messages[index + 1].role
                                    : (isThinking || !streamingResponse.isEmpty ? "assistant" : nil)
                            )
                        )
                    }
                    if isThinking, streamingResponse.isEmpty {
                        ThinkingIndicator()
                            .padding(.horizontal, TaisaSpacing.standard.rawValue)
                            .accessibilityIdentifier("conversation.thinking")
                            .id("conversation.thinking")
                    } else if !streamingResponse.isEmpty {
                        Text((try? AttributedString(markdown: streamingResponse)) ?? AttributedString(streamingResponse))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TaisaSpacing.standard.rawValue)
                            .accessibilityIdentifier("conversation.streaming-response")
                            .id("conversation.streaming-response")
                    }
                }
                .padding(.top, ConversationTimelineLayout.firstMessageTopSpacing)
                .padding(.bottom, TaisaSpacing.standard.rawValue)
                Color.clear
                    .frame(height: 1)
                    .id("conversation.timeline-bottom")
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .contentMargins(
                .top,
                TaisaControlMetric.appBarHeight,
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
            .task(id: messages.last?.id) {
                guard messages.last != nil else { return }
                if !hasPositionedInitialMessages {
                    await Task.yield()
                    isAwayFromLatest = false
                    scrollToLatest(using: proxy, animated: false)
                    hasPositionedInitialMessages = true
                    return
                }
                guard !isAwayFromLatest else { return }
                await Task.yield()
                scrollToLatest(using: proxy, animated: ConversationTimelineMotion.animatesNewMessage(reduceMotion: reduceMotion))
            }
            .onChange(of: streamingResponse) { _, _ in
                guard !isAwayFromLatest else { return }
                scrollToLatest(using: proxy, animated: false)
            }
            .onChange(of: isThinking) { _, thinking in
                guard thinking, !isAwayFromLatest else { return }
                scrollToLatest(using: proxy, animated: false)
            }
        }
        .accessibilityIdentifier("conversation.timeline")
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.smooth(duration: TaisaMotion.settle)) {
                proxy.scrollTo("conversation.timeline-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("conversation.timeline-bottom", anchor: .bottom)
        }
    }

    private func messageText(_ message: MessageRecord) -> Text {
        if message.role == "assistant", let markdown = try? AttributedString(markdown: message.body) { return Text(markdown) }
        return Text(message.body)
    }

    private func toggleExpansion(for messageID: String) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if expandedUserMessages.contains(messageID) {
                expandedUserMessages.remove(messageID)
            } else {
                expandedUserMessages.insert(messageID)
            }
        }
    }

    @ViewBuilder private func messageActions(for message: MessageRecord) -> some View {
        Button { UIPasteboard.general.string = message.body } label: {
            Label {
                Text("Copy")
            } icon: {
                CentralIcon(.copy)
                    .frame(width: 16, height: 16)
            }
        }
        if message.role == "user" {
            Button { correct(message) } label: {
                Label {
                    Text("Edit")
                } icon: {
                    CentralIcon(.edit)
                        .frame(width: 16, height: 16)
                }
            }
                .accessibilityIdentifier("conversation.correct-transcript")
        }
    }
}

private struct ThinkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        Text("Thinking")
            .font(TaisaTypography.body.font)
            .foregroundStyle(TaisaColor.mutedForeground.color)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                .clear,
                                TaisaColor.raisedSurface.color.opacity(0.9),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.55)
                        .offset(x: shimmerOffset * geometry.size.width)
                    }
                    .mask(Text("Thinking").font(TaisaTypography.body.font))
                    .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Thinking")
            .onAppear {
                guard !reduceMotion else { return }
                shimmerOffset = -1
                withAnimation(
                    .linear(duration: TaisaMotion.settle * 3)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 1.5
                }
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
