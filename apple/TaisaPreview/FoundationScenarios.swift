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
        scenario(
            identifier: "foundation.default",
            title: "Foundation default",
            deviceFamily: .adaptive
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
            identifier: "foundation.narrowIPad",
            title: "Narrow iPad",
            deviceFamily: .tablet
        ),
        scenario(
            identifier: "foundation.reducedMotion",
            title: "Reduced motion",
            deviceFamily: .adaptive,
            accessibility: PreviewAccessibilitySettings(reducedMotion: true)
        ),
        scenario(
            identifier: "foundation.increasedContrast",
            title: "Increased contrast",
            deviceFamily: .adaptive,
            accessibility: PreviewAccessibilitySettings(increasedContrast: true)
        ),
        scenario(
            identifier: "foundation.diagnostics",
            title: "Build diagnostics",
            deviceFamily: .adaptive,
            detail: "Synthetic build details are available for exact-preview review."
        ),
    ] + HomeScenarios.scenarios + VoiceSessionScenarios.scenarios

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
