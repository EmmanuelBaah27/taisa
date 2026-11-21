import SwiftUI

public enum TaisaButtonRole: Sendable, Equatable {
    case primary
    case secondary
    case destructive
}

public enum TaisaButtonShape: Sendable, Equatable {
    case roundedRectangle
    case capsule
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
}

public struct TaisaButton: View {
    public enum Contract {
        public static let supportsLabelContent = true
        public static let supportsIconContent = true
        public static let supportsIconAndLabelContent = true
        public static let supportsDisabledState = true
        public static let supportsSelectedState = true
        public static let supportsInPlaceProgress = true
    }

    private let role: TaisaButtonRole
    private let shape: TaisaButtonShape
    private let label: String
    private let icon: CentralIconName?
    private let size: TaisaButtonSize
    private let isSelected: Bool
    private let isEnabled: Bool
    private let isProcessing: Bool
    private let processingAccessibilityLabel: String
    private let action: @MainActor () -> Void

    public init(
        role: TaisaButtonRole,
        shape: TaisaButtonShape = .roundedRectangle,
        label: String,
        icon: CentralIconName? = nil,
        size: TaisaButtonSize = .standard,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        isProcessing: Bool = false,
        processingAccessibilityLabel: String = "Working",
        action: @escaping @MainActor () -> Void
    ) {
        self.role = role
        self.shape = shape
        self.label = label
        self.icon = icon
        self.size = size
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isProcessing = isProcessing
        self.processingAccessibilityLabel = processingAccessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: TaisaSpacing.compact.rawValue) {
                    if let icon {
                        CentralIcon(icon)
                            .frame(width: size.iconSize, height: size.iconSize)
                    }
                    if !label.isEmpty {
                        TaisaText(role: .label, color: labelColor, content: label)
                    }
                }
                    .opacity(isProcessing ? 0 : 1)
                if isProcessing {
                    ProgressView()
                        .tint(TaisaColor.foreground.color)
                }
            }
                .frame(maxWidth: .infinity, minHeight: size.minimumHeight)
                .padding(.horizontal, TaisaSpacing.standard.rawValue)
                .background(background, in: buttonShape)
                .overlay { buttonShape.stroke(borderColor) }
                .clipShape(buttonShape)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing || !isEnabled)
        .opacity(isEnabled ? 1 : TaisaControlMetric.disabledControlOpacity)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(isProcessing ? processingAccessibilityLabel : label)
    }

    private var buttonShape: AnyShape {
        switch shape {
        case .roundedRectangle: AnyShape(RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue))
        case .capsule: AnyShape(Capsule())
        }
    }

    private var background: Color {
        switch role {
        case .primary:
            TaisaColor.primaryAction.color
        case .secondary, .destructive:
            isSelected ? TaisaColor.selectedSurface.color : TaisaColor.background.color
        }
    }

    private var labelColor: TaisaColor {
        role == .destructive ? .destructive : .foreground
    }

    private var borderColor: Color {
        switch role {
        case .primary: .clear
        case .secondary: TaisaColor.border.color
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
