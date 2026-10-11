import Testing
@testable import TaisaDesignSystem

@Suite("Conversation component contracts")
struct ConversationComponentTests {
    @Test func dockExposesDistinctVoiceAndKeyboardActions() {
        let contract = ConversationEntryDock.Contract.preview
        #expect(contract.voiceAccessibilityLabel == "Talk to Taisa, starts recording")
        #expect(contract.keyboardAccessibilityLabel == "Talk to Taisa with keyboard")
    }

    @Test func conversationTokensCoverRequiredSemanticRoles() {
        #expect(TaisaColor.destructive.hex == "#C60000")
        #expect(TaisaColor.warning.hex == "#E46300")
        #expect(TaisaColor.raisedSurface.hex == "#F9F9F9")
        #expect(TaisaRadius.composer.rawValue == 24)
        #expect(TaisaMaterial.composer.reducedTransparencyFallback == .raisedSurface)
    }

    @Test func composerContractsDescribeActionsWithoutColorAlone() {
        #expect(VoiceComposerControls.Contract.recording.pauseLabel == "Pause recording")
        #expect(VoiceComposerControls.Contract.paused.resumeLabel == "Resume recording")
        #expect(ConversationFailureActions.Contract.retryable.retryLabel == "Retry request")
        #expect(TextComposer.Contract.empty.voiceLabel == "Reply by voice, starts recording")
    }
}
