import SwiftUI

public struct TaisaMenu: View {
    private let label: String
    private let actions: [(String, TaisaSystemActionRole, () -> Void)]

    public init(label: String, actions: [(String, TaisaSystemActionRole, () -> Void)]) {
        self.label = label
        self.actions = actions
    }

    public var body: some View {
        Menu(label) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                TaisaSystemButton(item.0, role: item.1 == .destructive ? .destructive : nil, action: { item.2() })
            }
        }
        .tint(TaisaColor.foreground.color)
    }
}
