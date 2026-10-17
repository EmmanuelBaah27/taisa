import SwiftUI

public struct InlineRecoveryAlert: View {
    public struct Contract: Sendable, Equatable {
        public let title: String; public let message: String; public let cancelLabel: String; public let retryLabel: String
        public static let usesStableHorizontalActions = true
        public static let actionHeight: CGFloat = 48
        public static let actionSpacing: CGFloat = TaisaSpacing.control.rawValue
        public static let transcription = Contract(
            title: "Recording couldn’t be transcribed",
            message: "Your recording is saved.",
            cancelLabel: "Save for later", retryLabel: "Retry transcription"
        )
        public static let request = Contract(
            title: "Taisa couldn’t respond",
            message: "Your message is saved.",
            cancelLabel: "Continue later", retryLabel: "Retry response"
        )
        public static let beginRecording = Contract(
            title: "Recording didn’t start",
            message: "Nothing was recorded. Try again or use the keyboard.",
            cancelLabel: "Use keyboard", retryLabel: "Try recording again"
        )
        public static let microphonePermission = Contract(
            title: "Microphone access is off",
            message: "Allow microphone access in Settings to record, or continue with the keyboard.",
            cancelLabel: "Use keyboard", retryLabel: "Open Settings"
        )
        public static let pauseRecording = Contract(
            title: "Recording didn’t pause",
            message: "Your recording is still available. Try pausing again or discard it.",
            cancelLabel: "Discard recording", retryLabel: "Pause again"
        )
        public static let resumeRecording = Contract(
            title: "Recording didn’t resume",
            message: "Your recording is still paused. Try again or save it for later.",
            cancelLabel: "Save draft", retryLabel: "Resume again"
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
            CentralIcon(.exclamationCircle)
                .foregroundStyle(TaisaColor.destructive.color)
                .frame(width: 24, height: 24)
            Text(contract.title).font(.system(.body, weight: .medium))
            Text(contract.message).font(.system(.subheadline)).foregroundStyle(TaisaColor.mutedForeground.color)
            HStack(spacing: Contract.actionSpacing) { actions }
        }
        .padding(TaisaSpacing.standard.rawValue)
        .background(TaisaColor.background.color, in: RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue))
        .overlay { RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue).stroke(TaisaColor.border.color) }
    }
    private var actions: some View {
        Group {
            recoveryButton(contract.cancelLabel, action: onCancel)
            recoveryButton(contract.retryLabel, action: onRetry)
        }
    }

    private func recoveryButton(_ label: String, action: @escaping @MainActor () -> Void) -> some View {
        TaisaSecondaryCapsuleButton(action: action) {
            Text(label)
                .font(TaisaTypography.navigationLabel.font)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: Contract.actionHeight)
        }
        .frame(maxWidth: .infinity)
    }
}
