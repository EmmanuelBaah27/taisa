#if TAISA_PERSONAL
import SwiftUI
import TaisaDesignSystem

struct PersonalDeviceQAView: View {
    @State private var harness: PersonalDeviceQA?
    @State private var evidence: PersonalDeviceQA.Evidence?
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
                TaisaText(role: .heading, content: "Personal device QA")
                TaisaText(role: .body, content: "Inspection does not create data. Create the public canary once on the source device. After reinstall or restore, inspect before creating anything.")
                if let evidence {
                    TaisaText(role: .body, content: evidence.canaryCount == 1
                        ? "Canary: present and verified" : "Canary: absent or unverified")
                        .accessibilityIdentifier("personal-qa.presence")
                    TaisaText(role: .metadata, content: "Canary count: \(evidence.canaryCount); conversations: \(evidence.conversationCount)")
                        .accessibilityIdentifier("personal-qa.counts")
                    TaisaText(role: .metadata, content: "Canary SHA-256: \(evidence.hash ?? "unavailable")")
                        .accessibilityIdentifier("personal-qa.hash")
                }
                if failed {
                    TaisaText(role: .body, content: "QA evidence could not be verified. No existing data was replaced.")
                }
                TaisaButton(role: .secondary, label: "Inspect stored evidence") {
                    Task { await perform(create: false) }
                }
                .accessibilityIdentifier("personal-qa.inspect")
                TaisaButton(role: .secondary, label: "Create public canary once") {
                    Task { await perform(create: true) }
                }
                .accessibilityIdentifier("personal-qa.create")
                NavigationLink { RecoveryView() } label: {
                    TaisaText(role: .body, content: "Backup and recovery")
                }
                NavigationLink { PersonalVoiceSessionView() } label: {
                    TaisaText(role: .body, content: "Voice gateway and streaming")
                }
                .accessibilityIdentifier("personal-qa.voice")
            }
            .disabled(busy)
            .padding(TaisaSpacing.page.rawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TaisaColor.background.color)
        .navigationTitle("Personal device QA")
        .navigationBarTitleDisplayMode(.inline)
        .task { await perform(create: false) }
    }

    private func perform(create: Bool) async {
        guard !busy else { return }
        busy = true; failed = false
        defer { busy = false }
        do {
            if harness == nil {
                harness = PersonalDeviceQA(backend: try .personal(), arguments: ProcessInfo.processInfo.arguments)
            }
            guard let harness else { return }
            evidence = try await create ? harness.createCanary() : harness.inspect()
        } catch {
            evidence = nil; failed = true
        }
    }
}
#endif
