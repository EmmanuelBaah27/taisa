import SwiftUI
import TaisaDesignSystem
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
                    Text(issue.guidance)
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
        YouDestinationPage(destination: destination) {
            switch destination {
            case .careerProfile: CareerProfileView(model: model, profile: snapshot.profile, issue: model.state.issue)
            case .privacyPermissions: PrivacyPermissionsView(facts: snapshot.diagnostics)
            case .backupRecovery:
                List { Button("Open backup and recovery", action: openRecovery) }
            case .diagnostics: DiagnosticsSummaryView(facts: snapshot.diagnostics)
            }
        }
    }
}

private struct YouDestinationPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let destination: YouDestination
    private let content: Content

    init(destination: YouDestination, @ViewBuilder content: () -> Content) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                TaisaChildPageHeader(destination.title,
                    mode: horizontalSizeClass == .regular ? .detail : .back,
                    back: { dismiss() }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(TaisaColor.background.color.ignoresSafeArea())
    }
}

private struct CareerProfileView: View {
    @Bindable var model: YouModel
    let profile: ProfileRecord?
    let issue: YouIssue?
    @State private var editing = false

    var body: some View {
        Form {
            if let issue {
                Label(issue.guidance, systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("you.profile.issue")
            }
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
    }

    private func binding(_ keyPath: WritableKeyPath<ProfileDraft, String>) -> Binding<String> {
        Binding(get: { model.profileDraft?[keyPath: keyPath] ?? "" }, set: { value in
            guard var draft = model.profileDraft else { return }
            draft[keyPath: keyPath] = value
            model.updateProfile(displayName: draft.displayName, headline: draft.headline, biography: draft.biography)
        })
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
                Text(YouPrivacyCopy.retentionBoundary).foregroundStyle(.secondary)
            }
            Section("Network boundary") {
                Text(YouPrivacyCopy.networkBoundary)
            }
            Section("Recovery boundary") {
                Text(YouPrivacyCopy.recoveryBoundary)
            }
            Section("Permissions") {
                LabeledContent("Microphone", value: microphone.status.displayName)
                Text(microphone.guidance)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DiagnosticsSummaryView: View {
    let facts: YouOperationalFacts
    var body: some View {
        List(YouDiagnostics.rows(for: facts)) { row in
            LabeledContent(row.label, value: row.value)
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
