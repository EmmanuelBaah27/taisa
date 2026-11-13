import SwiftUI

public enum TaisaSystemActionRole: Sendable, Equatable {
    case standard
    case destructive
    case cancel
    case confirmation
}

public struct TaisaPicker<Option: Hashable>: View {
    private let title: String
    private let options: [Option]
    private let label: (Option) -> String
    @Binding private var selection: Option

    public init(_ title: String, selection: Binding<Option>, options: [Option], label: @escaping (Option) -> String) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    public var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in Text(label(option)).tag(option) }
        }
        .tint(TaisaColor.foreground.color)
    }
}

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
                Button(item.0, role: item.1 == .destructive ? .destructive : nil, action: item.2)
            }
        }
        .tint(TaisaColor.foreground.color)
    }
}

public struct TaisaNavigationRow: View {
    private let label: String
    private let icon: CentralIconName?

    public init(label: String, icon: CentralIconName? = nil) {
        self.label = label
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: TaisaSpacing.control.rawValue) {
            if let icon { CentralIcon(icon).frame(width: 24, height: 24) }
            TaisaText(role: .body, content: label)
            Spacer()
            CentralIcon(.chevronLeft).rotationEffect(.degrees(180)).frame(width: 20, height: 20)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

public struct TaisaToolbarAction: View {
    private let label: String
    private let icon: CentralIconName
    private let action: () -> Void

    public init(label: String, icon: CentralIconName, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) { CentralIcon(icon).frame(width: 24, height: 24) }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(label)
    }
}

public struct TaisaConfirmationDialog: ViewModifier {
    private let title: String
    @Binding private var isPresented: Bool
    private let confirmLabel: String
    private let cancelLabel: String
    private let role: TaisaSystemActionRole
    private let confirm: () -> Void

    public init(title: String, isPresented: Binding<Bool>, confirmLabel: String, cancelLabel: String, role: TaisaSystemActionRole = .confirmation, confirm: @escaping () -> Void) {
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
