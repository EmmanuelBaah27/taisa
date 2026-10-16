import SwiftUI

public enum TaisaButtonRole: Sendable {
    case primary
    case secondary
}

public enum TaisaButtonShape: Sendable, Equatable {
    case roundedRectangle
    case capsule
}

public struct TaisaButton: View {
    private let role: TaisaButtonRole
    private let shape: TaisaButtonShape
    private let label: String
    private let action: @MainActor () -> Void

    public init(
        role: TaisaButtonRole,
        shape: TaisaButtonShape = .roundedRectangle,
        label: String,
        action: @escaping @MainActor () -> Void
    ) {
        self.role = role
        self.shape = shape
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TaisaText(role: .label, color: .foreground, content: label)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, TaisaSpacing.standard.rawValue)
                .background(background, in: buttonShape)
                .overlay { buttonShape.stroke(TaisaColor.border.color, lineWidth: role == .secondary ? 1 : 0) }
                .clipShape(buttonShape)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var buttonShape: AnyShape {
        switch shape {
        case .roundedRectangle: AnyShape(RoundedRectangle(cornerRadius: 12))
        case .capsule: AnyShape(Capsule())
        }
    }

    private var background: Color {
        switch role {
        case .primary:
            TaisaColor.primaryAction.color
        case .secondary:
            TaisaColor.background.color
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
