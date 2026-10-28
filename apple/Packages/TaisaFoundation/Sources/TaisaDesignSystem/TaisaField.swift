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

public struct TaisaField: View {
    private let title: String
    private let placeholder: String
    private let kind: TaisaFieldKind
    private let state: TaisaFieldState
    @Binding private var text: String

    public init(
        _ title: String,
        text: Binding<String>,
        placeholder: String = "",
        kind: TaisaFieldKind = .text,
        state: TaisaFieldState = .enabled
    ) {
        self.title = title
        _text = text
        self.placeholder = placeholder
        self.kind = kind
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
            TaisaText(role: .label, content: title)
            field
                .font(TaisaTypography.body.font)
                .accessibilityLabel(title)
                .padding(TaisaSpacing.control.rawValue)
                .background(TaisaColor.background.color)
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
                .lineLimit(3...8)
        case .text, .readOnly:
            TextField(placeholder, text: $text)
        }
    }

    private var borderColor: Color {
        if case .invalid = state { return TaisaColor.destructive.color }
        return TaisaColor.border.color
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
