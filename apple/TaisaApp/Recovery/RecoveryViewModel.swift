import Foundation
import LocalAuthentication
import Observation
import TaisaRecovery
import TaisaSecurity

@MainActor @Observable
final class RecoveryViewModel {
    enum State: Equatable { case idle, authenticating, awaitingKey, ceremony, lockedCeremony, creating, exportReady, finishing, importSelected, validating, confirmation, restoring, success, failure }
    private(set) var state: State = .idle
    private(set) var message: String?
    private(set) var document: TaisaBackupDocument?
    private(set) var ceremonyKey: String?
    private(set) var isShielded = false
    let storageStatus = "Stored securely on this device"
    let replacementWarning = "Restoring replaces this device’s current Taisa data"
    let divergenceWarning = "Changes made independently on this device, including newer changes, will be lost. Choose one authoritative device and avoid editing both copies between transfers."
    private let backend: PersonalRecoveryBackend
    private let authenticate: @MainActor () async throws -> Bool
    private var restoring = false
    private var generation = UUID()
    private var operation: Task<Void, Never>?
    private var setup: RecoverySetupState?
    private var pendingAuthentication: Bool?
    private var suspendedKey: RecoveryKey?
    private var suspendedSetup: RecoverySetupState?

    init(backend: PersonalRecoveryBackend, authenticate: @escaping @MainActor () async throws -> Bool = RecoveryViewModel.deviceAuthentication) {
        self.backend = backend; self.authenticate = authenticate
    }

    var isBusy: Bool { [.authenticating, .creating, .validating, .restoring, .finishing].contains(state) || operation != nil }
    var acceptsKey: Bool { !isShielded && state == .awaitingKey }
    var canGenerateKey: Bool { acceptsKey && !restoring }
    var canResumeCeremony: Bool { suspendedKey != nil && [.lockedCeremony, .failure].contains(state) && !isShielded }
    var canStart: Bool {
        !isBusy && !isShielded && suspendedKey == nil && [.idle, .success, .failure].contains(state)
    }

