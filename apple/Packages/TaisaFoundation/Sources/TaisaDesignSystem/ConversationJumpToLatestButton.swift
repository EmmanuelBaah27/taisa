import SwiftUI

public struct ConversationJumpToLatestButton: View {
    public enum Contract {
        public static let size: CGFloat = 48
        public static let iconSize: CGFloat = 24
        public static let loadingRingLineWidth: CGFloat = 2
        public static let loadingRingTracksOuterStroke = true
        public static let accessibilityLabel = "Jump to latest response"
    }

    private let isLoading: Bool
    private let action: @MainActor () -> Void

    public init(isLoading: Bool, action: @escaping @MainActor () -> Void) {
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        TaisaSecondaryCapsuleButton(height: Contract.size, action: action) {
            CentralIcon(.chevronDown)
                .frame(width: Contract.iconSize, height: Contract.iconSize)
                .foregroundStyle(TaisaColor.foreground.color)
                .frame(width: Contract.size, height: Contract.size)
        }
        .overlay {
            if isLoading {
                LoadingRing()
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(Contract.accessibilityLabel)
        .accessibilityValue(isLoading ? "Taisa is responding" : "")
    }
}

private struct LoadingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = Angle.zero

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.78)
            .stroke(
                TaisaColor.mutedForeground.color,
                style: StrokeStyle(
                    lineWidth: ConversationJumpToLatestButton.Contract.loadingRingLineWidth,
                    lineCap: .round
                )
            )
            .padding(1)
            .rotationEffect(rotation)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = .degrees(360)
                }
            }
    }
}
