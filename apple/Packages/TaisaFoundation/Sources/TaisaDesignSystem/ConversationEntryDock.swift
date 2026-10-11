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
        HStack(spacing: TaisaSpacing.compact.rawValue) {
            Button(action: onVoice) { Label("Talk to Taisa", systemImage: "waveform") }
                .buttonStyle(.borderedProminent).tint(TaisaColor.primaryAction.color)
                .accessibilityLabel(Contract.preview.voiceAccessibilityLabel)
            Button(action: onKeyboard) { Image(systemName: "keyboard") }
                .buttonStyle(.bordered).accessibilityLabel(Contract.preview.keyboardAccessibilityLabel)
        }
        .padding(TaisaSpacing.compact.rawValue)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: TaisaRadius.composer.rawValue))
        .disabled(disabled)
    }
}
