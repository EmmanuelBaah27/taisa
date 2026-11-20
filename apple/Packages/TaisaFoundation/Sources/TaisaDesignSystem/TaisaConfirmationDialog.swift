import SwiftUI

public struct TaisaConfirmationDialog: ViewModifier {
    private let title: String
    @Binding private var isPresented: Bool
    private let confirmLabel: String
    private let cancelLabel: String
    private let role: TaisaSystemActionRole
    private let confirm: @MainActor () -> Void

    public init(title: String, isPresented: Binding<Bool>, confirmLabel: String, cancelLabel: String, role: TaisaSystemActionRole = .confirmation, confirm: @escaping @MainActor () -> Void) {
        self.title = title
        _isPresented = isPresented
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.role = role
        self.confirm = confirm
    }

    public func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented) {
            Button(confirmLabel, role: role == .destructive ? .destructive : nil, action: confirm)
            Button(cancelLabel, role: .cancel) {}
        }
    }
}
