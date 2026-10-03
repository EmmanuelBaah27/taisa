import SwiftUI
import TaisaDesignSystem
import TaisaPreviewSupport

struct PreviewCatalogView: View {
    private let registry: TaisaPreviewSupport.PreviewRegistry
    @State private var searchText = ""
    @State private var path: [String]

    init(registry: TaisaPreviewSupport.PreviewRegistry = FoundationScenarios.registry) {
        self.registry = registry
        let arguments = ProcessInfo.processInfo.arguments
        let flagIndex = arguments.firstIndex(of: "-TAISAPreviewScenario")
        let requestedIdentifier = flagIndex.flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
        _path = State(initialValue: requestedIdentifier.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
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
        .accessibilityIdentifier("preview.catalog")
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
            "preview.ready.\(scenario.identifier)"
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
