import Foundation

/// In-memory ceremony state. Only the two explicit storage confirmations and
/// a re-entered key verification may unlock sync; none of these is persisted here.
public struct RecoverySetupState: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let manualSaveInstructions =
        "Copy the recovery key, create a new entry in Passwords, paste the key there, " +
        "and make a separate offline copy. Then confirm both copies and re-enter the key."

    private let recoveryKey: RecoveryKey
    private var saveResult: PasswordSaveResult?
    private var manuallyCopied = false
    private var manualPasswordsSaveConfirmed = false
    private var offlineCopyConfirmed = false
    private var recoveryVerified = false

    public init(recoveryKey: RecoveryKey) { self.recoveryKey = recoveryKey }

    public var needsManualSave: Bool {
        if case .manualSaveRequired = saveResult { return true }
        return false
    }

    public var canEnableSync: Bool {
        let passwordsConfirmed: Bool
        switch saveResult {
        case .savedToPasswords: passwordsConfirmed = true
        case .manualSaveRequired: passwordsConfirmed = manuallyCopied && manualPasswordsSaveConfirmed
        case nil: passwordsConfirmed = false
        }
        return passwordsConfirmed && offlineCopyConfirmed && recoveryVerified
    }

    public mutating func recordSaveResult(_ result: PasswordSaveResult) {
        saveResult = result
        manuallyCopied = false
        manualPasswordsSaveConfirmed = false
        recoveryVerified = false
    }

    public mutating func confirmManualCopy() {
        guard needsManualSave else { return }
        manuallyCopied = true
    }

    public mutating func confirmManualPasswordsSave() {
        guard needsManualSave, manuallyCopied else { return }
        manualPasswordsSaveConfirmed = true
    }

    public mutating func confirmOfflineCopy() { offlineCopyConfirmed = true }

    public mutating func verifyRecoveryKey(_ enteredText: String) throws {
        recoveryVerified = false
        let entered = try RecoveryKey(validating: enteredText)
        guard recoveryKey.matches(entered) else { throw VaultError.wrongRecoveryKey }
        recoveryVerified = true
    }

    private var diagnosticState: String {
        if canEnableSync { return "ready" }
        if needsManualSave { return "manual-save-required" }
        return "awaiting-confirmation"
    }

    public var description: String { "<recovery setup: \(diagnosticState)>" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["state": diagnosticState], displayStyle: .struct)
    }
}
