import SwiftUI
import TaisaDesignSystem
import TaisaStorage

struct DraftRow: View {
    let draft: ConversationDraftRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TaisaIconLabel(title, icon: draft.inputMode == .voice ? .voiceMid : .keyboard, role: .childHeaderTitle)
                .taisaTypography(.childHeaderTitle)
            TaisaText(role: .supporting, color: .mutedForeground, content: status)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(draft.inputMode == .voice ? "Voice" : "Text") draft, \(status)")
        .accessibilityIdentifier("conversation.resume")
    }

    private var title: String {
        guard draft.inputMode == .text, let text = draft.text, !text.isEmpty else { return "Voice draft" }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 80 else { return normalized }
        return String(normalized.prefix(77)) + "…"
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
