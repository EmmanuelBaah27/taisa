import SwiftUI

public enum TaisaInlineActionStyle: Sendable, Equatable {
    case standard
    case muted
    case accent
    case destructive

    public func foregroundColor(isSelected: Bool) -> TaisaColor {
        switch self {
        case .standard: .foreground
        case .muted: isSelected ? .mutedForeground : .inactiveForeground
        case .accent: .primaryAction
        case .destructive: .destructive
        }
    }
}

public enum TaisaInlineActionIconPlacement: Sendable, Equatable {
    case leading
    case trailing
}

public enum TaisaInlineActionLayout: Sendable, Equatable {
    case intrinsic
    case fullRow
}

public enum TaisaInlineActionContract {
    public static let minimumHitHeight = TaisaButtonSize.small.minimumHitHeight
    public static let horizontalContentPadding: CGFloat = 0
    public static let hasVisibleContainer = false
}

/// A content-aligned action with a full mobile tap target and no visible button surface.
public struct TaisaInlineAction: View {
    private let label: String
    private let icon: CentralIconName?
    private let iconPlacement: TaisaInlineActionIconPlacement
    private let style: TaisaInlineActionStyle
    private let textRole: TaisaTypography
    private let layout: TaisaInlineActionLayout
    private let isSelected: Bool
    private let isEnabled: Bool
    private let isProcessing: Bool
    private let accessibilityLabel: String
    private let action: @MainActor () -> Void

    public init(
        label: String,
        icon: CentralIconName? = nil,
        iconPlacement: TaisaInlineActionIconPlacement = .leading,
        style: TaisaInlineActionStyle = .standard,
        textRole: TaisaTypography = .body,
        layout: TaisaInlineActionLayout = .intrinsic,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        isProcessing: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.iconPlacement = iconPlacement
        self.style = style
        self.textRole = textRole
        self.layout = layout
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isProcessing = isProcessing
        self.accessibilityLabel = accessibilityLabel ?? label
        self.action = action
    }

    public var body: some View {
        TaisaPressable(role: style == .destructive ? .destructive : nil, action: action) {
            HStack(spacing: TaisaSpacing.compact.rawValue) {
                if isProcessing {
                    ProgressView()
                        .tint(foregroundColor.color)
                } else {
                    if iconPlacement == .leading { actionIcon }
                    TaisaText(role: textRole, color: foregroundColor, content: label)
                    if iconPlacement == .trailing { actionIcon }
                }
            }
            .frame(
                maxWidth: layout == .fullRow ? .infinity : nil,
                minHeight: TaisaInlineActionContract.minimumHitHeight,
                alignment: .leading
            )
        }
        .disabled(!isEnabled || isProcessing)
        .opacity(isEnabled ? 1 : TaisaControlMetric.disabledControlOpacity)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var actionIcon: some View {
        if let icon {
            CentralIcon(icon, color: foregroundColor)
                .frame(width: TaisaControlMetric.compactActionIcon, height: TaisaControlMetric.compactActionIcon)
        }
    }

    private var foregroundColor: TaisaColor {
        style.foregroundColor(isSelected: isSelected)
    }
}
