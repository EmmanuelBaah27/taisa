import SwiftUI

public enum TaisaButtonRole: Sendable, Equatable {
    case primary
    case secondary
    case destructive
}

public enum TaisaButtonShape: Sendable, Equatable {
    case roundedRectangle
    case capsule
    case circle
}

public struct TaisaButton: View {
    public enum Contract {
        public static let supportsInPlaceProgress = true
    }

    private let role: TaisaButtonRole
    private let shape: TaisaButtonShape
    private let label: String
    private let isProcessing: Bool
    private let processingAccessibilityLabel: String
    private let action: @MainActor () -> Void

    public init(
        role: TaisaButtonRole,
        shape: TaisaButtonShape = .capsule,
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
        TaisaButtonControl(style: TaisaButtonStyle(role: role, shape: shape), action: action) {
            buttonSurface
        }
        .disabled(isProcessing)
        .accessibilityLabel(isProcessing ? processingAccessibilityLabel : label)
    }

    private var buttonSurface: some View {
        ZStack {
            TaisaText(role: .label, color: labelColor, content: label)
                .opacity(isProcessing ? 0 : 1)
            if isProcessing {
                ProgressView()
                    .tint(TaisaColor.foreground.color)
            }
        }
        .frame(maxWidth: .infinity, minHeight: TaisaControlMetric.actionButtonHeight)
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
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
