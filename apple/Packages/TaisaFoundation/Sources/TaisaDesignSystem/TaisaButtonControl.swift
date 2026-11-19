import SwiftUI

/// The only action-control constructor used by DS button components.
/// Keep action, native role and label intact; the shared style owns rendering.
public struct TaisaButtonControl<Label: View>: View {
    private let role: ButtonRole?
    private let action: @MainActor () -> Void
    private let label: Label
    private let style: TaisaButtonStyle

    public init(
        role: ButtonRole? = nil,
        style: TaisaButtonStyle = TaisaButtonStyle(),
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.style = style
        self.action = action
        self.label = label()
    }

    public var body: some View {
        Button(role: role, action: action) { label }
            .buttonStyle(style)
    }
}

extension TaisaButtonControl where Label == TaisaText {
    public init(
        _ title: String,
        role: ButtonRole? = nil,
        style: TaisaButtonStyle = TaisaButtonStyle(),
        textRole: TaisaTypography = .label,
        textColor: TaisaColor? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.init(role: role, style: style, action: action) {
            TaisaText(role: textRole, color: textColor ?? (role == .destructive ? .destructive : .foreground), content: title)
        }
    }
}

/// Menus and confirmation dialogs must receive a native Button value so SwiftUI
/// can extract its title and cancel/destructive role. Rendering belongs to that
/// system presentation; ordinary app buttons use TaisaButtonControl instead.
public func TaisaSystemButton(
    _ title: String,
    role: ButtonRole? = nil,
    action: @escaping @MainActor () -> Void
) -> Button<Text> {
    Button(title, role: role, action: action)
}
