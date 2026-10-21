import SwiftUI

public struct ResponseActionIconButton: View {
    public enum Contract {
        public static let iconSize: CGFloat = 16
        public static let visualWidth = TaisaSpacing.section.rawValue
        public static let minimumHitHeight = TaisaControlMetric.headerActionHeight
    }

    private let icon: CentralIconName
    private let accessibilityLabel: String
    private let isSelected: Bool
    private let action: @MainActor () -> Void

    public init(
        icon: CentralIconName,
        accessibilityLabel: String,
        isSelected: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            CentralIcon(icon)
                .frame(width: Contract.iconSize, height: Contract.iconSize)
                .frame(width: Contract.visualWidth)
                .frame(minHeight: Contract.minimumHitHeight)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? TaisaColor.foreground.color : TaisaColor.mutedForeground.color)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

public struct SelectableChip: View {
    public enum Contract {
        public static let minimumHeight = TaisaControlMetric.headerActionHeight
    }

    private let label: String
    private let isSelected: Bool
    private let action: @MainActor () -> Void

    public init(label: String, isSelected: Bool, action: @escaping @MainActor () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TaisaText(role: .label, content: label)
                .padding(.horizontal, TaisaSpacing.control.rawValue)
                .frame(minHeight: Contract.minimumHeight)
                .background(
                    isSelected ? TaisaColor.raisedSurface.color : TaisaColor.background.color,
                    in: Capsule()
                )
                .overlay { Capsule().stroke(TaisaColor.border.color) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

public struct FeedbackTextEditor: View {
    public enum Contract {
        public static let minimumHeight: CGFloat = 112
    }

    @Binding private var text: String
    private let accessibilityLabel: String

    public init(text: Binding<String>, accessibilityLabel: String) {
        _text = text
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        TextEditor(text: $text)
            .font(TaisaTypography.body.font)
            .frame(minHeight: Contract.minimumHeight)
            .padding(TaisaSpacing.compact.rawValue)
            .modifier(LiquidTextInputSurface(cornerRadius: TaisaRadius.control.rawValue))
            .accessibilityLabel(accessibilityLabel)
    }
}

public enum ActionPanelContract {
    public static let usesRaisedSurface = true
}

public struct ActionPanel<Content: View>: View {

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(TaisaSpacing.control.rawValue)
            .background(
                TaisaColor.raisedSurface.color,
                in: RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue)
            )
    }
}
