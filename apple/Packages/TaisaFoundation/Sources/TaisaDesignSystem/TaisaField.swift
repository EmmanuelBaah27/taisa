import SwiftUI

public enum TaisaFieldKind: Sendable, Equatable {
    case text
    case secure
    case multiline
    case readOnly
}

public enum TaisaFieldState: Sendable, Equatable {
    case enabled
    case disabled
    case invalid(message: String)
    case loading
}

public enum TaisaFieldAppearance: Sendable { case outlined, profile }

public struct TaisaField: View {
    private let title: String
    private let placeholder: String
    private let kind: TaisaFieldKind
    private let appearance: TaisaFieldAppearance
    private let state: TaisaFieldState
    @Binding private var text: String

    public init(
        _ title: String,
        text: Binding<String>,
        placeholder: String = "",
        kind: TaisaFieldKind = .text,
        state: TaisaFieldState = .enabled,
        appearance: TaisaFieldAppearance = .outlined
    ) {
        self.title = title
        _text = text
        self.placeholder = placeholder
        self.kind = kind
        self.state = state
        self.appearance = appearance
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: appearance == .profile ? TaisaSpacing.tight.rawValue : TaisaSpacing.compact.rawValue) {
            TaisaText(role: appearance == .profile ? .profileSupporting : .label, color: appearance == .profile ? .mutedForeground : .foreground, content: title)
                .frame(minHeight: appearance == .profile ? TaisaTypography.supporting.lineHeight : nil, alignment: .leading)
            field
                .font(appearance == .profile ? TaisaTypography.profileBody.font : TaisaTypography.body.font)
                .accessibilityLabel(title)
                .padding(.horizontal, appearance == .profile ? TaisaSpacing.standard.rawValue : TaisaSpacing.control.rawValue)
                .padding(.vertical, TaisaSpacing.control.rawValue)
                .frame(minHeight: appearance == .profile ? TaisaControlMetric.primaryNavigationItemHeight : nil)
                .background(appearance == .profile ? TaisaColor.subtleSurface.color : TaisaColor.background.color, in: RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue))
                .overlay {
                    RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue)
                        .stroke(borderColor)
                }
            if case let .invalid(message) = state {
                TaisaText(role: .supporting, color: .destructive, content: message)
            }
        }
        .disabled(state == .disabled || state == .loading || kind == .readOnly)
        .opacity(state == .disabled ? TaisaControlMetric.disabledControlOpacity : 1)
    }

    @ViewBuilder private var field: some View {
        switch kind {
        case .secure:
            SecureField(placeholder, text: $text)
        case .multiline:
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit((appearance == .profile ? 1 : 3)...8)
        case .text, .readOnly:
            TextField(placeholder, text: $text)
        }
    }

    private var borderColor: Color {
        if case .invalid = state { return TaisaColor.destructive.color }
        return appearance == .profile ? .clear : TaisaColor.border.color
    }
}

public struct TaisaDateField: View {
    private let title: String
    @Binding private var selection: Date

    public init(_ title: String, selection: Binding<Date>) {
        self.title = title
        _selection = selection
    }

    public var body: some View {
        DatePicker(title, selection: $selection, displayedComponents: .date)
            .font(TaisaTypography.body.font)
            .tint(TaisaColor.foreground.color)
    }
}
