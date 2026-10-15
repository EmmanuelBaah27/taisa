import SwiftUI

public enum PrimaryNavigationTransition: Sendable, Equatable {
    case spatial
    case instant
}

public enum PrimaryNavigationMotion {
    public static func transition(reduceMotion: Bool) -> PrimaryNavigationTransition {
        reduceMotion ? .instant : .spatial
    }
}

public struct PrimaryNavigation<Item: Hashable>: View {
    public let items: [(Item, String, CentralIconName)]
    @Binding private var selection: Item
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionCapsule

    public init(items: [(Item, String, CentralIconName)], selection: Binding<Item>) {
        self.items = items; _selection = selection
    }

    public var body: some View {
        HStack(spacing: TaisaSpacing.tight.rawValue) {
            ForEach(items, id: \.0) { item, label, icon in
                Button { select(item) } label: {
                    HStack(spacing: TaisaSpacing.compact.rawValue) {
                        CentralIcon(icon)
                            .frame(width: 24, height: 24)

                        if selection == item {
                            Text(label)
                                .font(TaisaTypography.body.font.weight(.medium))
                                .lineLimit(1)
                                .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .foregroundStyle(selection == item ? TaisaColor.foreground.color : TaisaColor.mutedForeground.color)
                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                    .frame(minHeight: 48)
                    .background {
                        if selection == item {
                            Capsule()
                                .fill(TaisaColor.selectedSurface.color)
                                .matchedGeometryEffect(id: "primary-navigation-selection", in: selectionCapsule)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(6)
        .background(TaisaColor.background.color, in: Capsule())
        .overlay { Capsule().stroke(TaisaColor.background.color, lineWidth: 1) }
        .shadow(color: TaisaColor.foreground.color.opacity(0.04), radius: 14)
    }

    private func select(_ item: Item) {
        guard selection != item else { return }
        if PrimaryNavigationMotion.transition(reduceMotion: reduceMotion) == .instant {
            selection = item
        } else {
            withAnimation(.snappy) { selection = item }
        }
    }
}
