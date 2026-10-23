import Foundation
import Testing
@testable import TaisaDesignSystem

@Suite("Conversation component contracts")
struct ConversationComponentTests {
    @Test func dockExposesDistinctVoiceAndKeyboardActions() {
        let contract = ConversationEntryDock.Contract.preview
        #expect(contract.voiceAccessibilityLabel == "Talk to Taisa, starts recording")
        #expect(contract.keyboardAccessibilityLabel == "Talk to Taisa with keyboard")
    }

    @Test func disabledDockRemovesTheRecordingGlow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/ConversationEntryDock.swift"),
            encoding: .utf8
        )

        #expect(source.contains("recordingGlow(enabled: !disabled)"))
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
        #expect(TaisaMotion.streamingWordGap == 0.06)
        #expect(TaisaMotion.streamingWordFade == 0.35)
        #expect(TaisaMotion.streamingScrollFollow == 0.35)
        #expect(TaisaMotion.streamingWordRevealCurve.value(at: 0) == 0)
        #expect(TaisaMotion.streamingWordRevealCurve.value(at: 1) == 1)
        #expect(TaisaControlMetric.primaryNavigationItemWidth == 56)
        #expect(TaisaControlMetric.primaryNavigationItemHeight == 48)
        #expect(TaisaControlMetric.standardIcon == 24)
        #expect(TaisaControlMetric.recordingButtonWidth == 104)
        #expect(TaisaControlMetric.recordingButtonHeight == 48)
        #expect(TaisaControlMetric.primaryNavigationReservedHeight == 152)
        #expect(TaisaControlMetric.chatPreviewLineHeight == 20)
        #expect(TaisaTypography.navigationLabel.pointSize == 16)
        #expect(TaisaTypography.navigationLabel.lineHeight == 24)
        #expect(TaisaTypography.supporting.pointSize == 14)
        #expect(TaisaTypography.supporting.lineHeight == 20)
        #expect(TaisaTypography.allCases.contains(.childHeaderTitle))
        #expect(TaisaMotion.activityCycle == 2)
        #expect(TaisaMotion.activityStagger == 0.18)
        #expect(TaisaActivityIndicatorMetric.width == 44)
        #expect(TaisaActivityIndicatorMetric.height == 24)
        #expect(TaisaActivityIndicatorMetric.barWidth == 12)
        #expect(TaisaActivityIndicatorMetric.activeBarHeight == 22)
        #expect(TaisaActivityIndicatorMetric.restingBarHeight == 10)
        #expect(TaisaActivityIndicatorMetric.barSpacing == 2)
        #expect(TaisaActivityIndicatorMetric.barRadius == 3)
        #expect(TaisaColor.activityWarmAccent != TaisaColor.activityCoolAccent)
        #expect(TaisaEffect.recordingGlowBlurRadius == 10)
        #expect(TaisaEffect.recordingGlowSpread == 4)
        #expect(TaisaEffect.recordingGlowOpacity == 0.35)
        #expect(TaisaEffect.edgeFadeBlurOpacity == 0.42)
        #expect(TaisaControlMetric.appBarHeight == 64)
        #expect(TaisaControlMetric.headerActionHeight == 44)
        #expect(TaisaControlMetric.toastMinimumHeight == 44)
        #expect(TaisaRadius.historyGroup.rawValue == 20)
    }

    @Test func streamingTextPreservesWhitespaceAndUsesPerWordResolution() {
        #expect(TaisaStreamingText.chunks(in: "One  two\nthree") == ["One  ", "two\n", "three"])
        #expect(TaisaStreamingText.revealDuration(wordCount: 0) == 0)
        #expect(TaisaStreamingText.revealDuration(wordCount: 3) == 0.47)
        #expect(TaisaStreamingText.Motion.reduced == .instant)
        #expect(TaisaStreamingText.Motion.standard == .softWordResolution)
    }

    @Test func jumpToLatestIsIconOnlyAndKeepsStableGeometryWhileLoading() {
        #expect(ConversationJumpToLatestButton.Contract.size == 48)
        #expect(ConversationJumpToLatestButton.Contract.iconSize == 24)
        #expect(ConversationJumpToLatestButton.Contract.icon == .arrowDown)
        #expect(ConversationJumpToLatestButton.Contract.accessibilityLabel == "Jump to latest response")
        #expect(ConversationJumpToLatestButton.Contract.loadingRingLineWidth == 2)
        #expect(ConversationJumpToLatestButton.Contract.loadingRingStart == 0.08)
        #expect(ConversationJumpToLatestButton.Contract.loadingRingEnd == 0.78)
        #expect(ConversationJumpToLatestButton.Contract.loadingRingInset == 1)
        #expect(ConversationJumpToLatestButton.Contract.loadingRingCycle == 1)
        #expect(ConversationJumpToLatestButton.Contract.loadingRingTracksOuterStroke)
    }

    @Test func restoredVoiceDraftUsesStaticRecordedStatus() {
        #expect(RecordedVoiceDraftBadge.Contract.label == "Recorded")
        #expect(RecordedVoiceDraftBadge.Contract.iconSize == 20)
    }

    @Test func conversationOpeningPlaceholderMatchesFinalPageStructure() {
        #expect(ConversationOpeningPlaceholder.Contract.messageCount == 3)
        #expect(ConversationOpeningPlaceholder.Contract.usesSharedFades)
        #expect(ConversationOpeningPlaceholder.Contract.reduceMotionIsStatic)
    }

    @Test func composerContractsDescribeActionsWithoutColorAlone() {
        #expect(VoiceComposerControls.Contract.recording.pauseLabel == "Pause recording")
        #expect(VoiceComposerControls.Contract.paused.resumeLabel == "Resume recording")
        #expect(ConversationFailureActions.Contract.retryable.retryLabel == "Retry request")
        #expect(TextComposer.Contract.empty.voiceLabel == "Reply by voice, starts recording")
        #expect(InlineRecoveryAlert.Contract.microphonePermission.cancelLabel == "Use keyboard")
        #expect(InlineRecoveryAlert.Contract.responseUpdate.retryLabel == "Try again")
        #expect(InlineRecoveryAlert.Contract.responseUpdate.cancelLabel == "Keep edited message")
        #expect(TaisaButton.Contract.supportsInPlaceProgress)
    }

    @Test func primaryNavigationMotionBeginsWithTheSelectionInteraction() {
        #expect(PrimaryNavigationMotion.transition(reduceMotion: false) == .interactiveSpatial)
        #expect(PrimaryNavigationMotion.transition(reduceMotion: true) == .instant)
    }

    @Test func primaryNavigationIsolatesPillMotionFromPageSelectionWork() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/PrimaryNavigation.swift"),
            encoding: .utf8
        )

        #expect(source.contains("visualSelection"))
        #expect(source.contains("await Task.yield()"))
        #expect(source.contains("transaction.disablesAnimations = true"))
    }

    @Test func centralIconCatalogCoversChatsPageControls() {
        #expect(CentralIconName.magnifyingGlass != .voiceMid)
        #expect(CentralIconName.chevronLeft != .chevronDown)
        #expect(CentralIconName.voiceMid != .chatBubbles)
        #expect(CentralIconName.circleInfo != .thumbsUp)
        #expect(CentralIconName.thumbsUp != .thumbsDown)
        #expect(CentralIconName.copy != .edit)
    }

    @MainActor @Test func figmaEdgeFadesUseMeasuredStops() {
        #expect(PageEdgeFade.fadeStart == 0.40)
        #expect(PageEdgeFade.headerOpaqueStop == 0.56)
        #expect(PageEdgeFade.navigationOpaqueStop == 0.60)
        #expect(TaisaBottomChromeContract.fadeHeight == TaisaControlMetric.primaryNavigationReservedHeight)
        #expect(TaisaBottomChromeContract.coversBottomSafeArea)
        #expect(TaisaControlMetric.childNavigationControlHeight == 48)
    }

    @Test func childPageHeaderUsesTheSharedFadeAndCentralBackControl() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaPageChrome.swift"),
            encoding: .utf8
        )

        #expect(source.contains("public struct TaisaChildPageHeader"))
        #expect(source.contains("icon: .chevronLeft"))
        #expect(source.contains("PageEdgeFade(.header)"))
        #expect(source.contains("TaisaControlMetric.childNavigationControlHeight"))
        #expect(source.contains("case back"))
        #expect(source.contains("case detail"))
    }

    @Test func conversationComposerChromeOwnsTheBottomSafeAreaFade() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaPageChrome.swift"),
            encoding: .utf8
        )

        #expect(source.contains("public struct ConversationComposerChrome"))
        #expect(source.contains("TaisaControlMetric.conversationComposerDockHeight"))
        #expect(source.contains("private let backdrop: Backdrop"))
        #expect(source.contains(".background(alignment: .bottom)"))
        #expect(source.contains("PageEdgeFade(.navigation)"))
        #expect(source.contains(".ignoresSafeArea(edges: [.horizontal, .bottom])"))
    }

    @Test func conversationHeaderAndActionBarMatchFigmaContracts() {
        #expect(TaisaControlMetric.conversationTitleWidth == 220)
        #expect(TaisaControlMetric.conversationRecordingControl == 48)
        #expect(TaisaControlMetric.conversationActionSpacing == 12)
        #expect(ConversationPageHeader.Contract.usesSharedHeaderFade)
        #expect(ConversationPageHeader.Contract.dismissPlacement == .leading)
        #expect(ConversationActionBar.Availability.recording.canDiscard)
        #expect(ConversationActionBar.Availability.preparing.canSwitchToKeyboard)
        #expect(ConversationActionBar.Availability.preparing.showsPause)
        #expect(ConversationActionBar.Availability.preparing.primaryLabel == "Pause")
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
        #expect(TextComposer.Contract.emptyActionHierarchy == .secondary)
        #expect(TextComposer.Contract.filledActionHierarchy == .primary)
        #expect(TextComposer.Contract.centersSingleLineTextWithAction)
        #expect(InlineRecoveryAlert.Contract.alwaysFillsAvailableWidth)
        #expect(InlineRecoveryAlert.Contract.stackedActionsFillAvailableWidth)
        #expect(InlineRecoveryAlert.Contract.actionHeight == 48)
        #expect(InlineRecoveryAlert.Contract.actionSpacing == 12)
    }

    @Test func recordingControlsUseShadowedClearGlassWithATintedCircularSendControl() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let actionBar = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/ConversationActionBar.swift"),
            encoding: .utf8
        )
        let chrome = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaPageChrome.swift"),
            encoding: .utf8
        )
        let tokens = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/SpacingToken.swift"),
            encoding: .utf8
        )

        #expect(chrome.contains("public enum TaisaGlassStyle"))
        #expect(chrome.contains("case regular"))
        #expect(chrome.contains("case clear"))
        #expect(chrome.contains(".glassEffect(.clear.interactive(), in: Circle())"))
        #expect(!chrome.contains("Circle().stroke(TaisaColor.border.color)"))
        #expect(!chrome.contains("Capsule().stroke(TaisaColor.border.color)"))
        #expect(chrome.contains("TaisaEffect.clearGlassShadowOpacity"))
        #expect(chrome.contains("TaisaEffect.clearGlassShadowRadius"))
        #expect(chrome.contains("TaisaEffect.clearGlassShadowOffsetY"))
        #expect(tokens.contains("public static let clearGlassShadowOpacity"))
        #expect(tokens.contains("public static let clearGlassShadowRadius"))
        #expect(tokens.contains("public static let clearGlassShadowOffsetY"))
        #expect(actionBar.contains("glassStyle: .clear"))
        #expect(actionBar.contains(".glassEffect(.clear.tint(TaisaColor.primaryAction.color).interactive(), in: Circle())"))
        #expect(!actionBar.contains(".buttonStyle(.glassProminent)"))
    }

    @Test func conversationMetricsNameEveryReviewedProductRole() {
        #expect(TaisaControlMetric.contextMenuIcon == 16)
        #expect(TaisaControlMetric.conversationEmptyVoiceIcon == 24)
        #expect(TaisaControlMetric.messageEditorMinimumHeight == 120)
        #expect(TaisaControlMetric.disabledControlOpacity > 0)
        #expect(TaisaControlMetric.disabledControlOpacity < 1)
    }

    @MainActor @Test func conversationActivityAndRecoveryRemainAccessible() {
        #expect(ConversationActivityIndicator.animationDuration == 2)
        #expect(ConversationActivityIndicator.Motion.reduced == .staticFrame)
        #expect(InlineRecoveryAlert.Contract.transcription.title == "Couldn’t transcribe recording")
        #expect(InlineRecoveryAlert.Contract.transcription.message == "Your recording is saved. Try again now or keep it for later.")
        #expect(InlineRecoveryAlert.Contract.transcription.retryLabel == "Try again")
        #expect(InlineRecoveryAlert.Contract.transcription.cancelLabel == "Keep for later")
        #expect(InlineRecoveryAlert.Contract.request.title == "Couldn’t get a response")
        #expect(InlineRecoveryAlert.Contract.request.message == "Your message is saved. Try again now or continue later.")
        #expect(InlineRecoveryAlert.Contract.request.cancelLabel == "Continue later")
        #expect(InlineRecoveryAlert.Contract.request.retryLabel == "Try again")
        #expect(InlineRecoveryAlert.Contract.beginRecording.title == "Couldn’t start recording")
        #expect(InlineRecoveryAlert.Contract.beginRecording.message == "No audio was captured. Try again or type instead.")
        #expect(InlineRecoveryAlert.Contract.beginRecording.cancelLabel == "Use keyboard")
        #expect(InlineRecoveryAlert.Contract.beginRecording.retryLabel == "Try again")
        #expect(InlineRecoveryAlert.Contract.microphonePermission.title == "Microphone access needed")
        #expect(InlineRecoveryAlert.Contract.microphonePermission.message == "Allow access in Settings to record, or type instead.")
        #expect(InlineRecoveryAlert.Contract.microphonePermission.retryLabel == "Open Settings")
        #expect(InlineRecoveryAlert.Contract.pauseRecording.title == "Couldn’t pause recording")
        #expect(InlineRecoveryAlert.Contract.pauseRecording.message == "Recording may still be active. Try again or discard it.")
        #expect(InlineRecoveryAlert.Contract.pauseRecording.cancelLabel == "Discard recording")
        #expect(InlineRecoveryAlert.Contract.pauseRecording.retryLabel == "Try again")
        #expect(InlineRecoveryAlert.Contract.resumeRecording.title == "Couldn’t resume recording")
        #expect(InlineRecoveryAlert.Contract.resumeRecording.cancelLabel == "Save draft")
        #expect(InlineRecoveryAlert.Contract.resumeRecording.retryLabel == "Try again")
        #expect(TextComposer.Contract.empty.placeholder == "Reply")
        #expect(TextComposer.Mode.processing.acceptsInput == false)
    }

    @Test func centralIconCatalogCoversConversationDetailsControls() {
        #expect(CentralIconName.cross != .keyboard)
        #expect(CentralIconName.arrowUp != .pause)
        #expect(CentralIconName.play != .chevronDown)
    }

    @Test func responseActionsUseSharedSemanticControls() {
        #expect(ResponseActionIconButton.Contract.iconSize == 16)
        #expect(ResponseActionIconButton.Contract.visualWidth == 24)
        #expect(ResponseActionIconButton.Contract.minimumHitHeight == 44)
        #expect(SelectableChip.Contract.minimumHeight == 44)
        #expect(FeedbackTextEditor.Contract.minimumHeight == 112)
        #expect(ActionPanelContract.usesRaisedSurface)
        #expect(TaisaButtonRole.destructive != .secondary)
    }

    @Test func toastContractIsTopPlacedAndAccessible() {
        #expect(TaisaToast.Contract.default.placement == .top)
        #expect(TaisaToast.Contract.default.dismissAfter == 4)
        #expect(TaisaToast.Contract.default.swipeDirection == .up)
        #expect(TaisaToast.Contract.default.announcesWithVoiceOver)
    }
}
