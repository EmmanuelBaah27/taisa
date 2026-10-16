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
        #expect(TaisaColor.inactiveForeground.hex == "#898989")
        #expect(TaisaRadius.composer.rawValue == 24)
        #expect(TaisaMaterial.composer.reducedTransparencyFallback == .raisedSurface)
        #expect(TaisaSpacing.control.rawValue == 12)
        #expect(TaisaMotion.fast == 0.18)
        #expect(TaisaMotion.settle == 0.50)
        #expect(TaisaControlMetric.primaryNavigationItemWidth == 56)
        #expect(TaisaControlMetric.primaryNavigationItemHeight == 48)
        #expect(TaisaControlMetric.standardIcon == 24)
        #expect(TaisaControlMetric.recordingButtonWidth == 104)
        #expect(TaisaControlMetric.recordingButtonHeight == 48)
        #expect(TaisaControlMetric.primaryNavigationReservedHeight == 152)
        #expect(TaisaControlMetric.chatPreviewLineHeight == 20)
        #expect(TaisaTypography.navigationLabel.pointSize == 16)
        #expect(TaisaTypography.navigationLabel.lineHeight == 24)
        #expect(TaisaEffect.recordingGlowBlurRadius == 10)
        #expect(TaisaEffect.recordingGlowSpread == 4)
        #expect(TaisaEffect.recordingGlowOpacity == 0.35)
        #expect(TaisaEffect.edgeFadeBlurOpacity == 0.42)
        #expect(TaisaControlMetric.appBarHeight == 64)
        #expect(TaisaControlMetric.headerActionHeight == 44)
        #expect(TaisaRadius.historyGroup.rawValue == 20)
    }

    @Test func composerContractsDescribeActionsWithoutColorAlone() {
        #expect(VoiceComposerControls.Contract.recording.pauseLabel == "Pause recording")
        #expect(VoiceComposerControls.Contract.paused.resumeLabel == "Resume recording")
        #expect(ConversationFailureActions.Contract.retryable.retryLabel == "Retry request")
        #expect(TextComposer.Contract.empty.voiceLabel == "Reply by voice, starts recording")
        #expect(InlineRecoveryAlert.Contract.microphonePermission.cancelLabel == "Use keyboard")
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
        #expect(PageEdgeFade.fadeStart == 0.40)
        #expect(PageEdgeFade.headerOpaqueStop == 0.40)
        #expect(PageEdgeFade.navigationOpaqueStop == 0.60)
    }

    @Test func conversationHeaderAndActionBarMatchFigmaContracts() {
        #expect(TaisaControlMetric.conversationTitleWidth == 220)
        #expect(TaisaControlMetric.conversationRecordingControl == 48)
        #expect(TaisaControlMetric.conversationActionSpacing == 12)
        #expect(ConversationPageHeader.Contract.usesSharedHeaderFade)
        #expect(ConversationPageHeader.Contract.dismissPlacement == .leading)
        #expect(ConversationActionBar.Availability.recording.canDiscard)
        #expect(ConversationActionBar.Availability.preparing.canSwitchToKeyboard)
        #expect(ConversationActionBar.Availability.recording.canSwitchToKeyboard)
        #expect(ConversationActionBar.Availability.recording.showsSend)
        #expect(ConversationActionBar.Availability.recording.canSend == false)
        #expect(ConversationActionBar.Availability.shortCapture.showsSend)
        #expect(ConversationActionBar.Availability.shortCapture.canSend == false)
        #expect(ConversationActionBar.Availability.sendable.showsSend)
        #expect(ConversationActionBar.Availability.sendable.canSend)
        #expect(ConversationActionBar.Availability.pausedEmpty.canSend == false)
        #expect(ConversationActionBar.Availability.pausedShort.canSend == false)
        #expect(ConversationActionBar.Availability.paused.primaryLabel == "Resume")
        #expect(ConversationActionBar.Availability.saved.canSwitchToKeyboard == false)
        #expect(ConversationActionBar.Availability.saved.canResume == false)
        #expect(ConversationActionBar.Availability.waitingForReply.canDiscard == false)
        #expect(TaisaButtonShape.roundedRectangle != .capsule)
        #expect(TextComposer.Contract.usesLiquidEditorSurface)
        #expect(TextComposer.Contract.minimumHeight == 48)
        #expect(TextComposer.Contract.focusesOnEntry)
    }

    @MainActor @Test func conversationActivityAndRecoveryRemainAccessible() {
        #expect(ConversationActivityIndicator.animationDuration == 2)
        #expect(ConversationActivityIndicator.Motion.reduced == .staticFrame)
        #expect(InlineRecoveryAlert.Contract.transcription.retryLabel == "Try again")
        #expect(InlineRecoveryAlert.Contract.transcription.cancelLabel == "Cancel")
        #expect(InlineRecoveryAlert.Contract.request.title == "Taisa couldn’t respond")
        #expect(InlineRecoveryAlert.Contract.request.message == "Your message is saved. Try again now or continue later.")
        #expect(InlineRecoveryAlert.Contract.request.cancelLabel == "Continue later")
        #expect(InlineRecoveryAlert.Contract.beginRecording.title == "Recording didn’t start")
        #expect(InlineRecoveryAlert.Contract.beginRecording.message == "Nothing was recorded. Try again or use the keyboard.")
        #expect(InlineRecoveryAlert.Contract.beginRecording.cancelLabel == "Use keyboard")
        #expect(InlineRecoveryAlert.Contract.microphonePermission.title == "Taisa needs microphone access")
        #expect(InlineRecoveryAlert.Contract.microphonePermission.retryLabel == "Open Settings")
        #expect(InlineRecoveryAlert.Contract.pauseRecording.cancelLabel == "Discard recording")
        #expect(InlineRecoveryAlert.Contract.resumeRecording.cancelLabel == "Save draft")
        #expect(TextComposer.Contract.empty.placeholder == "Reply")
        #expect(TextComposer.Mode.processing.acceptsInput == false)
    }

    @Test func centralIconCatalogCoversConversationDetailsControls() {
        #expect(CentralIconName.cross != .keyboard)
        #expect(CentralIconName.arrowUp != .pause)
        #expect(CentralIconName.play != .chevronDown)
    }

    @Test func toastContractIsTopPlacedAndAccessible() {
        #expect(TaisaToast.Contract.default.placement == .top)
        #expect(TaisaToast.Contract.default.dismissAfter == 4)
        #expect(TaisaToast.Contract.default.swipeDirection == .up)
        #expect(TaisaToast.Contract.default.announcesWithVoiceOver)
    }
}
