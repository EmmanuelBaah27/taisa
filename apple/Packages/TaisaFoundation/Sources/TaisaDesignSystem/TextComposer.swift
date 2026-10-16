import SwiftUI

public struct TextComposer: View {
    public struct Contract: Sendable, Equatable {
        public let voiceLabel: String
        public let placeholder: String
        public static let empty = Contract(voiceLabel: "Reply by voice, starts recording", placeholder: "Reply")
        public static let usesLiquidEditorSurface = true
        public static let minimumHeight: CGFloat = 48
        public static let focusesOnEntry = true
    }
    public enum Mode: Sendable { case composing, processing
        public var acceptsInput: Bool { self == .composing }
    }
    @Binding var text: String
    let onSend: @MainActor () -> Void
    let onVoice: @MainActor () -> Void
    let mode: Mode
    @FocusState private var isFocused: Bool
    public init(text: Binding<String>, mode: Mode = .composing, onSend: @escaping @MainActor () -> Void, onVoice: @escaping @MainActor () -> Void) {
        _text = text; self.mode = mode; self.onSend = onSend; self.onVoice = onVoice
    }
    public var body: some View {
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(alignment: .bottom, spacing: TaisaSpacing.compact.rawValue) {
            TextField(Contract.empty.placeholder, text: $text, axis: .vertical)
                .lineLimit(1...6)
                .disabled(!mode.acceptsInput)
                .focused($isFocused)
            Button(action: { isEmpty ? onVoice() : onSend() }) {
                Image(systemName: isEmpty ? "waveform" : "arrow.up")
                    .frame(width: 20, height: 20)
                    .frame(width: 40, height: 40)
                    .background(TaisaColor.primaryAction.color, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isEmpty ? Contract.empty.voiceLabel : "Send message")
            .disabled(!mode.acceptsInput)
        }
        .padding(.leading, TaisaSpacing.standard.rawValue)
        .padding(.trailing, TaisaSpacing.tight.rawValue)
        .padding(.vertical, TaisaSpacing.tight.rawValue)
        .frame(minHeight: Contract.minimumHeight)
        .modifier(LiquidTextInputSurface(cornerRadius: TaisaRadius.composer.rawValue))
        .onAppear { isFocused = mode.acceptsInput }
    }
}

public struct LiquidTextInputSurface: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) { self.cornerRadius = cornerRadius }

    @ViewBuilder public func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(TaisaColor.border.color)
                }
        }
    }
}
