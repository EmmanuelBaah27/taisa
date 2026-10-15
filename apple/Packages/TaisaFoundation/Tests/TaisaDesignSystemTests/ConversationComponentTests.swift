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
        #expect(TaisaSpacing.control.rawValue == 12)
        #expect(TaisaMotion.fast == 0.18)
        #expect(TaisaControlMetric.primaryNavigationItemWidth == 56)
        #expect(TaisaControlMetric.primaryNavigationItemHeight == 48)
        #expect(TaisaControlMetric.standardIcon == 24)
        #expect(TaisaControlMetric.recordingButtonWidth == 48)
        #expect(TaisaControlMetric.recordingButtonHeight == 48)
        #expect(TaisaTypography.navigationLabel.pointSize == 16)
        #expect(TaisaTypography.navigationLabel.lineHeight == 24)
        #expect(TaisaEffect.recordingGlowBlurRadius == 10)
        #expect(TaisaEffect.recordingGlowSpread == 4)
        #expect(TaisaEffect.recordingGlowOpacity == 0.35)
        #expect(TaisaRadius.historyGroup.rawValue == 20)
    }

    @Test func composerContractsDescribeActionsWithoutColorAlone() {
        #expect(VoiceComposerControls.Contract.recording.pauseLabel == "Pause recording")
        #expect(VoiceComposerControls.Contract.paused.resumeLabel == "Resume recording")
        #expect(ConversationFailureActions.Contract.retryable.retryLabel == "Retry request")
        #expect(TextComposer.Contract.empty.voiceLabel == "Reply by voice, starts recording")
    }

    @Test func primaryNavigationMotionFallsBackToAnInstantAccessibleTransition() {
        #expect(PrimaryNavigationMotion.transition(reduceMotion: false) == .spatial)
        #expect(PrimaryNavigationMotion.transition(reduceMotion: true) == .instant)
    }

    @Test func centralIconCatalogCoversChatsPageControls() {
        #expect(CentralIconName.magnifyingGlass != .voiceMid)
        #expect(CentralIconName.voiceMid != .chatBubbles)
    }

    @MainActor @Test func figmaEdgeFadesUseMeasuredStops() {
        #expect(PageEdgeFade.headerOpaqueStop == 0.70)
        #expect(PageEdgeFade.navigationOpaqueStop == 0.54565)
    }
}
