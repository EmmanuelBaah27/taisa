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

public struct TaisaButton: View {
    public enum Contract {
        public static let supportsInPlaceProgress = true
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let role: TaisaButtonRole
    private let shape: TaisaButtonShape
    private let label: String
    private let isProcessing: Bool
    private let processingAccessibilityLabel: String
    private let action: @MainActor () -> Void

    public init(
        role: TaisaButtonRole,
        shape: TaisaButtonShape = .roundedRectangle,
        label: String,
        isProcessing: Bool = false,
        processingAccessibilityLabel: String = "Working",
        action: @escaping @MainActor () -> Void
    ) {
        self.role = role
        self.shape = shape
        self.label = label
        self.isProcessing = isProcessing
        self.processingAccessibilityLabel = processingAccessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            buttonSurface
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel(isProcessing ? processingAccessibilityLabel : label)
    }

    @ViewBuilder private var buttonSurface: some View {
        let content = ZStack {
            TaisaText(role: .label, color: labelColor, content: label)
                .opacity(isProcessing ? 0 : 1)
            if isProcessing {
                ProgressView()
                    .tint(TaisaColor.foreground.color)
            }
        }
        .frame(maxWidth: .infinity, minHeight: TaisaControlMetric.actionButtonHeight)
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .contentShape(buttonShape)

        if #available(iOS 26.0, macOS 26.0, *), !reduceTransparency {
            switch role {
            case .primary:
                content.glassEffect(.clear.tint(TaisaColor.primaryAction.color).interactive(), in: buttonShape)
            case .secondary, .destructive:
                content.glassEffect(.clear.interactive(), in: buttonShape)
            }
        } else {
            content.background(fallbackColor, in: buttonShape)
        }
    }

    private var buttonShape: AnyShape {
        switch shape {
        case .roundedRectangle: AnyShape(RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue))
        case .capsule: AnyShape(Capsule())
        }
    }

    private var fallbackColor: Color {
        role == .primary ? TaisaColor.primaryAction.color : TaisaColor.raisedSurface.color
    }

    private var labelColor: TaisaColor {
        role == .destructive ? .destructive : .foreground
    }
}

#Preview("Buttons") {
    VStack(spacing: TaisaSpacing.standard.rawValue) {
        TaisaButton(role: .primary, label: "Continue") {}
        TaisaButton(role: .secondary, label: "Build diagnostics") {}
    }
    .padding()
}
