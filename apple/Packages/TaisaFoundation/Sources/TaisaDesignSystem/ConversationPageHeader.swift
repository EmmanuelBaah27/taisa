import SwiftUI

public struct ConversationPageHeader: View {
    public enum DismissPlacement: Sendable { case leading, trailing }
    public enum Contract {
        public static let usesSharedHeaderFade = true
        public static let dismissPlacement = DismissPlacement.leading
    }
    private let title: String
    private let onDismiss: @MainActor () -> Void

    public init(title: String, onDismiss: @escaping @MainActor () -> Void) {
        self.title = title; self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            TaisaText(role: .navigationLabel, content: title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: TaisaControlMetric.conversationTitleWidth, alignment: .center)
            HStack {
                TaisaSecondaryIconButton(
                    icon: .chevronDown,
                    accessibilityLabel: "Close conversation",
                    elevation: .floating,
                    action: onDismiss
                )
                Spacer()
            }
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: TaisaControlMetric.appBarHeight)
        .background {
            PageEdgeFade(.header)
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
    }
}
