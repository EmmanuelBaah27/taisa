import SwiftUI
import TaisaStorage
import TaisaYou

struct YouView: View {
    @Bindable var model: YouModel
    let openRecovery: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDestination: YouDestination? = .careerProfile

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView("Loading You")
            case let .failure(issue):
                ContentUnavailableView {
                    Label(issue == .recoveryRequired ? "Recovery required" : "You is unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(issue == .recoveryRequired ? "Taisa could not safely open your encrypted data." : "Your information could not be loaded from this device.")
                } actions: {
                    if issue == .recoveryRequired {
                        Button("Open backup and recovery", action: openRecovery)
                    } else {
                        Button("Try again") { Task { await model.retry() } }
                    }
                }
            case let .content(snapshot, issue):
                content(snapshot: snapshot, issue: issue)
            }
        }
        .navigationTitle("You")
        .accessibilityIdentifier("you.root")
        .task { if model.state == .idle { await model.load() } }
    }

    @ViewBuilder private func content(snapshot: YouSnapshot, issue: YouIssue?) -> some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                destinationList(issue: issue, selection: $selectedDestination)
                    .navigationTitle("You")
            } detail: {
                if let selectedDestination {
                    destinationView(selectedDestination, snapshot: snapshot)
                }
            }
        } else {
            destinationList(issue: issue)
                .navigationDestination(for: YouDestination.self) { destination in
                    destinationView(destination, snapshot: snapshot)
                }
        }
    }

    private func destinationList(issue: YouIssue?, selection: Binding<YouDestination?>? = nil) -> some View {
        List(selection: selection) {
            if issue != nil { Label("Some local information could not be refreshed.", systemImage: "exclamationmark.triangle") }
            ForEach(YouDestination.allCases, id: \.self) { destination in
                if selection != nil {
                    Label(destination.title, systemImage: destination.systemImage)
                        .tag(destination)
                        .accessibilityIdentifier("you.destination.\(destination.stableID)")
                } else {
                    NavigationLink(value: destination) {
                        Label(destination.title, systemImage: destination.systemImage)
                    }
                    .accessibilityIdentifier("you.destination.\(destination.stableID)")
                }
            }
        }
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
    var body: some View {
        List(YouDiagnostics.rows(for: facts)) { row in
            LabeledContent(row.label, value: row.value)
        }
        .navigationTitle("Diagnostics")
    }
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
