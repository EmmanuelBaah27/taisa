import SwiftUI

public enum PrimaryNavigationTransition: Sendable, Equatable {
    case interactiveSpatial
    case instant
}

public enum PrimaryNavigationMotion {
    public static func transition(reduceMotion: Bool) -> PrimaryNavigationTransition {
        reduceMotion ? .instant : .interactiveSpatial
    }
}

public struct PrimaryNavigation<Item: Hashable>: View {
    public let items: [(Item, String, CentralIconName)]
    @Binding private var selection: Item
    @State private var visualSelection: Item
    @State private var selectionGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionCapsule

    public init(items: [(Item, String, CentralIconName)], selection: Binding<Item>) {
        self.items = items
        _selection = selection
        _visualSelection = State(initialValue: selection.wrappedValue)
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

                        if visualSelection == item {
                            Text(label)
                                .font(TaisaTypography.navigationLabel.font)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(visualSelection == item ? TaisaColor.foreground.color : TaisaColor.inactiveForeground.color)
                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                    .frame(
                        minWidth: TaisaControlMetric.primaryNavigationItemWidth,
                        minHeight: TaisaControlMetric.primaryNavigationItemHeight
                    )
                    .contentShape(Capsule())
                    .background {
                        if visualSelection == item {
                            selectedSurface
                                .matchedGeometryEffect(id: "primary-navigation-selection", in: selectionCapsule)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .accessibilityLabel(label)
                .accessibilityAddTraits(visualSelection == item ? .isSelected : [])
            }
        }
        .onChange(of: selection) { _, newSelection in
            guard visualSelection != newSelection else { return }
            selectionGeneration += 1
            visualSelection = newSelection
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
        guard visualSelection != item else { return }
        selectionGeneration += 1
        let generation = selectionGeneration

        if PrimaryNavigationMotion.transition(reduceMotion: reduceMotion) == .instant {
            visualSelection = item
            selection = item
        } else {
            withAnimation(.snappy(duration: TaisaMotion.fast)) {
                visualSelection = item
            }
            Task { @MainActor in
                await Task.yield()
                guard generation == selectionGeneration else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selection = item
                }
            }
        }
    }
}
