import SwiftUI

public struct ConversationActionBar: View {
    public enum Phase: Sendable { case preparing, recording, shortCapture, sendable, pausedEmpty, pausedShort, paused, saved, waitingForReply }
    public struct Availability: Sendable, Equatable {
        public let canDiscard: Bool
        public let canSwitchToKeyboard: Bool
        public let canSend: Bool
        public let canResume: Bool
        public let primaryLabel: String
        public static let preparing = Self(canDiscard: true, canSwitchToKeyboard: true, canSend: false, canResume: false, primaryLabel: "Preparing")
        public static let recording = Self(canDiscard: true, canSwitchToKeyboard: true, canSend: false, canResume: true, primaryLabel: "Pause")
        public static let shortCapture = Self(canDiscard: true, canSwitchToKeyboard: true, canSend: false, canResume: true, primaryLabel: "Pause")
        public static let sendable = Self(canDiscard: true, canSwitchToKeyboard: true, canSend: true, canResume: true, primaryLabel: "Pause")
        public static let pausedEmpty = Self(canDiscard: true, canSwitchToKeyboard: true, canSend: false, canResume: true, primaryLabel: "Resume")
        public static let pausedShort = Self(canDiscard: true, canSwitchToKeyboard: true, canSend: false, canResume: true, primaryLabel: "Resume")
        public static let paused = Self(canDiscard: true, canSwitchToKeyboard: true, canSend: true, canResume: true, primaryLabel: "Resume")
        public static let saved = Self(canDiscard: true, canSwitchToKeyboard: false, canSend: true, canResume: false, primaryLabel: "Recorded")
        public static let waitingForReply = Self(canDiscard: false, canSwitchToKeyboard: false, canSend: false, canResume: false, primaryLabel: "Reply")
    }

    private let phase: Phase
    private let elapsed: String
    private let onDiscard: @MainActor () -> Void
    private let onKeyboard: @MainActor () -> Void
    private let onPrimary: @MainActor () -> Void
    private let onSend: @MainActor () -> Void

    public init(
        phase: Phase, elapsed: String,
        onDiscard: @escaping @MainActor () -> Void,
        onKeyboard: @escaping @MainActor () -> Void,
        onPrimary: @escaping @MainActor () -> Void,
        onSend: @escaping @MainActor () -> Void
    ) {
        self.phase = phase; self.elapsed = elapsed; self.onDiscard = onDiscard
        self.onKeyboard = onKeyboard; self.onPrimary = onPrimary; self.onSend = onSend
    }

    public var body: some View {
        HStack(spacing: TaisaSpacing.compact.rawValue) { controls }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .padding(.vertical, TaisaSpacing.section.rawValue)
        .background { PageEdgeFade(.navigation).ignoresSafeArea(edges: .horizontal) }
    }

    @ViewBuilder private var controls: some View {
        if availability.canDiscard { iconButton(.cross, label: "Discard recording", action: onDiscard) }
        if availability.canSwitchToKeyboard { iconButton(.keyboard, label: "Switch to keyboard", action: onKeyboard) }
        Spacer(minLength: TaisaSpacing.compact.rawValue)
        TaisaSecondaryCapsuleButton(action: onPrimary) {
            HStack(spacing: TaisaSpacing.compact.rawValue) {
                if phase == .recording || phase == .shortCapture || phase == .sendable {
                    ConversationActivityIndicator(active: true)
                } else {
                    CentralIcon(isPaused ? .play : .voiceMid).frame(width: 24, height: 24)
                }
                Text(availability.primaryLabel)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !elapsed.isEmpty {
                    Text(elapsed)
                        .font(.caption)
                        .foregroundStyle(TaisaColor.mutedForeground.color)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
        }
        .layoutPriority(1)
        .disabled(!availability.canResume)
        if availability.canSend {
            Button(action: onSend) { CentralIcon(.arrowUp).frame(width: 24, height: 24).frame(width: 56, height: 56) }
                .buttonStyle(.plain)
                .background(TaisaColor.primaryAction.color, in: Circle())
                .accessibilityLabel("Send recording")
        }
    }

    private var availability: Availability {
        switch phase {
        case .preparing: .preparing
        case .recording: .recording
        case .shortCapture: .shortCapture
        case .sendable: .sendable
        case .pausedEmpty: .pausedEmpty
        case .pausedShort: .pausedShort
        case .paused: .paused
        case .saved: .saved
        case .waitingForReply: .waitingForReply
        }
    }

    private var isPaused: Bool {
        phase == .pausedEmpty || phase == .pausedShort || phase == .paused || phase == .saved
    }

    private func iconButton(_ icon: CentralIconName, label: String, action: @escaping @MainActor () -> Void) -> some View {
        TaisaSecondaryIconButton(icon: icon, accessibilityLabel: label, action: action)
            .frame(width: TaisaControlMetric.conversationRecordingControl, height: TaisaControlMetric.conversationRecordingControl)
    }
}
