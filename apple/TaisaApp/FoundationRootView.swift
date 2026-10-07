import SwiftUI
import TaisaCore
import TaisaDesignSystem
import TaisaStorage
import TaisaVoice

struct FoundationRootView: View {
    @State private var showsDiagnostics = false
    @State private var showsRecovery = false
    @State private var showsVoiceDiagnostics = false
    @State private var recoveryImportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
                    VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
                        TaisaText(role: .display, content: "Taisa")
                            .accessibilityIdentifier("foundation.title")
                        TaisaText(
                            role: .body,
                            color: .mutedForeground,
                            content: "Native foundation ready"
                        )
                        if let storageStatus {
                            TaisaText(
                                role: .body,
                                color: .mutedForeground,
                                content: storageStatus
                            )
                            .accessibilityIdentifier("foundation.storage.status")
                        }
                    }
                    if storageStatus != nil {
                        TaisaButton(role: .secondary, label: "Backup and recovery") { showsRecovery = true }
                            .accessibilityIdentifier("foundation.recovery.action")
                    }
#if TAISA_PERSONAL
                    if ProcessInfo.processInfo.arguments.contains(PersonalDeviceQA.launchArgument) {
                        NavigationLink { PersonalDeviceQAView() } label: {
                            TaisaText(role: .body, content: "Personal device QA")
                        }
                        .accessibilityIdentifier("foundation.personal-qa.action")
                    }
#endif
#if DEBUG || TAISA_PREVIEW
                    environmentBadge
                    TaisaButton(role: .secondary, label: "Build diagnostics") {
                        showsDiagnostics = true
                    }
                    .accessibilityIdentifier("foundation.diagnostics.action")
                    TaisaButton(role: .secondary, label: "Voice platform diagnostics") {
                        showsVoiceDiagnostics = true
                    }
                    .accessibilityIdentifier("foundation.voice-diagnostics.action")
#endif
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(TaisaSpacing.page.rawValue)
                .frame(maxWidth: .infinity)
            }
            .background(TaisaColor.background.color)
            .navigationDestination(isPresented: $showsDiagnostics) {
#if DEBUG || TAISA_PREVIEW
                BuildDiagnosticsView()
#else
                EmptyView()
#endif
            }
            .accessibilityIdentifier("foundation.root")
            .navigationDestination(isPresented: $showsRecovery) { RecoveryView(importURL: recoveryImportURL) }
            .navigationDestination(isPresented: $showsVoiceDiagnostics) {
#if TAISA_PERSONAL
                PersonalVoiceSessionView()
#elseif DEBUG || TAISA_PREVIEW
                VoiceSessionDiagnosticsView(snapshot: diagnosticVoiceSnapshot)
#else
                EmptyView()
#endif
            }
            .onOpenURL { url in
                guard storageStatus != nil else { return }
                recoveryImportURL = url
                showsRecovery = true
            }
            .onChange(of: showsRecovery) { _, shown in
                if !shown { recoveryImportURL = nil }
            }
        }
    }

#if DEBUG || TAISA_PREVIEW
    private var environmentBadge: some View {
        TaisaText(
            role: .metadata,
            content: currentEnvironment.rawValue.uppercased()
        )
        .padding(.horizontal, TaisaSpacing.compact.rawValue)
        .frame(minHeight: 44)
        .background(TaisaColor.primaryAction.color)
        .clipShape(Capsule())
        .accessibilityLabel("Environment: \(currentEnvironment.rawValue)")
    }

#endif

    var storageStatus: String? {
        SyncCapability.forEnvironment(currentEnvironment) == .localOnly
            ? "Stored securely on this device"
            : nil
    }

    private var currentEnvironment: TaisaEnvironment {
        let value = Bundle.main.object(forInfoDictionaryKey: "TaisaEnvironment") as? String
            ?? "development"
        return (try? TaisaEnvironment(configurationValue: value)) ?? .development
    }

#if DEBUG || TAISA_PREVIEW
    private var diagnosticVoiceSnapshot: VoiceSessionSnapshot {
        VoiceSessionSnapshot(
            durable: VoiceTurnRecord(
                id: UUID().uuidString,
                conversationID: UUID().uuidString,
                transcriptionRequestID: UUID().uuidString,
                transcriptionIdempotencyKey: "diagnostic-transcription",
                coachingRequestID: UUID().uuidString,
                coachingIdempotencyKey: "diagnostic-coaching",
                state: .draft,
                stage: .capture,
                createdAtMS: 0,
                updatedAtMS: 0
            ),
            partialTranscript: "",
            partialCoaching: ""
        )
    }
#endif
}

#Preview("iPhone") {
    FoundationRootView()
}

#Preview("iPad split width", traits: .fixedLayout(width: 507, height: 720)) {
    FoundationRootView()
}

#Preview("Accessibility XXXL") {
    FoundationRootView()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Increased contrast") {
    FoundationRootView()
}

#Preview("Reduced transparency") {
    FoundationRootView()
}
