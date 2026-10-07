import SwiftUI
import TaisaDesignSystem
import TaisaVoice

struct VoiceSessionDiagnosticsView: View {
    let snapshot: VoiceSessionSnapshot
    let onAction: @MainActor (VoiceSessionDiagnosticAction) -> Void
    private let reduceMotionOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        snapshot: VoiceSessionSnapshot,
        reduceMotionOverride: Bool? = nil,
        onAction: @escaping @MainActor (VoiceSessionDiagnosticAction) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.reduceMotionOverride = reduceMotionOverride
        self.onAction = onAction
    }

    var body: some View {
        let model = VoiceSessionDiagnosticsViewModel(
            snapshot: snapshot,
            reduceMotion: reduceMotionOverride ?? reduceMotion
        )
        ScrollView {
            VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
                VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
                    TaisaText(role: .heading, content: "Conversation session")
                        .accessibilityAddTraits(.isHeader)
                    TaisaText(role: .body, color: .mutedForeground, content: model.statusTitle)
                        .accessibilityIdentifier("voice.diagnostics.status")
                        .accessibilityLabel(model.statusAccessibilityLabel)
                    TaisaText(
                        role: .metadata,
                        color: .mutedForeground,
                        content: "Stage: \(model.stage.rawValue)"
                    )
                }
                VoiceActivityIndicator(isAnimated: model.animatesWaveform)
                VStack(spacing: TaisaSpacing.standard.rawValue) {
                    ForEach(model.actions) { action in
                        TaisaButton(role: role(for: action), label: action.title) { onAction(action) }
                            .accessibilityIdentifier("voice.action.\(action.rawValue)")
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(TaisaSpacing.page.rawValue)
            .frame(maxWidth: .infinity)
        }
        .background(TaisaColor.background.color)
        .navigationTitle("Voice diagnostics")
        .accessibilityIdentifier("voice.diagnostics.root")
    }

    private func role(for action: VoiceSessionDiagnosticAction) -> TaisaButtonRole {
        switch action {
        case .record, .send, .confirmTranscript, .retry, .confirmResume: .primary
        case .pause, .resume, .cancel, .discard: .secondary
        }
    }
}

private struct VoiceActivityIndicator: View {
    let isAnimated: Bool

    var body: some View {
        HStack(alignment: .center, spacing: TaisaSpacing.compact.rawValue) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(TaisaColor.primaryAction.color)
                    .frame(width: TaisaSpacing.compact.rawValue, height: barHeight(index))
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAnimated ? "Recording activity" : "Audio activity paused")
        .accessibilityIdentifier(isAnimated ? "voice.waveform.animated" : "voice.waveform.static")
    }

    private func barHeight(_ index: Int) -> CGFloat {
        guard isAnimated else { return TaisaSpacing.standard.rawValue }
        return index.isMultiple(of: 2) ? TaisaSpacing.section.rawValue : TaisaSpacing.standard.rawValue
    }
}