    static func deviceAuthentication() async throws -> Bool {
        let context = LAContext()
        defer { context.invalidate() }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication,
            localizedReason: "Use your Taisa recovery key for an encrypted backup.")
    }

    func beginBackup() async {
        guard canStart else { return }
        restoring = false
        await authenticateKey()
    }

    func selectImport(_ url: URL) async {
        guard canStart else { return }
        message = nil; restoring = true; state = .validating
        await perform {
            do { try await self.backend.copyImport(url); self.state = .importSelected }
            catch { self.fail("This backup could not be opened. Choose the file again.") }
        }
    }

    func authenticateImport() async {
        guard state == .importSelected, !isShielded else { return }
        await authenticateKey()
    }

    private func authenticateKey() async {
        state = .authenticating; message = nil
        let token = generation
        do {
            let accepted = try await authenticate()
            guard token == generation else { return }
            guard accepted else { throw CancellationError() }
            if isShielded { pendingAuthentication = true; return }
            acceptAuthentication()
        } catch {
            guard token == generation else { return }
            try? await backend.cleanup()
            fail("Device authentication is required. Try again when you’re ready.")
        }
    }

    func submitKey(_ text: String) async {
        guard acceptsKey, !isBusy else { return }
        let key: RecoveryKey
        do { key = try RecoveryKey(validating: text) }
        catch { message = "Check your recovery key and try again."; return }
        await process(key)
    }

    func generateRecoveryKey() throws {
        guard acceptsKey, !restoring else { return }
        let key = try RecoveryKey.generate()
        var setup = RecoverySetupState(recoveryKey: key)
        setup.recordSaveResult(.manualSaveRequired(.sdkOrDomainUnavailable))
        self.setup = setup; ceremonyKey = key.formatted; state = .ceremony
    }

    func resumeCeremony() async {
        guard canResumeCeremony else { return }
        await authenticateKey()
    }

    private func acceptAuthentication() {
        if let suspendedKey, let suspendedSetup {
            ceremonyKey = suspendedKey.formatted; setup = suspendedSetup
            self.suspendedKey = nil; self.suspendedSetup = nil
            state = .ceremony
        } else { state = .awaitingKey }
    }

    func completeCeremony(enteredKey: String, passwordsSaved: Bool, offlineSaved: Bool) async {
        guard state == .ceremony, !isShielded, var setup else { return }
        guard passwordsSaved, offlineSaved else { message = "Save both copies before continuing."; return }
        setup.confirmManualCopy(); setup.confirmManualPasswordsSave(); setup.confirmOfflineCopy()
        do {
            try setup.verifyRecoveryKey(enteredKey)
            guard setup.canEnableSync else { return }
            let key = try RecoveryKey(validating: enteredKey)
            self.setup = nil; ceremonyKey = nil
            await process(key)
        } catch { message = "The key did not match. Check your saved copy and try again." }
    }

    private func process(_ key: RecoveryKey) async {
        message = nil; state = restoring ? .validating : .creating
        await perform {
            do {
                if self.restoring {
                    try await self.backend.validate(key: key)
                    try Task.checkCancellation()
                    self.state = .confirmation
                } else {
                    let document = try await self.backend.createBackup(key: key)
                    try Task.checkCancellation()
                    self.document = document
                    self.state = .exportReady
                }
            } catch is CancellationError { self.state = .idle }
            catch SnapshotError.authenticationFailed {
                self.state = .awaitingKey
                self.message = "The key could not open this backup. Check the key or choose another backup."
            } catch SnapshotError.pendingAudio {
                self.fail("Finish or discard audio-dependent work before creating a backup.")
            } catch {
                try? await self.backend.cleanup()
                self.fail("The backup could not be completed. Your current data has been preserved.")
            }
        }
    }

    func confirmRestore(replace: Bool) async {
        guard state == .confirmation, !isBusy, !isShielded else { return }
        guard replace else { await cancel(); return }
        state = .restoring
        await perform {
            do {
                try await self.backend.promote(confirmed: replace)
                try await self.backend.cleanup()
                self.state = .success; self.message = "Backup restored. Stored securely on this device."
            } catch {
                try? await self.backend.cleanup()
                self.fail("Restore could not finish. Reopen Taisa to recover safely before trying again.")
            }
        }
    }

    func exportFinished(success: Bool, failed: Bool = false) async {
        guard state == .exportReady else { return }
        state = .finishing
        document = nil
        do {
            try await backend.cleanup()
            state = success ? .success : (failed ? .failure : .idle)
            message = success ? "Encrypted backup exported. Keep your recovery key separately."
                : (failed ? "Encrypted backup export failed. Create a backup and try again." : nil)
        } catch { fail("Temporary backup cleanup could not finish. Reopen Taisa before trying again.") }
    }

    func cancel() async {
        if state == .restoring { await operation?.value; return }
        generation = UUID(); pendingAuthentication = nil; setup = nil; ceremonyKey = nil; document = nil
        suspendedKey = nil; suspendedSetup = nil
        let pending = operation
        pending?.cancel()
        await pending?.value
        operation = nil
        document = nil; ceremonyKey = nil; setup = nil
        do { try await backend.cleanup(); state = .idle; message = nil }
        catch { fail("Recovery cleanup could not finish. Reopen Taisa before trying again.") }
    }

    func sceneBecameInactive() async {
        isShielded = true
        // Once replacement is explicitly confirmed, let the journaled operation
        // settle and retain its truthful outcome. Backgrounding is not a second
        // replacement decision; the coordinator handles interruption recovery.
        if state == .restoring { return }
        // Manual Passwords saving requires leaving the app. Retain only opaque
        // security values in memory; showing them again requires fresh device auth.
        let savedKey = suspendedKey ?? ceremonyKey.flatMap { try? RecoveryKey(validating: $0) }
        let savedSetup = suspendedSetup ?? setup
        await cancel()
        if let savedKey, let savedSetup {
            suspendedKey = savedKey; suspendedSetup = savedSetup; state = .lockedCeremony
        }
    }
    // LocalAuthentication itself makes the scene inactive. No key is present at
    // that point; defer acceptance until active, but backgrounding still cancels.
    func shieldForSystemInterruption() { isShielded = true }
    func sceneBecameActive() {
        isShielded = false
        if let pendingAuthentication {
            self.pendingAuthentication = nil
            if pendingAuthentication { acceptAuthentication() }
            else { fail("Device authentication is required. Try again when you’re ready.") }
        }
    }

    private func perform(_ body: @escaping @MainActor () async -> Void) async {
        let task = Task { await body() }
        operation = task
        await task.value
        operation = nil
        if isShielded { document = nil; ceremonyKey = nil; setup = nil }
    }

    private func fail(_ message: String) { state = .failure; self.message = message }
}
