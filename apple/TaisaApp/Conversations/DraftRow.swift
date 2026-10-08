import SwiftUI
import TaisaStorage

struct DraftRow: View {
    let draft: ConversationDraftRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: draft.inputMode == .voice ? "waveform" : "keyboard")
                .font(.headline)
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("conversation.resume")
    }

    private var title: String {
        guard draft.inputMode == .text, let text = draft.text, !text.isEmpty else { return "Voice draft" }
        return text
    }

    private var status: String {
        switch draft.recoveryKind {
        case .saved: "Saved draft"
        case .recovered: "Recovered draft"
        case .retryableTranscription: "Transcription needs attention"
        case .retryableCoaching: "Reply needs attention"
        }
    }
}
