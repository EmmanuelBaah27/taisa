import SwiftUI
import TaisaDesignSystem
import TaisaSecurity

struct RecoveryView: View {
    var importURL: URL? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: RecoveryViewModel?
    @State private var enteredKey = ""
    @State private var passwordsSaved = false
    @State private var offlineSaved = false
    @State private var importing = false
    @State private var exporting = false
    @State private var sharing = false
    @State private var initializationFailed = false

    init(importURL: URL? = nil, model: RecoveryViewModel? = nil) {
        self.importURL = importURL
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
                TaisaText(role: .heading, content: "Backup and recovery")
                    .accessibilityAddTraits(.isHeader)
                if let model {
                    if model.isShielded || scenePhase != .active {
                        TaisaText(role: .body, content: "Taisa is locked")
                            .accessibilityIdentifier("recovery.shield")
                    } else { content(model).disabled(importing || exporting || sharing) }
                } else {
                    TaisaText(role: .body, content: initializationFailed
                        ? "Recovery could not open safely. Reopen Taisa to try again." : "Opening secure storage…")
                }
            }
            .padding(TaisaSpacing.page.rawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TaisaColor.background.color)
        .navigationTitle("Backup and recovery")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model?.state == .restoring)
        .interactiveDismissDisabled(model?.state == .restoring)
        .task(id: importURL) {
            await initialize()
            if let importURL { await model?.selectImport(importURL) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.taisaBackup], allowsMultipleSelection: false, onCompletion: { result in
            guard let model else { return }
            switch result {
            case .success(let urls):
                if let url = urls.first { Task { await model.selectImport(url) } }
            case .failure: Task { await model.cancel() }
            }
        }, onCancellation: { Task { await model?.cancel() } })
        .sheet(isPresented: $exporting, onDismiss: {
            Task { await model?.exportFinished(success: false) }
        }) {
            if let document = model?.document {
                BackupFileExporter(document: document) { success in
                    Task { await model?.exportFinished(success: success) }
                    exporting = false
                }
            }
        }
        .sheet(isPresented: $sharing, onDismiss: {
            Task { await model?.exportFinished(success: false) }
        }) {
            if let document = model?.document {
                BackupShareSheet(document: document) { success, failed in
                    sharing = false
                    Task { await model?.exportFinished(success: success, failed: failed) }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard let model else { return }
            if phase == .active { model.sceneBecameActive() }
            else {
                enteredKey = ""; passwordsSaved = false; offlineSaved = false
                if phase == .inactive && model.state == .authenticating {
                    model.shieldForSystemInterruption()
                } else {
                    if model.state != .systemExport {
                        importing = false; exporting = false; sharing = false
                    }
                    Task { await model.sceneBecameInactive() }
                }
            }
        }
        .onDisappear { enteredKey = ""; Task { await model?.cancel() } }
    }

    @ViewBuilder private func content(_ model: RecoveryViewModel) -> some View {
        TaisaText(role: .body, color: .mutedForeground, content: model.storageStatus)
        TaisaText(role: .body, content: "Backups contain your Taisa database only. Recordings and unfinished audio work are excluded. Keep the recovery key separately from the backup.")
        TaisaText(role: .body, content: "Use one authoritative device. Files and AirDrop transfer a copy; changes on your devices are not combined automatically.")
        if let message = model.message {
            TaisaText(role: .body, content: message)
                .accessibilityIdentifier("recovery.message")
        }
        switch model.state {
        case .idle, .success, .failure:
            if model.canResumeCeremony {
                TaisaButton(role: .primary, label: "Unlock Recovery Key Setup") { Task { await model.resumeCeremony() } }
                cancel(model)
            } else {
                TaisaButton(role: .primary, label: "Back Up Now") { Task { await model.beginBackup() } }
                    .disabled(!model.canStart)
                TaisaButton(role: .secondary, label: "Restore Backup") { importing = true }
                    .disabled(!model.canStart)
            }
        case .lockedCeremony:
            TaisaText(role: .body, content: "Unlock to finish saving and verifying your recovery key.")
            TaisaButton(role: .primary, label: "Unlock Recovery Key Setup") { Task { await model.resumeCeremony() } }
            cancel(model)
        case .authenticating, .creating, .validating, .restoring, .systemExport, .finishing:
            TaisaText(role: .body, content: progressLabel(model.state))
                .accessibilityIdentifier("recovery.progress")
            // Text-only progress has no spatial animation, including Reduce Motion.
            TaisaButton(role: .secondary, label: "Cancel") { Task { await model.cancel() } }
                .disabled(model.state == .restoring || model.state == .systemExport || model.state == .finishing)
        case .awaitingKey:
            keyField
            TaisaButton(role: .primary, label: "Continue with Recovery Key") {
                let key = enteredKey; enteredKey = ""
                Task { await model.submitKey(key) }
            }
            if model.canGenerateKey {
                TaisaButton(role: .secondary, label: "Create a Recovery Key") {
                    try? model.generateRecoveryKey()
                }
            }
            cancel(model)
        case .ceremony:
            TaisaText(role: .body, content: RecoverySetupState.manualSaveInstructions)
            if let key = model.ceremonyKey {
                TaisaText(role: .body, content: key)
                    .textSelection(.disabled)
                    .privacySensitive()
                    .accessibilityLabel("Recovery key. Use Copy Recovery Key to save in Passwords and keep an offline copy.")
                TaisaButton(role: .secondary, label: "Copy Recovery Key") {
                    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: key]], options: [
                        .localOnly: true, .expirationDate: Date().addingTimeInterval(120)
                    ])
                }
            }
            Toggle(isOn: $passwordsSaved) { TaisaText(role: .body, content: "I saved the key in Passwords") }
            Toggle(isOn: $offlineSaved) { TaisaText(role: .body, content: "I saved a separate offline copy") }
            keyField
            TaisaButton(role: .primary, label: "Verify Saved Recovery Key") {
                let key = enteredKey; enteredKey = ""
                Task { await model.completeCeremony(enteredKey: key, passwordsSaved: passwordsSaved, offlineSaved: offlineSaved) }
            }
            .disabled(!passwordsSaved || !offlineSaved || enteredKey.isEmpty)
            cancel(model)
        case .exportReady:
            TaisaText(role: .body, content: "Your encrypted backup is ready. Choose where to save or send it.")
            TaisaButton(role: .primary, label: "Export Encrypted Backup") { model.beginSystemExport(); exporting = true }
            TaisaButton(role: .secondary, label: "Send with AirDrop") { model.beginSystemExport(); sharing = true }
            cancel(model)
        case .importSelected:
            TaisaText(role: .body, content: "Backup selected. Authenticate to enter its recovery key.")
            TaisaButton(role: .primary, label: "Unlock Recovery Key Entry") { Task { await model.authenticateImport() } }
            cancel(model)
        case .confirmation:
            TaisaText(role: .heading, content: model.replacementWarning)
                .accessibilityAddTraits(.isHeader)
            TaisaText(role: .body, content: model.divergenceWarning)
            TaisaButton(role: .secondary, label: "Keep Current Data") { Task { await model.confirmRestore(replace: false) } }
            TaisaButton(role: .primary, label: "Replace This Device’s Data") { Task { await model.confirmRestore(replace: true) } }
                .accessibilityHint("Permanently replaces this device’s current Taisa data with the verified backup.")
        }
    }

    private var keyField: some View {
        // Native secure input is the narrowly scoped system-control exception;
        // semantic DS font, color and spacing retain the Taisa visual contract.
        SecureField("Recovery key", text: $enteredKey)
            .font(TaisaTypography.body.font)
            .foregroundStyle(TaisaColor.foreground.color)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .privacySensitive()
            .accessibilityIdentifier("recovery.key")
    }

    private func cancel(_ model: RecoveryViewModel) -> some View {
        TaisaButton(role: .secondary, label: "Cancel") {
            enteredKey = ""; passwordsSaved = false; offlineSaved = false
            Task { await model.cancel() }
        }
    }

    private func progressLabel(_ state: RecoveryViewModel.State) -> String {
        switch state {
        case .authenticating: "Waiting for device authentication…"
        case .creating: "Creating and verifying encrypted backup…"
        case .validating: "Checking backup…"
        case .restoring: "Restoring verified backup…"
        case .systemExport: "Complete or cancel the transfer in the system sheet…"
        case .finishing: "Finishing encrypted backup…"
        default: "Working…"
        }
    }

    private func initialize() async {
        guard model == nil, !initializationFailed else { return }
        do {
            let backend = try PersonalRecoveryBackend.personal()
            _ = try await backend.openStore()
            model = RecoveryViewModel(backend: backend)
        } catch { initializationFailed = true }
    }
}

private struct BackupShareSheet: UIViewControllerRepresentable {
    let document: TaisaBackupDocument
    let completion: @MainActor (Bool, Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [document.shareURL], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            let failed = error != nil
            Task { @MainActor in completion(completed, failed) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
