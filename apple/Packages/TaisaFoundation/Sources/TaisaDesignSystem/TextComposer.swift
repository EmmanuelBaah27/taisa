import SwiftUI

public struct TextComposer: View {
    public struct Contract: Sendable, Equatable {
        public let voiceLabel: String
        public static let empty = Contract(voiceLabel: "Reply by voice, starts recording")
    }
    @Binding var text: String
    let onSend: @MainActor () -> Void
    let onVoice: @MainActor () -> Void
    public init(text: Binding<String>, onSend: @escaping @MainActor () -> Void, onVoice: @escaping @MainActor () -> Void) {
        _text = text; self.onSend = onSend; self.onVoice = onVoice
    }
    public var body: some View {
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(alignment: .bottom) {
            TextField("Message Taisa", text: $text, axis: .vertical).lineLimit(1...6)
            Button(action: { isEmpty ? onVoice() : onSend() }) {
                Image(systemName: isEmpty ? "waveform" : "arrow.up")
            }
            .accessibilityLabel(isEmpty ? Contract.empty.voiceLabel : "Send message")
        }
        .padding(TaisaSpacing.standard.rawValue)
        .background(TaisaColor.raisedSurface.color, in: RoundedRectangle(cornerRadius: TaisaRadius.composer.rawValue))
    }
}
