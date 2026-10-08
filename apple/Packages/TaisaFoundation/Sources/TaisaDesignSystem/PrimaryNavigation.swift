import SwiftUI

public struct PrimaryNavigation<Item: Hashable>: View {
    public let items: [(Item, String, String)]
    @Binding private var selection: Item

    public init(items: [(Item, String, String)], selection: Binding<Item>) {
        self.items = items; _selection = selection
    }

    public var body: some View {
        HStack {
            ForEach(items, id: \.0) { item, label, symbol in
                Button { selection = item } label: {
                    Label(label, systemImage: symbol).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain).accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(TaisaSpacing.compact.rawValue)
        .background(.regularMaterial, in: Capsule())
    }
}
