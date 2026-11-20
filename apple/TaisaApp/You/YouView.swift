import SwiftUI
import TaisaDesignSystem
import TaisaStorage
import TaisaYou

struct YouView: View {
    @Bindable var model: YouModel
    let openRecovery: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDestination: YouDestination?
    @State private var showsProfile = false

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                TaisaProgressView("Loading You")
            case let .failure(issue):
                VStack(spacing: TaisaSpacing.standard.rawValue) {
                    TaisaText(role: .profileBody, content: issue.guidance)
                    TaisaButton(role: .secondary, label: issue == .recoveryRequired ? "Open backup and recovery" : "Try again") {
                        if issue == .recoveryRequired { openRecovery() }
                        else { Task { await model.retry() } }
                    }
                }
                .padding(TaisaSpacing.content.rawValue)
            case let .content(snapshot, issue):
                if horizontalSizeClass == .regular {
                    NavigationSplitView {
                        overview(snapshot, issue: issue)
                    } detail: {
                        if let selectedDestination {
                            destinationView(selectedDestination, snapshot: snapshot)
                        } else {
                            TaisaText(role: .profileSupporting, color: .mutedForeground, content: "Choose a setting to view its details.")
                        }
                    }
                } else {
                    overview(snapshot, issue: issue)
                        .navigationDestination(item: $selectedDestination) { destination in
                            destinationView(destination, snapshot: snapshot)
                        }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(TaisaColor.background.color.ignoresSafeArea())
        .accessibilityIdentifier("you.root")
        .task { if model.state == .idle { await model.load() } }
        .fullScreenCover(isPresented: $showsProfile) {
            CareerProfileEditor(model: model) { showsProfile = false }
        }
    }

