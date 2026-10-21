import Foundation
import XCTest
@testable import Taisa

final class ConversationViewContractTests: XCTestCase {
    func testConversationOpenFailureReportsAContentFreeStage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversation/ConversationRuntimeFactory.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("enum ConversationOpenStage: String"))
        XCTAssertTrue(source.contains("conversation.unavailable.diagnostic"))
        XCTAssertTrue(source.contains("openStage(.resumableTurn)"))
        XCTAssertTrue(source.contains("TAISA_CONVERSATION_OPEN_FAILURE stage="))
        XCTAssertFalse(source.contains("error.localizedDescription"))
    }

    func testConversationOpeningUsesLayoutMatchingPlaceholder() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let runtimeSource = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversation/ConversationRuntimeFactory.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(runtimeSource.contains("ConversationOpeningPlaceholder"))
        XCTAssertFalse(runtimeSource.contains("ProgressView(\"Opening conversation…\")"))
    }

    func testLatestDraftDiagnosticReportsOnlyContentFreeFields() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let factory = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversation/ConversationRuntimeFactory.swift"),
            encoding: .utf8
        )
        let appRoot = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/App/AppRootView.swift"),
            encoding: .utf8
        )
        let diagnosticStart = try XCTUnwrap(factory.range(of: "func contentFreeLatestDraftDiagnostic"))
        let remainder = factory[diagnosticStart.lowerBound...]
        let diagnosticEnd = try XCTUnwrap(remainder.range(of: "\n    func makeModel"))
        let diagnostic = String(remainder[..<diagnosticEnd.lowerBound])

        XCTAssertTrue(factory.contains("contentFreeLatestDraftDiagnostic"))
        XCTAssertTrue(diagnostic.contains("state=\\(turn.state.rawValue) stage=\\(turn.stage.rawValue) failure=\\(turn.failureCode ?? \"none\")"))
        XCTAssertTrue(diagnostic.contains("reconciliation=\\(status)"))
        XCTAssertTrue(diagnostic.contains("case .safeToRetry: status = \"safe-to-retry\""))
        XCTAssertTrue(diagnostic.contains("case .completed: status = \"completed\""))
        XCTAssertFalse(diagnostic.contains("acceptedTranscript"))
        XCTAssertFalse(appRoot.contains("TAISA_CONVERSATION_DRAFT_DIAGNOSTIC \\(requestID)"))
        XCTAssertTrue(appRoot.contains("--taisa-diagnose-latest-preserved-draft"))
        XCTAssertTrue(appRoot.contains("TAISA_CONVERSATION_DRAFT_DIAGNOSTIC"))
        XCTAssertTrue(appRoot.contains("--taisa-retry-latest-preserved-draft-once"))
        XCTAssertTrue(appRoot.contains("TAISA_CONVERSATION_RETRY_PROBE"))
        XCTAssertTrue(factory.contains("retryLatestPreservedDraftProbe"))
        XCTAssertTrue(factory.contains("await model.retry()"))
        XCTAssertTrue(appRoot.contains("--taisa-cleanup-completed-preserved-draft"))
        XCTAssertTrue(appRoot.contains("TAISA_CONVERSATION_CLEANUP_PROBE"))
        XCTAssertTrue(factory.contains("cleanupCompletedPreservedDraftProbe"))
    }

    func testLegacyVoiceDraftDecodeFailureFallsThroughToTranscriptRecovery() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversation/ConversationRuntimeFactory.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let voiceTurn = try? await turns.turn(id: voiceTurnID)"))
        XCTAssertTrue(source.contains("linkedVoiceTurn = try? await turns.turn(id: voiceTurnID)"))
        XCTAssertTrue(source.contains("recoveryTranscript: recoveryTranscript ?? lastUserMessage?.body"))
    }

    func testConversationScreenExposesRequiredNativeInteractionContracts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("TaisaApp/Conversation")
        let source = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for identifier in [
            "conversation.root", "conversation.close", "conversation.timeline",
            "conversation.voice-composer", "conversation.text-composer",
            "conversation.save-draft", "conversation.discard", "conversation.retry",
            "conversation.correct-transcript",
            "conversation.unavailable.close", "conversation.response-info",
            "conversation.feedback.helpful", "conversation.feedback.not_helpful",
            "conversation.feedback-factors", "conversation.feedback.close",
            "conversation.feedback.save", "conversation.feedback.detail",
            "conversation.feedback.remove", "conversation.proposal-review",
            "conversation.proposal.accept", "conversation.proposal.dismiss"
        ] {
            XCTAssertTrue(source.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertTrue(source.contains("interactiveDismissDisabled"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertTrue(source.contains("ScrollViewReader"))
        XCTAssertTrue(source.contains(".task(id: messages.last?.id)"))
        XCTAssertTrue(source.contains("await Task.yield()"))
        XCTAssertTrue(source.contains("conversation.timeline-bottom"))
        XCTAssertTrue(source.contains("hasPositionedInitialMessages"))
        XCTAssertTrue(source.contains("latestUserTranscript"))
        XCTAssertTrue(source.contains("contextMenu"))
        XCTAssertTrue(source.contains("Copy"))
        XCTAssertTrue(source.contains("TaisaToast(message: \"Copied\""))
        XCTAssertTrue(source.contains("Edit"))
        XCTAssertTrue(source.contains("userPreviewLineLimit = 6"))
        XCTAssertTrue(source.contains("Updating response…"))
        XCTAssertTrue(source.contains("ConversationJumpToLatestButton"))
        XCTAssertEqual(ConversationTimelineLayout.userBubbleWidthFraction, 0.85)
        XCTAssertTrue(source.contains("withAnimation"))
        XCTAssertTrue(source.contains("scrollBounceBehavior(.always, axes: .vertical)"))
        XCTAssertTrue(source.contains("defaultScrollAnchor(.bottom, for: .initialOffset)"))
        XCTAssertFalse(source.contains("defaultScrollAnchor(.bottom)\n"))
        XCTAssertTrue(source.contains("jumpVisibilityThreshold"))
        XCTAssertTrue(source.contains("isAwayFromLatest = false"))
        XCTAssertTrue(source.contains("LazyVStack(alignment: .leading, spacing: 0)"))
        XCTAssertTrue(source.contains("VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue)"))
        XCTAssertFalse(source.contains("safeAreaInset(edge: .bottom)"))
        XCTAssertTrue(source.contains("VStack(spacing: 0)"))
        XCTAssertTrue(source.contains("static let userToAssistantSpacing"))
        XCTAssertTrue(source.contains("static let ordinaryMessageSpacing"))
        XCTAssertTrue(source.contains("StatusBarBackground"))
        XCTAssertTrue(source.contains("TaisaSecondaryCapsuleButton"))
        XCTAssertTrue(source.contains("height: TaisaControlMetric.recordingButtonHeight"))
        XCTAssertTrue(source.contains("HStack(spacing: TaisaSpacing.compact.rawValue)"))
        XCTAssertTrue(source.contains("CentralIcon(.voiceMid)"))
        XCTAssertTrue(source.contains("Text(\"Reply\")"))
        XCTAssertTrue(source.contains(".smooth(duration: TaisaMotion.settle)"))
        XCTAssertTrue(source.contains("Edit message"))
        XCTAssertTrue(source.contains("isProcessing: isSubmitting"))
        XCTAssertFalse(source.contains("taisaMessageSendTransition"))
        XCTAssertTrue(source.contains("UIApplication.openSettingsURLString"))
        XCTAssertTrue(source.contains("UIApplication.shared.open(settingsURL"))
        XCTAssertTrue(source.contains("Task.sleep(for: .milliseconds(200))"))
        XCTAssertTrue(source.contains("Microphone unavailable"))
        XCTAssertTrue(source.contains(".disabled(model.actionInFlight)"))
        XCTAssertTrue(source.contains("TaisaControlMetric.conversationEmptyVoiceIcon"))
        XCTAssertTrue(source.contains("TaisaTypography.metadata.font"))
        XCTAssertTrue(source.contains("TAISA_CAPTURE begin.failure type="))
        XCTAssertFalse(source.contains("Correct transcript"))
        XCTAssertFalse(source.contains("Text(message.role == \"assistant\" ? \"Taisa\" : \"You\")"))
        XCTAssertFalse(source.contains("Text(\"You\")"))
        XCTAssertFalse(source.contains("conversation.transcript-preview"))
        XCTAssertFalse(source.contains("containerRelativeFrame(.horizontal"))
        XCTAssertFalse(source.contains("import GRDB"))
    }

    func testJumpToLatestAppearsOnlyAfterAUsefulDistance() {
        XCTAssertFalse(ConversationTimelineLayout.shouldShowJumpToLatest(distanceFromBottom: 0))
        XCTAssertFalse(ConversationTimelineLayout.shouldShowJumpToLatest(distanceFromBottom: 159))
        XCTAssertTrue(ConversationTimelineLayout.shouldShowJumpToLatest(distanceFromBottom: 160))
    }

    func testConversationUsesSemanticTurnSpacing() {
        XCTAssertEqual(ConversationTimelineLayout.ordinaryMessageSpacing, 12)
        XCTAssertEqual(ConversationTimelineLayout.userToAssistantSpacing, 32)
        XCTAssertEqual(
            ConversationTimelineLayout.spacing(afterRole: "user", beforeRole: "assistant"),
            32
        )
        XCTAssertEqual(
            ConversationTimelineLayout.spacing(afterRole: "assistant", beforeRole: "user"),
            12
        )
    }

    func testUserBubbleWidthIsIntrinsicUntilItReachesTheEightyFivePercentCap() {
        XCTAssertEqual(
            ConversationTimelineLayout.userBubbleWidth(
                intrinsicWidth: 120,
                containerWidth: 400,
                trailingInset: 16
            ),
            120
        )
        XCTAssertEqual(
            ConversationTimelineLayout.userBubbleWidth(
                intrinsicWidth: 500,
                containerWidth: 400,
                trailingInset: 16
            ),
            324
        )
    }

    func testResponseFeedbackUsesAlwaysVisibleThumbsAndSelectableQualityFactors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversation/AssistantResponseActions.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("icon: .circleInfo"))
        XCTAssertFalse(source.contains("CentralIcon(.infoSimple)"))
        XCTAssertTrue(source.contains("icon: .thumbsUp"))
        XCTAssertTrue(source.contains("icon: .thumbsDown"))
        XCTAssertTrue(source.contains("ResponseActionIconButton("))
        XCTAssertFalse(source.contains("Image(systemName:"))
        XCTAssertFalse(source.contains("systemImage:"))
        XCTAssertTrue(source.contains("accessibilityLabel: \"About this response\""))
        XCTAssertFalse(source.contains("Label(\"About this response\", systemImage:"))
        XCTAssertTrue(source.contains("What worked well?"))
        XCTAssertTrue(source.contains("What could be better?"))
        XCTAssertTrue(source.contains("Source unavailable"))
        XCTAssertTrue(source.contains(".sheet(isPresented: $showsFeedback, onDismiss:"))
        XCTAssertTrue(source.contains("Button(\"Close\")"))
        XCTAssertTrue(source.contains("Button(\"Save feedback\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"conversation.feedback.close\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"conversation.feedback.save\")"))
        XCTAssertTrue(source.contains("FeedbackTextEditor"))
        XCTAssertTrue(source.contains("Add more detail (optional)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"conversation.feedback.detail\")"))
        XCTAssertTrue(source.contains("TaisaButton(role: .destructive, label: \"Remove rating\")"))
        XCTAssertTrue(source.contains("saveFeedback(nil, [], nil)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"conversation.feedback.remove\")"))
        XCTAssertFalse(source.contains("direction == value ? nil : value"))
        XCTAssertFalse(source.contains("if let direction {\n                feedbackFactors(for: direction)\n            }"))
        XCTAssertTrue(source.contains("ResponseFeedbackCopy.options"))
        XCTAssertTrue(source.contains("ResponseActionIconButton"))
        XCTAssertTrue(source.contains("SelectableChip"))
        XCTAssertTrue(source.contains("FeedbackTextEditor"))
        XCTAssertTrue(source.contains("ActionPanel"))
        XCTAssertTrue(source.contains("TaisaTypography.metadata.font"))
        XCTAssertTrue(source.contains("TaisaTypography.body.font"))
        XCTAssertFalse(source.contains("AssistantResponseActionsLayout"))
        XCTAssertFalse(source.contains(".font(.caption)"))
        XCTAssertFalse(source.contains(".font(.body)"))
        XCTAssertFalse(source.contains(".buttonStyle(.bordered)"))
        XCTAssertFalse(source.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertFalse(source.contains("minHeight: 112"))
        XCTAssertFalse(source.contains("minWidth: TaisaControlMetric.headerActionHeight"))
        XCTAssertFalse(source.contains("TextField"))
    }

    func testSeniorSelfResponseHasDeterministicPreviewScenario() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaPreview/ConversationScenarios.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("conversation.senior-self-response"))
        XCTAssertTrue(source.contains("assistantResponses:"))
        XCTAssertTrue(source.contains("AssistantResponseMetadataRecord"))
        XCTAssertTrue(source.contains("AssistantProposalRecord"))
    }
}
