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

/// The internal custom-content entry point for shared interactive controls.
struct TaisaButtonControl<Label: View>: View {
    enum Contract {
        static var supportsCustomContent: Bool { true }
    }

    private let action: @MainActor () -> Void
    private let label: Label

    init(
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
    }
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
        TaisaButtonControl(action: action) {
            ZStack {
                TaisaText(role: .label, color: labelColor, content: label)
                    .opacity(isProcessing ? 0 : 1)
                if isProcessing {
                    ProgressView()
                        .tint(TaisaColor.foreground.color)
                }
            }
                .frame(maxWidth: .infinity, minHeight: TaisaControlMetric.headerActionHeight)
                .padding(.horizontal, TaisaSpacing.standard.rawValue)
                .background(background, in: buttonShape)
                .overlay { buttonShape.stroke(borderColor) }
                .clipShape(buttonShape)
                .contentShape(Rectangle())
        }
        .disabled(isProcessing)
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
            TaisaColor.background.color
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
