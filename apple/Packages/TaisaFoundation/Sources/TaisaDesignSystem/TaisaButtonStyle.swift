import SwiftUI

/// One native button foundation for the app, previews and every DS button wrapper.
/// Content actions (rows, navigation items and inline links) keep their surrounding
/// surface; standalone and floating actions use the same native glass treatment.
public struct TaisaButtonStyle: PrimitiveButtonStyle {
    public enum Presentation: Sendable { case surface, content }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let role: TaisaButtonRole
    let shape: TaisaButtonShape
    let presentation: Presentation
    let size: TaisaButtonSize

    public init(
        role: TaisaButtonRole = .secondary,
        shape: TaisaButtonShape = .capsule,
        presentation: Presentation = .surface,
        size: TaisaButtonSize = .standard
    ) {
        self.role = role
        self.shape = shape
        self.presentation = presentation
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        styledButton(configuration)
            .buttonBorderShape(borderShape)
            .contentShape(buttonShape)
            .font(TaisaTypography.buttonLabel.font)
    }

    @ViewBuilder private func styledButton(_ configuration: Configuration) -> some View {
        let button = Button(configuration)
        let destructive = role == .destructive || configuration.role == .destructive
        if presentation == .content || role == .ghost {
            button.buttonStyle(.plain)
        } else if role == .primary {
            if #available(iOS 26.0, macOS 26.0, *), !reduceTransparency {
                button
                    .buttonStyle(.glassProminent)
                    .tint(TaisaColor.primaryAction.color)
                    .foregroundStyle(TaisaColor.foreground.color)
            } else {
                button
                    .buttonStyle(.plain)
                    .foregroundStyle(TaisaColor.foreground.color)
                    .background(TaisaColor.primaryAction.color, in: buttonShape)
            }
        } else if #available(iOS 26.0, macOS 26.0, *), !reduceTransparency {
            if destructive {
                button
                    .controlSize(size.controlSize)
                    .buttonStyle(.plain)
                    .foregroundStyle(TaisaColor.destructive.color)
                    .glassEffect(.regular.interactive(), in: buttonShape)
            } else {
                button
                    .controlSize(size.controlSize)
                    .buttonStyle(.plain)
                    .foregroundStyle(TaisaColor.foreground.color)
                    .glassEffect(.clear.interactive(), in: buttonShape)
            }
        } else if reduceTransparency {
            button
                .buttonStyle(.plain)
                .foregroundStyle(destructive ? TaisaColor.destructive.color : TaisaColor.foreground.color)
                .background(TaisaColor.raisedSurface.color, in: buttonShape)
        } else {
            button
                .buttonStyle(.plain)
                .foregroundStyle(destructive ? TaisaColor.destructive.color : TaisaColor.foreground.color)
                .background(.regularMaterial, in: buttonShape)
        }
    }

    private var borderShape: ButtonBorderShape {
        switch shape {
        case .capsule: .capsule
        case .circle: .circle
        case .roundedRectangle: .roundedRectangle(radius: TaisaRadius.control.rawValue)
        }
    }

    private var buttonShape: AnyShape {
        switch shape {
        case .capsule: AnyShape(Capsule())
        case .circle: AnyShape(Circle())
        case .roundedRectangle: AnyShape(RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue))
        }
    }
}
