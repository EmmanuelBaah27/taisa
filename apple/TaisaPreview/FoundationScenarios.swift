import SwiftUI
import TaisaDesignSystem
import TaisaPreviewSupport

@MainActor
enum FoundationScenarios {
    static let registry: TaisaPreviewSupport.PreviewRegistry = {
        do {
            return try TaisaPreviewSupport.PreviewRegistry(scenarios: scenarios)
        } catch {
            preconditionFailure("Foundation preview scenarios must have unique identifiers: \(error)")
        }
    }()

    private static let scenarios: [PreviewScenario] = [
        PreviewScenario(
            identifier: "foundation.buttons",
            title: "Shared button foundation",
            deviceFamily: .adaptive,
            accessibility: .default,
            readiness: .ready
        ) { AnyView(ButtonFoundationScenario()) },
        scenario(
            identifier: "foundation.default",
            title: "Foundation default",
            deviceFamily: .phone
        ),
        scenario(
            identifier: "foundation.accessibilityText",
            title: "Accessibility text",
            deviceFamily: .phone,
            accessibility: PreviewAccessibilitySettings(
                contentSize: .accessibilityExtraExtraExtraLarge
            )
        ),
        scenario(
            identifier: "foundation.reducedMotion",
            title: "Reduced motion",
            deviceFamily: .phone,
            accessibility: PreviewAccessibilitySettings(reducedMotion: true)
        ),
        scenario(
            identifier: "foundation.increasedContrast",
            title: "Increased contrast",
            deviceFamily: .phone,
            accessibility: PreviewAccessibilitySettings(increasedContrast: true)
        ),
        scenario(
            identifier: "foundation.diagnostics",
            title: "Build diagnostics",
            deviceFamily: .phone,
            detail: "Synthetic build details are available for exact-preview review."
        ),
    ] + HomeScenarios.scenarios + CareerWorkScenarios.scenarios + YouScenarios.scenarios + VoiceSessionScenarios.scenarios + ConversationScenarios.scenarios + RecordingGlowScenarios.scenarios

    private static func scenario(
        identifier: String,
        title: String,
        deviceFamily: PreviewDeviceFamily,
        accessibility: PreviewAccessibilitySettings = .default,
        detail: String = "This state contains synthetic preview content only."
    ) -> PreviewScenario {
        PreviewScenario(
            identifier: identifier,
            title: title,
            deviceFamily: deviceFamily,
            accessibility: accessibility,
            readiness: .ready
        ) {
            AnyView(
                FoundationScenarioView(
                    title: title,
                    detail: detail
                )
            )
        }
    }
}

private struct ButtonFoundationScenario: View {
    @State private var recordCount = 0
    @State private var actionCount = 0
    @State private var floatingCount = 0
    @State private var confirmedCount = 0
    @State private var showsConfirmation = false

    var body: some View {
        VStack(spacing: TaisaSpacing.standard.rawValue) {
            ConversationEntryDock(onVoice: { recordCount += 1 }, onKeyboard: {})
                .accessibilityIdentifier("buttons.record")
            TaisaButton(role: .primary, label: "Primary action") { actionCount += 1 }
                .accessibilityIdentifier("buttons.primary")
            TaisaButton(role: .secondary, label: "Secondary action") { actionCount += 1 }
                .accessibilityIdentifier("buttons.secondary")
            TaisaButton(role: .destructive, label: "Destructive action") { showsConfirmation = true }
                .accessibilityIdentifier("buttons.destructive")
            HStack {
                TaisaSecondaryIconButton(icon: .chevronLeft, accessibilityLabel: "Header action") { actionCount += 1 }
                    .accessibilityIdentifier("buttons.header")
                ConversationJumpToLatestButton(isLoading: false) { floatingCount += 1 }
                    .accessibilityIdentifier("buttons.floating")
                TaisaSecondaryCapsuleButton(action: { actionCount += 1 }) {
                    TaisaText(role: .label, content: "Capsule action")
                        .padding(.horizontal, TaisaSpacing.standard.rawValue)
                }
            }
            TaisaButton(role: .primary, label: "Processing", isProcessing: true) { actionCount += 1 }
                .accessibilityIdentifier("buttons.processing")
            TaisaText(role: .metadata, content: "Record \(recordCount), actions \(actionCount), floating \(floatingCount), confirmed \(confirmedCount)")
                .accessibilityIdentifier("buttons.counts")
        }
        .padding(TaisaSpacing.standard.rawValue)
        .background(TaisaColor.subtleSurface.color, in: RoundedRectangle(cornerRadius: TaisaRadius.panel.rawValue))
        .confirmationDialog("Preview confirmation", isPresented: $showsConfirmation) {
            TaisaSystemButton("Confirm preview action", role: .destructive) { confirmedCount += 1 }
            TaisaSystemButton("Cancel", role: .cancel) {}
        }
    }
}

private struct FoundationScenarioView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
            TaisaText(role: .display, content: "Taisa")
            TaisaText(role: .heading, content: title)
                .accessibilityIdentifier("preview.scenario.title")
            TaisaText(role: .body, color: .mutedForeground, content: detail)
            TaisaButton(role: .primary, label: "Preview action") {}
                .accessibilityIdentifier("preview.scenario.primaryAction")
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(TaisaSpacing.page.rawValue)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(TaisaColor.background.color)
    }
}
