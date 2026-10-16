import SwiftUI

public struct InlineRecoveryAlert: View {
    public struct Contract: Sendable, Equatable {
        public let title: String; public let message: String; public let cancelLabel: String; public let retryLabel: String
        public static let transcription = Contract(
            title: "Taisa couldn’t transcribe your recording",
            message: "Your recording is safe. Try again when you’re ready.",
            cancelLabel: "Cancel", retryLabel: "Try again"
        )
        public static let request = Contract(
            title: "Taisa couldn’t finish this response",
            message: "Nothing has been discarded. Try again when you’re ready.",
            cancelLabel: "Cancel", retryLabel: "Try again"
        )
        public static let beginRecording = Contract(
            title: "Taisa couldn’t start recording",
            message: "Check microphone access, then try again.",
            cancelLabel: "Close", retryLabel: "Try again"
        )
        public static let pauseRecording = Contract(
            title: "Taisa couldn’t pause recording",
            message: "Your recording is still safe. Try pausing again.",
            cancelLabel: "Close", retryLabel: "Try again"
        )
        public static let resumeRecording = Contract(
            title: "Taisa couldn’t resume recording",
            message: "Your recording is still safe. Try resuming again.",
            cancelLabel: "Close", retryLabel: "Try again"
        )
    }
    private let contract: Contract
    private let onCancel: @MainActor () -> Void
    private let onRetry: @MainActor () -> Void
    public init(contract: Contract = .transcription, onCancel: @escaping @MainActor () -> Void, onRetry: @escaping @MainActor () -> Void) {
        self.contract = contract; self.onCancel = onCancel; self.onRetry = onRetry
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.control.rawValue) {
            CentralIcon(.exclamationCircle).frame(width: 24, height: 24)
            Text(contract.title).font(.system(.body, weight: .medium))
            Text(contract.message).font(.system(.subheadline)).foregroundStyle(TaisaColor.mutedForeground.color)
            ViewThatFits(in: .horizontal) {
                HStack { Spacer(); actions }
                VStack(alignment: .trailing) { actions }
            }
        }
        .padding(TaisaSpacing.standard.rawValue)
        .background(TaisaColor.background.color, in: RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue))
        .overlay { RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue).stroke(TaisaColor.border.color) }
    }
    private var actions: some View {
        Group {
            TaisaSecondaryCapsuleButton(action: onCancel) { Text(contract.cancelLabel).padding(.horizontal, TaisaSpacing.standard.rawValue) }
            TaisaSecondaryCapsuleButton(action: onRetry) { Text(contract.retryLabel).padding(.horizontal, TaisaSpacing.standard.rawValue) }
        }
    }
}
