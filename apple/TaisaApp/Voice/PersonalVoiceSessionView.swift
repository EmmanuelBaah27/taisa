#if TAISA_PERSONAL
import SwiftUI

struct PersonalVoiceSessionView: View {
    @StateObject private var model = PersonalVoiceSessionModel()

    var body: some View {
        Group {
            if let snapshot = model.snapshot {
                VoiceSessionDiagnosticsView(snapshot: snapshot, actionStatus: model.status) { action in
                    model.perform(action)
                }
            } else {
                ContentUnavailableView(
                    "Voice session unavailable",
                    systemImage: "waveform.slash",
                    description: Text(model.status)
                )
                .accessibilityIdentifier("voice.runtime.unavailable")
            }
        }
        .task { await model.start() }
    }
}
#endif
