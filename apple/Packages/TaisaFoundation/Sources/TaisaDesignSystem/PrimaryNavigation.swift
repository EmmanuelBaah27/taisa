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

    @ViewBuilder public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            navigationItems
                .padding(6)
                .glassEffect(.regular.interactive(), in: .capsule)
                .shadow(color: TaisaColor.foreground.color.opacity(0.04), radius: 14)
        } else {
            navigationItems
                .padding(6)
                .background(TaisaColor.background.color, in: Capsule())
                .overlay { Capsule().stroke(TaisaColor.background.color, lineWidth: 1) }
                .shadow(color: TaisaColor.foreground.color.opacity(0.04), radius: 14)
        }
    }

    private var navigationItems: some View {
        HStack(spacing: TaisaSpacing.tight.rawValue) {
            ForEach(items, id: \.0) { item, label, icon in
                Button { select(item) } label: {
                    HStack(spacing: TaisaSpacing.compact.rawValue) {
                        CentralIcon(icon)
                            .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)

                        if selection == item {
                            Text(label)
                                .font(TaisaTypography.navigationLabel.font)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(selection == item ? TaisaColor.foreground.color : TaisaColor.inactiveForeground.color)
                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                    .frame(
                        minWidth: TaisaControlMetric.primaryNavigationItemWidth,
                        minHeight: TaisaControlMetric.primaryNavigationItemHeight
                    )
                    .contentShape(Capsule())
                    .background {
                        if selection == item {
                            selectedSurface
                                .matchedGeometryEffect(id: "primary-navigation-selection", in: selectionCapsule)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .accessibilityLabel(label)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var selectedSurface: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Capsule()
                .fill(TaisaColor.selectedSurface.color.opacity(0.72))
        } else {
            Capsule().fill(TaisaColor.selectedSurface.color)
        }
    }

    private func select(_ item: Item) {
        guard selection != item else { return }
        selection = item
    }
}
