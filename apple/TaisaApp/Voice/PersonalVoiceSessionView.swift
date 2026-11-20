#if TAISA_PERSONAL
import SwiftUI
import TaisaDesignSystem

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
                ContentUnavailableView {
                    TaisaIconLabel("Voice session unavailable", icon: .voiceMid, role: .heading)
                } description: {
                    TaisaText(role: .body, content: model.status)
                }
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
            TaisaSection("Voice gateway") {
                TaisaText(role: .body, content: model.status)
                TaisaSystemSecureField("Enrollment code", text: $enrollmentCode)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("voice.enrollment.code")
                TaisaButtonControl("Connect this device") {
                    let code = enrollmentCode
                    enrollmentCode = ""
                    Task { await model.connect(code: code) }
                }
                .disabled(enrollmentCode.isEmpty || model.gatewayState == .enrolling)
                .accessibilityIdentifier("voice.enrollment.connect")
                if model.gatewayState == .enrolling {
                    TaisaProgressView("Connecting…")
                }
            }
        }
    }
}
#endif
