import SwiftUI
import TaisaStorage
import TaisaYou

struct YouView: View {
    @Bindable var model: YouModel
    let openRecovery: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView("Loading You")
            case .failure:
                ContentUnavailableView("You is unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
            case let .content(snapshot, issue):
                List {
                    if issue != nil { Label("Some local information could not be refreshed.", systemImage: "exclamationmark.triangle") }
                    ForEach(YouDestination.allCases, id: \.self) { destination in
                        NavigationLink(value: destination) {
                            Label(destination.title, systemImage: destination.systemImage)
                        }
                        .accessibilityIdentifier("you.destination.\(destination.stableID)")
                    }
                }
                .navigationDestination(for: YouDestination.self) { destination in
                    destinationView(destination, snapshot: snapshot)
                }
            }
        }
        .navigationTitle("You")
        .accessibilityIdentifier("you.root")
        .task { if model.state == .idle { await model.load() } }
    }

    @ViewBuilder private func destinationView(_ destination: YouDestination, snapshot: YouSnapshot) -> some View {
        switch destination {
        case .careerProfile: CareerProfileView(model: model, profile: snapshot.profile)
        case .capabilities: CapabilityOverviewView(model: model, snapshot: snapshot)
        case .privacyPermissions: PrivacyPermissionsView(facts: snapshot.diagnostics)
        case .backupRecovery:
            List { Button("Open backup and recovery", action: openRecovery) }
                .navigationTitle(destination.title)
        case .diagnostics: DiagnosticsSummaryView(facts: snapshot.diagnostics)
        }
    }
}

private struct CareerProfileView: View {
    @Bindable var model: YouModel
    let profile: ProfileRecord?
    @State private var editing = false

    var body: some View {
        Form {
            if editing, model.profileDraft != nil {
                TextField("Display name", text: binding(\.displayName))
                TextField("Headline", text: binding(\.headline))
                TextField("Biography", text: binding(\.biography), axis: .vertical)
                Button("Save") { Task { await model.saveProfile(); editing = model.profileDraft != nil } }
                Button("Cancel", role: .cancel) { model.cancelProfileEdit(); editing = false }
            } else {
                LabeledContent("Display name", value: profile?.displayName.isEmpty == false ? profile!.displayName : "Not set")
                LabeledContent("Headline", value: profile?.headline.isEmpty == false ? profile!.headline : "Not set")
                if let biography = profile?.biography, !biography.isEmpty { Text(biography) }
                Button("Edit career profile") { model.beginProfileEdit(); editing = true }
            }
        }
        .navigationTitle("Career profile")
    }

    private func binding(_ keyPath: WritableKeyPath<ProfileDraft, String>) -> Binding<String> {
        Binding(get: { model.profileDraft?[keyPath: keyPath] ?? "" }, set: { value in
            guard var draft = model.profileDraft else { return }
            draft[keyPath: keyPath] = value
            model.updateProfile(displayName: draft.displayName, headline: draft.headline, biography: draft.biography)
        })
    }
}

private struct CapabilityOverviewView: View {
    @Bindable var model: YouModel
    let snapshot: YouSnapshot
    var body: some View {
        List(snapshot.capabilities) { capability in
            Section(capability.id.title) {
                Picker("Your choice", selection: Binding(
                    get: { capability.chosenState },
                    set: { requested in Task { await model.requestCapabilityChange(capability.id, to: requested) } }
                )) {
                    ForEach(CapabilityGovernanceState.allCases, id: \.self) { state in
                        Text(state.rawValue.capitalized).tag(state)
                    }
                }
                LabeledContent("Availability", value: capability.availability.rawValue.capitalized)
            }
        }
        .navigationTitle("Capabilities")
        .confirmationDialog(
            "Confirm capability change",
            isPresented: Binding(
                get: { model.pendingCapabilityReview != nil },
                set: { if !$0 { model.cancelCapabilityChange() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Confirm") { Task { await model.confirmCapabilityChange() } }
            Button("Cancel", role: .cancel) { model.cancelCapabilityChange() }
        } message: {
            Text("This changes how much responsibility Taisa may take. You can reduce it again at any time.")
        }
    }
}

private struct PrivacyPermissionsView: View {
    let facts: YouOperationalFacts
    private var microphone: YouPermissionGuidance { .microphone(facts.microphone) }
    var body: some View {
        List {
            Section("Readable data") {
                LabeledContent("Stored", value: YouPrivacyCopy.readableData)
                LabeledContent("Protection", value: YouPrivacyCopy.encryptedLocation)
            }
            Section("Permissions") {
                LabeledContent("Microphone", value: microphone.status.displayName)
                Text(microphone.guidance)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy & permissions")
    }
}

private struct DiagnosticsSummaryView: View {
    let facts: YouOperationalFacts
    var body: some View { List { LabeledContent("Local store", value: facts.store.rawValue); LabeledContent("Recovery", value: facts.recovery.rawValue); LabeledContent("Voice gateway", value: facts.gateway.rawValue) }.navigationTitle("Diagnostics") }
}

private extension CapabilityID {
    var title: String {
        switch self {
        case .voice: "Voice"
        case .seniorSelf: "Senior self"
        case .insights: "Insights"
        }
    }
}

private extension YouPermissionStatus {
    var displayName: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        }
    }
}
