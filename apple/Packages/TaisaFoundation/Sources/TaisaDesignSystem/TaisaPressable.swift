import SwiftUI

/// The single shared boundary for custom-content SwiftUI button interactions.
struct TaisaPressable<Label: View>: View {
    private let role: ButtonRole?
    private let action: @MainActor @Sendable () -> Void
    private let label: Label

    init(
        role: ButtonRole? = nil,
        action: @escaping @MainActor @Sendable () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(role: role, action: action) {
            label
        }
    }
}
