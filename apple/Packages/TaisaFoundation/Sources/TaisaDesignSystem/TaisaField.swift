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

public struct TaisaFieldStyle: Sendable, Equatable {
    public let spacing: CGFloat
    public let titleRole: TaisaTypography
    public let titleColor: TaisaColor
    public let titleLineHeight: CGFloat?
    public let fieldTypography: TaisaTypography
    public let horizontalPadding: CGFloat
    public let minimumHeight: CGFloat?
    public let background: TaisaColor
    public let border: TaisaColor?
    public let multilineMinimumLines: Int
}

public enum TaisaFieldAppearance: Sendable {
    case outlined, profile

    public var style: TaisaFieldStyle {
        switch self {
        case .outlined:
            .init(
                spacing: TaisaSpacing.compact.rawValue,
                titleRole: .label,
                titleColor: .foreground,
                titleLineHeight: nil,
                fieldTypography: .body,
                horizontalPadding: TaisaSpacing.control.rawValue,
                minimumHeight: nil,
                background: .background,
                border: .border,
                multilineMinimumLines: 3
            )
        case .profile:
            .init(
                spacing: TaisaSpacing.tight.rawValue,
                titleRole: .profileSupporting,
                titleColor: .mutedForeground,
                titleLineHeight: TaisaTypography.supporting.lineHeight,
                fieldTypography: .profileBody,
                horizontalPadding: TaisaSpacing.standard.rawValue,
                minimumHeight: TaisaControlMetric.primaryNavigationItemHeight,
                background: .subtleSurface,
                border: nil,
                multilineMinimumLines: 1
            )
        }
    }
}

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
        let style = appearance.style
        VStack(alignment: .leading, spacing: style.spacing) {
            TaisaText(role: style.titleRole, color: style.titleColor, content: title)
                .frame(minHeight: style.titleLineHeight, alignment: .leading)
            field
                .font(style.fieldTypography.font)
                .accessibilityLabel(title)
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, TaisaSpacing.control.rawValue)
                .frame(minHeight: style.minimumHeight)
                .background(style.background.color, in: RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue))
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
                .lineLimit(appearance.style.multilineMinimumLines...8)
        case .text, .readOnly:
            TextField(placeholder, text: $text)
        }
    }

    private var borderColor: Color {
        if case .invalid = state { return TaisaColor.destructive.color }
        return appearance.style.border?.color ?? .clear
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
