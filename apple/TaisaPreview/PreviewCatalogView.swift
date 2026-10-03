import SwiftUI
import TaisaDesignSystem
import TaisaPreviewSupport

struct PreviewCatalogView: View {
    private let registry: TaisaPreviewSupport.PreviewRegistry
    @State private var searchText = ""

    init(registry: TaisaPreviewSupport.PreviewRegistry = FoundationScenarios.registry) {
        self.registry = registry
    }

    var body: some View {
        NavigationStack {
            List(filteredScenarios) { scenario in
                NavigationLink(value: scenario.identifier) {
                    VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
                        TaisaText(role: .label, content: scenario.title)
                        TaisaText(
                            role: .metadata,
                            color: .mutedForeground,
                            content: scenario.deviceFamily.title
                        )
                        TaisaText(
                            role: .metadata,
                            color: .mutedForeground,
                            content: scenario.accessibility.summary
                        )
                    }
                    .padding(.vertical, TaisaSpacing.compact.rawValue)
                }
                .accessibilityLabel(
                    "\(scenario.title), \(scenario.deviceFamily.title), "
                        + scenario.accessibility.summary
                )
            }
            .navigationTitle("Taisa Preview")
            .searchable(text: $searchText, prompt: "Search scenarios")
            .navigationDestination(for: String.self) { identifier in
                if let scenario = registry.scenario(identifier: identifier) {
                    PreviewScenarioView(scenario: scenario)
                }
            }
        }
        .accessibilityIdentifier("preview.catalog.ready")
    }

    private var filteredScenarios: [PreviewScenario] {
        guard !searchText.isEmpty else { return registry.scenarios }
        return registry.scenarios.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.identifier.localizedStandardContains(searchText)
        }
    }
}

private struct PreviewScenarioView: View {
    let scenario: PreviewScenario

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
                VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
                    TaisaText(
                        role: .metadata,
                        color: .mutedForeground,
                        content: "Device: \(scenario.deviceFamily.title)"
                    )
                    TaisaText(
                        role: .metadata,
                        color: .mutedForeground,
                        content: "Appearance: \(scenario.accessibility.summary)"
                    )
                }
                scenario.makeRootView()
            }
        }
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .accessibilityIdentifier(
            "preview.scenario.\(scenario.identifier).\(scenario.readiness.rawValue)"
        )
    }

    private var dynamicTypeSize: DynamicTypeSize {
        switch scenario.accessibility.contentSize {
        case .standard:
            .large
        case .accessibilityExtraExtraExtraLarge:
            .accessibility3
        }
    }
}

#Preview {
    PreviewCatalogView()
}
