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

    public var body: some View {
        Button(action: onVoice) {
            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(TaisaColor.foreground.color)
                .frame(width: 104, height: 56)
                .background(TaisaColor.primaryAction.color, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Contract.preview.voiceAccessibilityLabel)
        .disabled(disabled)
    }
}