    private func overview(_ snapshot: YouSnapshot, issue: YouIssue?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaisaSpacing.control.rawValue) {
                TaisaProfileSummary(name: snapshot.profile?.displayName ?? "", bio: snapshot.profile?.biography ?? "") {
                    model.beginProfileEdit()
                    showsProfile = true
                }
                if let issue {
                    TaisaText(role: .profileSupporting, color: .destructive, content: issue.guidance)
                }
                TaisaSettingsGroup {
                    destinationRow(.privacyPermissions, icon: .profileShield)
                    destinationRow(.backupRecovery, icon: .profileCloud)
                    destinationRow(.diagnostics, icon: .profileDiagnostics)
                }
            }
            .padding(.horizontal, TaisaSpacing.content.rawValue)
        }
    }

    private func destinationRow(_ destination: YouDestination, icon: CentralIconName) -> some View {
        TaisaNavigationRow(
            label: destination.title,
            icon: icon,
            trailingIcon: .profileChevron,
            action: { selectedDestination = destination }
        )
        .accessibilityHint("Opens \(destination.title)")
        .accessibilityIdentifier("you.destination.\(destination.stableID)")
    }

    @ViewBuilder private func destinationView(_ destination: YouDestination, snapshot: YouSnapshot) -> some View {
        YouDestinationPage(destination: destination) {
            switch destination {
            case .careerProfile:
                CareerProfileEditor(model: model) { selectedDestination = nil }
            case .privacyPermissions:
                PrivacyPermissionsView(facts: snapshot.diagnostics)
            case .backupRecovery:
                VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
                    TaisaProfileSection("Backup & recovery") {
                        TaisaText(role: .profileSupporting, color: .mutedForeground, content: YouPrivacyCopy.recoveryBoundary)
                        TaisaButton(role: .secondary, label: "Open backup and recovery") { openRecovery() }
                    }
                }
            case .diagnostics:
                DiagnosticsSummaryView(facts: snapshot.diagnostics)
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
        self.destination = destination; self.content = content()
    }
    var body: some View {
        ScrollView {
            content
                .padding(TaisaSpacing.content.rawValue)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TaisaChildPageHeader(destination.title,
                mode: horizontalSizeClass == .regular ? .detail : .back,
                back: { dismiss() })
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(TaisaColor.background.color.ignoresSafeArea())
    }
}

private struct CareerProfileEditor: View {
    @Bindable var model: YouModel
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var closing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaisaSpacing.content.rawValue) {
                HStack(alignment: .top) {
                    TaisaProfileAvatar(
                        name: model.profileDraft?.displayName ?? "",
                        size: TaisaProfileMetric.editorAvatar
                    )
                    Spacer()
                    TaisaSecondaryIconButton(icon: .profileClose, accessibilityLabel: "Close profile editor") {
                        closing = true
                        Task {
                            if !model.profileValidation.isValid {
                                close()
                            } else if await model.finishProfileEditing() {
                                close()
                            }
                            closing = false
                        }
                    }
                    .disabled(closing)
                    .accessibilityIdentifier("you.profile.close")
                }
                TaisaField("Display name", text: binding(\.displayName),
                    state: fieldState(model.profileValidation.displayNameMessage), appearance: .profile)
                    .accessibilityIdentifier("you.profile.name")
                TaisaField("Bio", text: binding(\.biography), kind: .multiline,
                    state: fieldState(model.profileValidation.biographyMessage), appearance: .profile)
                    .accessibilityIdentifier("you.profile.bio")
                if model.profileSaveState == .failed {
                    TaisaText(role: .profileSupporting, color: .destructive,
                        content: "Your changes haven’t been saved. They’re still here. Try again.")
                    TaisaButton(role: .secondary, label: "Try again") {
                        Task { _ = await model.flushProfileChanges() }
                    }
                    .accessibilityIdentifier("you.profile.retry")
                } else if model.profileSaveState == .saving || closing {
                    TaisaProgressView("Saving changes")
                        .accessibilityIdentifier("you.profile.saving")
                }
            }
            .padding(.horizontal, TaisaSpacing.content.rawValue)
            .padding(.top, TaisaSpacing.control.rawValue)
            .disabled(closing)
        }
        .background(TaisaColor.background.color.ignoresSafeArea())
        .interactiveDismissDisabled()
        .task { model.beginProfileEdit() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { _ = await model.flushProfileChanges() } }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ProfileDraft, String>) -> Binding<String> {
        Binding(get: { model.profileDraft?[keyPath: keyPath] ?? "" }, set: { value in
            guard var draft = model.profileDraft else { return }
            draft[keyPath: keyPath] = value
            model.updateProfileBio(displayName: draft.displayName, biography: draft.biography)
        })
    }

    private func fieldState(_ message: String?) -> TaisaFieldState {
        message.map(TaisaFieldState.invalid(message:)) ?? .enabled
    }
}

private struct PrivacyPermissionsView: View {
    let facts: YouOperationalFacts
    private var microphone: YouPermissionGuidance { .microphone(facts.microphone) }
    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
            TaisaProfileSection("On this device") {
                TaisaText(role: .profileBody, content: YouPrivacyCopy.encryptedLocation)
                TaisaText(role: .profileSupporting, color: .mutedForeground, content: YouPrivacyCopy.retentionBoundary)
            }
            TaisaProfileSection("When information leaves your device") {
                TaisaText(role: .profileSupporting, color: .mutedForeground, content: YouPrivacyCopy.networkBoundary)
            }
            TaisaProfileSection("Microphone") {
                TaisaText(role: .profileBody, content: microphone.status.displayName)
                TaisaText(role: .profileSupporting, color: .mutedForeground, content: microphone.guidance)
            }
            TaisaProfileSection("Recovery") {
                TaisaText(role: .profileSupporting, color: .mutedForeground, content: YouPrivacyCopy.recoveryBoundary)
            }
        }
    }
}

private struct DiagnosticsSummaryView: View {
    let facts: YouOperationalFacts
    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
            ForEach(YouDiagnostics.rows(for: facts)) { row in
                TaisaProfileSection(row.label) {
                    TaisaText(role: .profileSupporting, color: .mutedForeground, content: row.value)
                }
            }
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
