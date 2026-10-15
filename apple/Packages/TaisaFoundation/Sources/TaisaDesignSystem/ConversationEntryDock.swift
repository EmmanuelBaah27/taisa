import SwiftUI

public struct ConversationEntryDock: View {
    public struct Contract: Sendable, Equatable {
        public let voiceAccessibilityLabel: String
        public let keyboardAccessibilityLabel: String
        public static let preview = Contract(
            voiceAccessibilityLabel: "Talk to Taisa, starts recording",
            keyboardAccessibilityLabel: "Talk to Taisa with keyboard"
        )
    }

    private let disabled: Bool
    private let onVoice: @MainActor () -> Void
    private let onKeyboard: @MainActor () -> Void

    public init(disabled: Bool = false, onVoice: @escaping @MainActor () -> Void, onKeyboard: @escaping @MainActor () -> Void) {
        self.disabled = disabled; self.onVoice = onVoice; self.onKeyboard = onKeyboard
    }

    @ViewBuilder public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            voiceButton
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(TaisaColor.primaryAction.color)
                .recordingGlow()
        } else {
            voiceButton
                .buttonStyle(.plain)
                .background(TaisaColor.primaryAction.color, in: Capsule())
                .recordingGlow()
        }
    }

    private var voiceButton: some View {
        Button(action: onVoice) {
            CentralIcon(.voiceMid)
                .foregroundStyle(TaisaColor.foreground.color)
                .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                .frame(
                    width: TaisaControlMetric.recordingButtonWidth,
                    height: TaisaControlMetric.recordingButtonHeight
                )
        }
        .accessibilityLabel(Contract.preview.voiceAccessibilityLabel)
        .disabled(disabled)
    }
}

private extension View {
    func recordingGlow() -> some View {
        compositingGroup()
            .shadow(
                color: TaisaColor.primaryAction.color.opacity(TaisaEffect.recordingGlowOpacity),
                radius: TaisaEffect.recordingGlowBlurRadius,
                x: 0,
                y: 0
            )
            .shadow(
                color: TaisaColor.primaryAction.color.opacity(TaisaEffect.recordingGlowOpacity),
                radius: TaisaEffect.recordingGlowSpread,
                x: 0,
                y: 0
            )
    }
}
