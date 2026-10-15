import SwiftUI

public struct ConversationPageHeader: View {
    public enum Contract { public static let usesSharedHeaderFade = true }
    private let title: String
    private let onDismiss: @MainActor () -> Void

    public init(title: String, onDismiss: @escaping @MainActor () -> Void) {
        self.title = title; self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(.system(.headline, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: TaisaControlMetric.conversationTitleWidth, alignment: .leading)
            Spacer(minLength: TaisaSpacing.compact.rawValue)
            TaisaSecondaryIconButton(icon: .chevronDown, accessibilityLabel: "Close conversation", action: onDismiss)
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: TaisaControlMetric.appBarHeight)
        .background { PageEdgeFade(.header).ignoresSafeArea(edges: .horizontal) }
    }
}
