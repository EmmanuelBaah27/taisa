import SwiftUI

public struct ConversationOpeningPlaceholder: View {
    public enum Contract {
        public static let messageCount = 3
        public static let usesSharedFades = true
        public static let reduceMotionIsStatic = true
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerMoves = false
    private let title: String
    private let onDismiss: @MainActor () -> Void

    public init(title: String, onDismiss: @escaping @MainActor () -> Void) {
        self.title = title
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TaisaColor.background.color.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: TaisaSpacing.page.rawValue) {
                    placeholderMessage(isUser: true, height: TaisaSpacing.page.rawValue * 2)
                    placeholderMessage(isUser: false, height: TaisaSpacing.page.rawValue * 3)
                    placeholderMessage(isUser: true, height: TaisaSpacing.page.rawValue * 2)
                }
                .padding(.top, TaisaControlMetric.appBarHeight + TaisaSpacing.page.rawValue)

                Spacer(minLength: TaisaSpacing.page.rawValue)

                Capsule()
                    .fill(TaisaColor.raisedSurface.color)
                    .frame(height: TaisaControlMetric.recordingButtonHeight)
                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                    .padding(.bottom, TaisaSpacing.section.rawValue)
                    .background { PageEdgeFade(.navigation).ignoresSafeArea(edges: [.horizontal, .bottom]) }
                    .placeholderShimmer(active: shimmerMoves && !reduceMotion)
            }

            ConversationPageHeader(title: title, onDismiss: onDismiss)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening conversation")
        .onAppear { shimmerMoves = true }
    }

    private func placeholderMessage(isUser: Bool, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue)
            .fill(TaisaColor.subtleSurface.color)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .padding(.leading, isUser ? TaisaSpacing.page.rawValue * 2 : TaisaSpacing.standard.rawValue)
            .padding(.trailing, isUser ? TaisaSpacing.standard.rawValue : TaisaSpacing.page.rawValue * 2)
            .placeholderShimmer(active: shimmerMoves && !reduceMotion)
    }
}

private extension View {
    func placeholderShimmer(active: Bool) -> some View {
        modifier(PlaceholderShimmerModifier(active: active))
    }
}

private struct PlaceholderShimmerModifier: ViewModifier {
    let active: Bool
    @State private var travel = TaisaEffect.placeholderTravelStart

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            TaisaColor.background.color.opacity(TaisaEffect.placeholderHighlightOpacity),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * TaisaEffect.placeholderHighlightWidthFraction)
                    .offset(x: travel * geometry.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue))
                .allowsHitTesting(false)
            }
        }
        .onAppear { updateTravel() }
        .onChange(of: active) { _, _ in updateTravel() }
    }

    private func updateTravel() {
        guard active else {
            travel = TaisaEffect.placeholderTravelStart
            return
        }
        travel = TaisaEffect.placeholderTravelStart
        withAnimation(.linear(duration: TaisaMotion.settle * 3).repeatForever(autoreverses: false)) {
            travel = TaisaEffect.placeholderTravelEnd
        }
    }
}
