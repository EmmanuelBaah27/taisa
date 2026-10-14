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
        case .capabilities: CapabilityOverviewView(snapshot: snapshot)
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
    let snapshot: YouSnapshot
    var body: some View { List(snapshot.capabilities) { capability in LabeledContent(capability.id.rawValue, value: capability.chosenState.rawValue.capitalized) }.navigationTitle("Capabilities") }
}

private struct PrivacyPermissionsView: View {
    let facts: YouOperationalFacts
    var body: some View { List { Text("Your readable career data stays encrypted on this device."); LabeledContent("Microphone", value: facts.microphone.rawValue) }.navigationTitle("Privacy & permissions") }
}

private struct DiagnosticsSummaryView: View {
    let facts: YouOperationalFacts
    var body: some View { List { LabeledContent("Local store", value: facts.store.rawValue); LabeledContent("Recovery", value: facts.recovery.rawValue); LabeledContent("Voice gateway", value: facts.gateway.rawValue) }.navigationTitle("Diagnostics") }
}
