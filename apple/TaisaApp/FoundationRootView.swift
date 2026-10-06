import SwiftUI
import TaisaCore
import TaisaDesignSystem

struct FoundationRootView: View {
    @State private var showsDiagnostics = false
    @State private var showsRecovery = false
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
#if DEBUG || TAISA_PREVIEW
                    environmentBadge
                    TaisaButton(role: .secondary, label: "Build diagnostics") {
                        showsDiagnostics = true
                    }
                    .accessibilityIdentifier("foundation.diagnostics.action")
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
