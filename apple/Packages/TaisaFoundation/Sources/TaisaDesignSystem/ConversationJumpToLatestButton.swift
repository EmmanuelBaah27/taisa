import SwiftUI

public struct ConversationJumpToLatestButton: View {
    public enum Contract {
        public static let size: CGFloat = 48
        public static let iconSize: CGFloat = 24
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
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(TaisaColor.mutedForeground.color)
                }
                CentralIcon(.chevronDown)
                    .frame(width: Contract.iconSize, height: Contract.iconSize)
                    .foregroundStyle(TaisaColor.foreground.color)
            }
            .frame(width: Contract.size, height: Contract.size)
        }
        .accessibilityLabel(Contract.accessibilityLabel)
        .accessibilityValue(isLoading ? "Taisa is responding" : "")
    }
}
