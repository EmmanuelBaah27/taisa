import SwiftUI
import TaisaDesignSystem
import TaisaStorage
import UIKit

enum ConversationTimelineLayout {
    enum NewMessageScrollAction: Equatable {
        case initialLatest
        case anchorUserMessage
        case preserveViewport
    }

    static let userBubbleWidthFraction: CGFloat = 0.85
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

    static func shouldShowJumpToLatest(
        actualContentFrame: CGRect,
        readableViewport: CGRect
    ) -> Bool {
        guard actualContentFrame != .zero, readableViewport != .zero else { return false }
        return actualContentFrame.maxY - readableViewport.maxY >= jumpVisibilityThreshold
    }

    static func newMessageScrollAction(
        hasPositionedInitialMessages: Bool,
        isSendingText: Bool,
        messageRole: String
    ) -> NewMessageScrollAction {
        if !hasPositionedInitialMessages, !isSendingText {
            return .initialLatest
        }
        return messageRole == "user" ? .anchorUserMessage : .preserveViewport
    }

    static func responseRunwayHeight(viewportHeight: CGFloat, preservesAnchoredTurn: Bool) -> CGFloat {
        guard preservesAnchoredTurn else { return 0 }
        return max(
            0,
            viewportHeight - TaisaControlMetric.appBarHeight - userToAssistantSpacing
        )
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
    let failedResponseUpdateAfter: String?
    let streamingResponse: String
    let streamingFinalMessageID: String?
    let isSendingText: Bool
    let isThinking: Bool
    let streamingDidFinish: @MainActor @Sendable () -> Void
    let retryResponseUpdate: @MainActor @Sendable () -> Void
    let keepEditedMessage: @MainActor @Sendable () -> Void
    let correct: (MessageRecord) -> Void
    let saveFeedback: (String, ResponseFeedbackDirection?, [ResponseQualityFactor], String?) -> Void
    let acceptProposal: (String) -> Void
    let dismissProposal: (String) -> Void
    @State private var isAwayFromLatest = false
    @State private var hasPositionedInitialMessages = false
    @State private var expandedUserMessages: Set<String> = []
    @State private var copiedConfirmationVisible = false
    @State private var readableViewportHeight: CGFloat = 0
    @State private var readableViewportFrame: CGRect = .zero
    @State private var actualContentFrame: CGRect = .zero
    @State private var anchoredUserMessageID: String?
    @State private var shouldReleaseAnchorWhenScrollSettles = false

    init(
        messages: [MessageRecord],
        assistantResponses: [String: AssistantResponseRecord] = [:],
        updatingResponseAfter: String? = nil,
        failedResponseUpdateAfter: String? = nil,
        streamingResponse: String = "",
        streamingFinalMessageID: String? = nil,
        isSendingText: Bool = false,
        isThinking: Bool = false,
        streamingDidFinish: @escaping @MainActor @Sendable () -> Void = {},
        retryResponseUpdate: @escaping @MainActor @Sendable () -> Void = {},
        keepEditedMessage: @escaping @MainActor @Sendable () -> Void = {},
        correct: @escaping (MessageRecord) -> Void,
        saveFeedback: @escaping (String, ResponseFeedbackDirection?, [ResponseQualityFactor], String?) -> Void = { _, _, _, _ in },
        acceptProposal: @escaping (String) -> Void = { _ in },
        dismissProposal: @escaping (String) -> Void = { _ in }
    ) {
        self.messages = messages
        self.assistantResponses = assistantResponses
        self.updatingResponseAfter = updatingResponseAfter
        self.failedResponseUpdateAfter = failedResponseUpdateAfter
        self.streamingResponse = streamingResponse
        self.streamingFinalMessageID = streamingFinalMessageID
        self.isSendingText = isSendingText
        self.isThinking = isThinking
        self.streamingDidFinish = streamingDidFinish
        self.retryResponseUpdate = retryResponseUpdate
        self.keepEditedMessage = keepEditedMessage
        self.correct = correct
        self.saveFeedback = saveFeedback
        self.acceptProposal = acceptProposal
        self.dismissProposal = dismissProposal
    }

    var body: some View {
        let presentedMessages = messages.filter { $0.id != streamingFinalMessageID }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(presentedMessages.enumerated()), id: \.element.id) { index, message in
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
                                if failedResponseUpdateAfter == message.id {
                                    InlineRecoveryAlert(
                                        contract: .responseUpdate,
                                        onCancel: keepEditedMessage,
                                        onRetry: retryResponseUpdate
                                    )
                                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                                    .accessibilityIdentifier("conversation.response-update-recovery")
                                } else {
                                    ConversationProgressState(label: "Updating response…")
                                        .foregroundStyle(TaisaColor.mutedForeground.color)
                                        .padding(.horizontal, TaisaSpacing.standard.rawValue)
                                }
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
                                beforeRole: presentedMessages.indices.contains(index + 1)
                                    ? presentedMessages[index + 1].role
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
                        TaisaStreamingText(streamingResponse, onRevealComplete: streamingDidFinish)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TaisaSpacing.standard.rawValue)
                            .accessibilityIdentifier("conversation.streaming-response")
                            .id(streamingFinalMessageID ?? "conversation.streaming-response.live")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("conversation.actual-content-bottom")
                        .accessibilityHidden(true)
                        .onGeometryChange(for: CGRect.self) { geometry in
                            geometry.frame(in: .global)
                        } action: { _, frame in
                            actualContentFrame = frame
                            refreshJumpVisibility()
                        }

                    let responseRunwayHeight = ConversationTimelineLayout.responseRunwayHeight(
                        viewportHeight: readableViewportHeight,
                        preservesAnchoredTurn: anchoredUserMessageID != nil
                    )
                    if responseRunwayHeight > 0 {
                        Spacer(minLength: 0)
                            .frame(height: responseRunwayHeight)
                            .accessibilityHidden(true)
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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, height in readableViewportHeight = height }
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting, anchoredUserMessageID != nil {
                    shouldReleaseAnchorWhenScrollSettles = true
                } else if newPhase == .idle, shouldReleaseAnchorWhenScrollSettles {
                    anchoredUserMessageID = nil
                    shouldReleaseAnchorWhenScrollSettles = false
                }
            }
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { _, frame in
                readableViewportFrame = frame
                refreshJumpVisibility()
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: TaisaSpacing.control.rawValue) {
                    if copiedConfirmationVisible {
                        TaisaToast(message: "Copied", dismiss: { copiedConfirmationVisible = false })
                    }
                    if isAwayFromLatest, !presentedMessages.isEmpty {
                        ConversationJumpToLatestButton(
                            isLoading: isThinking || !streamingResponse.isEmpty,
                            action: {
                                isAwayFromLatest = false
                                anchoredUserMessageID = nil
                                Task { @MainActor in
                                    await Task.yield()
                                    scrollToLatest(using: proxy, animated: !reduceMotion)
                                }
                            }
                        )
                        .accessibilityIdentifier("conversation.jump-to-latest")
                    }
                }
                .padding(.bottom, TaisaSpacing.standard.rawValue)
            }
            .task(id: messages.last?.id) {
                guard let message = messages.last else { return }
                let action = ConversationTimelineLayout.newMessageScrollAction(
                    hasPositionedInitialMessages: hasPositionedInitialMessages,
                    isSendingText: isSendingText,
                    messageRole: message.role
                )
                hasPositionedInitialMessages = true
                switch action {
                case .initialLatest:
                    await Task.yield()
                    isAwayFromLatest = false
                    scrollToLatest(using: proxy, animated: false)
                case .anchorUserMessage:
                    await Task.yield()
                    isAwayFromLatest = false
                    anchoredUserMessageID = message.id
                    shouldReleaseAnchorWhenScrollSettles = false
                    withAnimation(reduceMotion ? nil : .smooth(duration: TaisaMotion.settle)) {
                        proxy.scrollTo(message.id, anchor: .top)
                    }
                case .preserveViewport:
                    break
                }
            }
        }
        .accessibilityIdentifier("conversation.timeline")
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.smooth(duration: TaisaMotion.settle)) {
                proxy.scrollTo("conversation.actual-content-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("conversation.actual-content-bottom", anchor: .bottom)
        }
    }

    private func refreshJumpVisibility() {
        isAwayFromLatest = ConversationTimelineLayout.shouldShowJumpToLatest(
            actualContentFrame: actualContentFrame,
            readableViewport: readableViewportFrame
        )
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
        Button {
            UIPasteboard.general.string = message.body
            copiedConfirmationVisible = true
        } label: {
            Label {
                Text("Copy")
            } icon: {
                CentralIcon(.copy)
                    .frame(
                        width: TaisaControlMetric.contextMenuIcon,
                        height: TaisaControlMetric.contextMenuIcon
                    )
            }
        }
        if message.role == "user" {
            Button { correct(message) } label: {
                Label {
                    Text("Edit")
                } icon: {
                    CentralIcon(.edit)
                        .frame(
                            width: TaisaControlMetric.contextMenuIcon,
                            height: TaisaControlMetric.contextMenuIcon
                        )
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
        .background(TaisaColor.raisedSurface.color, in: RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue))
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
