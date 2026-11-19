import SwiftUI

public enum TaisaButtonRole: Sendable, Equatable {
    case primary
    case secondary
    case ghost
    case destructive

    public var labelTypography: TaisaTypography {
        .buttonLabel
    }
}

public enum TaisaButtonShape: Sendable, Equatable {
    case roundedRectangle
    case capsule
    case circle
}

public enum TaisaButtonLayout: Sendable, Equatable {
    case fill
    case intrinsic
}

public enum TaisaButtonSize: Sendable, Equatable {
    case standard
    case small

    public var minimumHeight: CGFloat {
        self == .standard ? TaisaControlMetric.actionButtonHeight : TaisaControlMetric.compactActionButtonHeight
    }
    public var iconSize: CGFloat {
        self == .standard ? TaisaControlMetric.standardIcon : TaisaControlMetric.compactActionIcon
    }
    public var minimumHitHeight: CGFloat {
        max(minimumHeight, TaisaControlMetric.headerActionHeight)
    }
}

public struct TaisaButton: View {
    public enum Contract {
        public static let supportsLabelContent = true
        public static let supportsIconContent = true
        public static let supportsIconAndLabelContent = true
        public static let supportsDisabledState = true
        public static let supportsSelectedState = true
        public static let supportsInPlaceProgress = true
        public static let supportsIntrinsicLayout = true
        public static let supportsIconOnlyContent = true
        public static let supportsGhostRole = true
        public static let supportsSemanticIconColor = true
    }

    private let role: TaisaButtonRole
    private let shape: TaisaButtonShape
    private let label: String
    private let icon: CentralIconName?
    private let iconColor: TaisaColor?
    private let size: TaisaButtonSize
    private let layout: TaisaButtonLayout
    private let isSelected: Bool
    private let isEnabled: Bool
    private let isProcessing: Bool
    private let processingAccessibilityLabel: String
    private let accessibilityLabel: String
    private let action: @MainActor () -> Void

    public init(
        role: TaisaButtonRole,
        shape: TaisaButtonShape = .roundedRectangle,
        label: String,
        icon: CentralIconName? = nil,
        iconColor: TaisaColor? = nil,
        size: TaisaButtonSize = .standard,
        layout: TaisaButtonLayout = .fill,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        isProcessing: Bool = false,
        processingAccessibilityLabel: String = "Working",
        accessibilityLabel: String? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.role = role
        self.shape = shape
        self.label = label
        self.icon = icon
        self.iconColor = iconColor
        self.size = size
        self.layout = layout
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isProcessing = isProcessing
        self.processingAccessibilityLabel = processingAccessibilityLabel
        self.accessibilityLabel = accessibilityLabel ?? label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: TaisaSpacing.compact.rawValue) {
                    if let icon {
                        CentralIcon(icon)
                            .foregroundStyle((iconColor ?? labelColor).color)
                            .frame(width: size.iconSize, height: size.iconSize)
                    }
                    if !label.isEmpty {
                        TaisaText(role: role.labelTypography, color: labelColor, content: label)
                    }
                }
                    .opacity(isProcessing ? 0 : 1)
                if isProcessing {
                    ProgressView()
                        .tint(TaisaColor.foreground.color)
                }
            }
                .frame(
                    minWidth: shape == .circle ? size.minimumHeight : nil,
                    maxWidth: layout == .fill ? .infinity : nil,
                    minHeight: size.minimumHeight
                )
                .padding(.horizontal, shape == .circle ? 0 : TaisaSpacing.standard.rawValue)
                .background(background, in: buttonShape)
                .overlay { buttonShape.stroke(borderColor) }
                .clipShape(buttonShape)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: layout == .intrinsic, vertical: false)
        .frame(minWidth: size.minimumHitHeight, minHeight: size.minimumHitHeight)
        .contentShape(Rectangle())
        .disabled(isProcessing || !isEnabled)
        .opacity(isEnabled ? 1 : TaisaControlMetric.disabledControlOpacity)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(isProcessing ? processingAccessibilityLabel : accessibilityLabel)
    }

    private var buttonShape: AnyShape {
        switch shape {
        case .roundedRectangle: AnyShape(RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue))
        case .capsule: AnyShape(Capsule())
        case .circle: AnyShape(Circle())
        }
    }

    private var background: Color {
        switch role {
        case .primary:
            TaisaColor.primaryAction.color
        case .secondary, .ghost, .destructive:
            if isSelected { TaisaColor.primaryAction.color }
            else if role == .ghost { Color.clear }
            else { TaisaColor.background.color }
        }
    }

    private var labelColor: TaisaColor {
        role == .destructive ? .destructive : .foreground
    }

    private var borderColor: Color {
        switch role {
        case .primary: .clear
        case .secondary: isSelected ? .clear : TaisaColor.border.color
        case .ghost: .clear
        case .destructive: TaisaColor.destructive.color
        }
    }
}

#Preview("Buttons") {
    VStack(spacing: TaisaSpacing.standard.rawValue) {
        TaisaButton(role: .primary, label: "Continue") {}
        TaisaButton(role: .secondary, label: "Build diagnostics") {}
    }
    .padding()
}
