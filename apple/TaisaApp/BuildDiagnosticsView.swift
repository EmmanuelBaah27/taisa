import SwiftUI
import TaisaCore

#if DEBUG || TAISA_PREVIEW
struct BuildDiagnosticsView: View {
    private let identity: BuildIdentity

    init(bundle: Bundle = .main) {
        let environmentValue = bundle.object(forInfoDictionaryKey: "TaisaEnvironment") as? String
            ?? "development"
        let environment = (try? TaisaEnvironment(configurationValue: environmentValue))
            ?? .development
        identity = BuildIdentity(
            gitCommit: GeneratedBuildMetadata.gitCommit,
            gitBranch: GeneratedBuildMetadata.gitBranch,
            isDirty: GeneratedBuildMetadata.isDirty,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            environment: environment,
            contractRevision: GeneratedBuildMetadata.contractRevision
        )
    }

    var body: some View {
        List {
            diagnosticRow("Source", value: identity.sourceDescription)
            diagnosticRow("Build", value: identity.buildNumber)
            diagnosticRow("Bundle", value: identity.bundleIdentifier)
            diagnosticRow("Environment", value: identity.environment.rawValue)
            diagnosticRow("Contracts", value: identity.contractRevision)
        }
        .navigationTitle("Build diagnostics")
        .accessibilityIdentifier("foundation.diagnostics")
    }

    private func diagnosticRow(_ label: String, value: String) -> some View {
        LabeledContent(label, value: value)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
    }
}
#endif
