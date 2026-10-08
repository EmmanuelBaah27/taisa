import SwiftUI

public struct VoiceComposerControls: View {
    public enum Phase: Sendable { case preparing, recording, paused, waitingForReply }
    public struct Contract: Sendable, Equatable {
        public let pauseLabel: String
        public let resumeLabel: String
        public static let recording = Contract(pauseLabel: "Pause recording", resumeLabel: "Resume recording")
        public static let paused = Contract(pauseLabel: "Pause recording", resumeLabel: "Resume recording")
    }
    let phase: Phase
    let onPrimary: @MainActor () -> Void
    let onSend: @MainActor () -> Void
    public init(phase: Phase, onPrimary: @escaping @MainActor () -> Void, onSend: @escaping @MainActor () -> Void) {
        self.phase = phase; self.onPrimary = onPrimary; self.onSend = onSend
    }
    public var body: some View {
        HStack {
            Button(primaryLabel, action: onPrimary).accessibilityLabel(primaryLabel)
            Spacer()
            if phase != .waitingForReply { Button("Send", action: onSend) }
        }
        .frame(minHeight: 56).padding(.horizontal, TaisaSpacing.standard.rawValue)
        .background(TaisaColor.raisedSurface.color, in: RoundedRectangle(cornerRadius: TaisaRadius.composer.rawValue))
    }
    private var primaryLabel: String {
        switch phase { case .preparing: "Preparing microphone"; case .recording: Contract.recording.pauseLabel; case .paused: Contract.paused.resumeLabel; case .waitingForReply: "Reply by voice, starts recording" }
    }
}
