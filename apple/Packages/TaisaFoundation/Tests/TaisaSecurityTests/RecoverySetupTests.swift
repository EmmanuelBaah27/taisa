import Foundation
import Testing
@testable import TaisaSecurity

@Suite struct RecoverySetupTests {
    @Test func manualPathRequiresCopySaveOfflineAndVerification() async throws {
        let key = try RecoveryKey.generate()
        let saver = SystemPasswordsSaver()
        let result = try await saver.save(recoveryKey: key)
        #expect(result == .manualSaveRequired(.sdkOrDomainUnavailable))
        var setup = RecoverySetupState(recoveryKey: key)
        setup.recordSaveResult(result)
        #expect(!setup.canEnableSync)
        setup.confirmManualCopy()
        setup.confirmManualPasswordsSave()
        #expect(!setup.canEnableSync)
        setup.confirmOfflineCopy()
        #expect(!setup.canEnableSync)
        try setup.verifyRecoveryKey(key.formatted)
        #expect(setup.canEnableSync)
    }

    @Test func preferredSaveStillRequiresOfflineCopyAndVerification() throws {
        let key = try RecoveryKey.generate()
        var setup = RecoverySetupState(recoveryKey: key)
        setup.recordSaveResult(.savedToPasswords)
        #expect(!setup.canEnableSync)
        setup.confirmOfflineCopy()
        #expect(!setup.canEnableSync)
        #expect(throws: VaultError.wrongRecoveryKey) { try setup.verifyRecoveryKey(try RecoveryKey.generate().formatted) }
        #expect(!setup.canEnableSync)
        try setup.verifyRecoveryKey(key.formatted)
        #expect(setup.canEnableSync)
    }

    @Test func manualSaveCannotBeConfirmedWithoutCopy() throws {
        let key = try RecoveryKey.generate()
        var setup = RecoverySetupState(recoveryKey: key)
        setup.recordSaveResult(.manualSaveRequired(.userDeclined))
        setup.confirmManualPasswordsSave()
        setup.confirmOfflineCopy()
        try setup.verifyRecoveryKey(key.formatted)
        #expect(!setup.canEnableSync)
        setup.confirmManualCopy()
        setup.confirmManualPasswordsSave()
        #expect(setup.canEnableSync)
    }
}
