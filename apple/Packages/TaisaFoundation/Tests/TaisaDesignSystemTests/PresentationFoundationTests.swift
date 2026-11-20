import Foundation
import Testing
@testable import TaisaDesignSystem

@Suite("Native presentation foundation")
struct PresentationFoundationTests {
    @Test func resultsRequireExplicitSuccessBeforeDismissal() {
        #expect(TaisaPresentationResult.success.shouldDismiss)
        #expect(!TaisaPresentationResult.failure.shouldDismiss)
        #expect(!TaisaPresentationResult.cancelled.shouldDismiss)
    }

    @Test func actionsBlockDisabledBusyAndRepeatedSubmission() async {
        let gate = await MainActor.run { TaisaPresentationActionGate() }

        #expect(await gate.finish(with: .success) == false)
        #expect(await gate.begin(isEnabled: false) == false)
        #expect(await gate.begin(isEnabled: true))
        #expect(await gate.begin(isEnabled: true) == false)
        #expect(await gate.finish(with: .failure) == false)
        #expect(await gate.begin(isEnabled: true))
        #expect(await gate.finish(with: .success))
    }

    @Test func editorAndTaskPoliciesRetainMountedContentOnFailure() {
        let editor = TaisaEditorSheetPolicy(isDirty: true, isBusy: false)
        let busyTask = TaisaTaskSheetPolicy(isBusy: true)

        #expect(editor.blocksInteractiveDismissal)
        #expect(editor.keepsContentMounted(after: .failure))
        #expect(busyTask.blocksInteractiveDismissal)
        #expect(busyTask.keepsContentMounted(after: .failure))
    }

    @Test func informationPolicyLeavesNativeDismissalAvailable() {
        #expect(!TaisaInformationSheetPolicy.default.blocksInteractiveDismissal)
    }

    @Test func immersiveCommitStaysVisibleUntilRouteDismissal() {
        #expect(TaisaImmersivePresentationPhase.active.keepsContentVisible)
        #expect(TaisaImmersivePresentationPhase.committing.keepsContentVisible)
        #expect(!TaisaImmersivePresentationPhase.dismissed.keepsContentVisible)
        #expect(!TaisaImmersivePresentationPhase.committing.allowsCloseRequest)
    }

    @Test func systemTransferAcceptsOnlyItsFirstTerminalCallback() async {
        let policy = await MainActor.run { TaisaSystemTransferPolicy() }

        #expect(await policy.complete(with: .success))
        #expect(await policy.complete(with: .cancelled) == false)
        #expect(await policy.result == .success)
    }

    @Test func dialogContractsKeepNativePresentersSeparate() {
        #expect(TaisaConfirmationDialogPolicy.destructive.kind == .confirmation)
        #expect(TaisaTextEntryAlertPolicy.standard.kind == .textEntry)
        #expect(TaisaTextEntryAlertPolicy.standard.keepsTextMounted(after: .failure))
        #expect(!TaisaTextEntryAlertPolicy.standard.keepsTextMounted(after: .success))
        #expect(TaisaPresentationAction(label: "Delete", role: .destructive).canInvoke)
        #expect(!TaisaPresentationAction(label: "Save", role: .primary, isBusy: true).canInvoke)
    }

    @Test func contractsPreserveAppleOwnedPresentationAndMotion() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sheets = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaPresentationSheets.swift"),
            encoding: .utf8
        )
        let dialogs = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaPresentationDialogs.swift"),
            encoding: .utf8
        )

        #expect(!sheets.contains(".sheet("))
        #expect(!sheets.contains("DragGesture"))
        #expect(!sheets.contains("withAnimation"))
        #expect(sheets.contains(".interactiveDismissDisabled"))
        #expect(dialogs.contains(".confirmationDialog("))
        #expect(dialogs.contains(".alert("))
    }
}
