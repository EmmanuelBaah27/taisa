#if TAISA_PERSONAL
import SwiftUI

struct PersonalVoiceSessionView: View {
    @StateObject private var model = PersonalVoiceSessionModel()
    @State private var enrollmentCode = ""

    var body: some View {
        Group {
            if let snapshot = model.snapshot {
                VoiceSessionDiagnosticsView(snapshot: snapshot, actionStatus: model.status) { action in
                    model.perform(action)
                }
            } else if needsEnrollment {
                enrollmentForm
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

    private var needsEnrollment: Bool {
        switch model.gatewayState {
        case .enrollmentRequired, .enrolling, .invalidOrExpiredCode,
             .credentialRejected, .reEnrollmentRequired:
            true
        case .notConfigured, .ready:
            false
        }
    }

    private var enrollmentForm: some View {
        Form {
            Section("Voice gateway") {
                Text(model.status)
                SecureField("Enrollment code", text: $enrollmentCode)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("voice.enrollment.code")
                Button("Connect this device") {
                    let code = enrollmentCode
                    enrollmentCode = ""
                    Task { await model.connect(code: code) }
                }
                .disabled(enrollmentCode.isEmpty || model.gatewayState == .enrolling)
                .accessibilityIdentifier("voice.enrollment.connect")
                if model.gatewayState == .enrolling {
                    ProgressView("Connecting…")
                }
            }
        }
    }
}
#endif
