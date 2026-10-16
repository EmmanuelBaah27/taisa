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
            "conversation.unavailable.close"
        ] {
            XCTAssertTrue(source.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertTrue(source.contains("interactiveDismissDisabled"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertTrue(source.contains("ScrollViewReader"))
        XCTAssertTrue(source.contains("onChange(of: messages.last?.id"))
        XCTAssertTrue(source.contains("latestUserTranscript"))
        XCTAssertTrue(source.contains("contextMenu"))
        XCTAssertTrue(source.contains("Copy"))
        XCTAssertTrue(source.contains("Edit"))
        XCTAssertTrue(source.contains("userPreviewLineLimit = 6"))
        XCTAssertTrue(source.contains("Updating response…"))
        XCTAssertTrue(source.contains("Jump to latest"))
        XCTAssertEqual(ConversationTimelineLayout.userBubbleWidthFraction, 0.85)
        XCTAssertTrue(source.contains("ConversationTimelineLayout.jumpIconSize"))
        XCTAssertTrue(source.contains("withAnimation"))
        XCTAssertTrue(source.contains("scrollBounceBehavior(.always, axes: .vertical)"))
        XCTAssertTrue(source.contains("defaultScrollAnchor(.bottom, for: .initialOffset)"))
        XCTAssertFalse(source.contains("defaultScrollAnchor(.bottom)\n"))
        XCTAssertTrue(source.contains("jumpVisibilityThreshold"))
        XCTAssertTrue(source.contains("isAwayFromLatest = false"))
        XCTAssertTrue(source.contains("LazyVStack(alignment: .leading, spacing: TaisaSpacing.control.rawValue)"))
        XCTAssertTrue(source.contains("VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue)"))
        XCTAssertFalse(source.contains("safeAreaInset(edge: .bottom)"))
        XCTAssertTrue(source.contains("VStack(spacing: 0)"))
        XCTAssertTrue(source.contains(".smooth(duration: TaisaMotion.settle)"))
        XCTAssertTrue(source.contains("Edit message"))
        XCTAssertTrue(source.contains("UIApplication.openSettingsURLString"))
        XCTAssertTrue(source.contains("UIApplication.shared.open(settingsURL"))
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
}
