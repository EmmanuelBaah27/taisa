import SwiftUI

public struct TextComposer: View {
    public struct Contract: Sendable, Equatable {
        public let voiceLabel: String
        public let placeholder: String
        public static let empty = Contract(voiceLabel: "Reply by voice, starts recording", placeholder: "Reply")
    }
    public enum Mode: Sendable { case composing, processing
        public var acceptsInput: Bool { self == .composing }
    }
    @Binding var text: String
    let onSend: @MainActor () -> Void
    let onVoice: @MainActor () -> Void
    let mode: Mode
    public init(text: Binding<String>, mode: Mode = .composing, onSend: @escaping @MainActor () -> Void, onVoice: @escaping @MainActor () -> Void) {
        _text = text; self.mode = mode; self.onSend = onSend; self.onVoice = onVoice
    }
    public var body: some View {
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(alignment: .bottom) {
            TextField(Contract.empty.placeholder, text: $text, axis: .vertical).lineLimit(1...6).disabled(!mode.acceptsInput)
            Button(action: { isEmpty ? onVoice() : onSend() }) {
                Image(systemName: isEmpty ? "waveform" : "arrow.up")
            }
            .accessibilityLabel(isEmpty ? Contract.empty.voiceLabel : "Send message")
            .disabled(!mode.acceptsInput)
        }
        .padding(TaisaSpacing.standard.rawValue)
        .background(TaisaColor.raisedSurface.color, in: RoundedRectangle(cornerRadius: TaisaRadius.composer.rawValue))
    }
}
