import Foundation
import XCTest

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
            "conversation.correct-transcript", "conversation.transcript-preview",
            "conversation.unavailable.close", "conversation.response-info",
            "conversation.feedback.helpful", "conversation.feedback.not_helpful",
            "conversation.feedback-factors", "conversation.feedback.done", "conversation.proposal-review",
            "conversation.proposal.accept", "conversation.proposal.dismiss"
        ] {
            XCTAssertTrue(source.contains(identifier), "Missing \(identifier)")
        }
        XCTAssertTrue(source.contains("interactiveDismissDisabled"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertTrue(source.contains("ScrollViewReader"))
        XCTAssertTrue(source.contains("onChange(of: messages.last?.id"))
        XCTAssertTrue(source.contains("latestUserTranscript"))
        XCTAssertFalse(source.contains("import GRDB"))
    }

    func testResponseFeedbackUsesAlwaysVisibleThumbsAndSelectableQualityFactors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/Conversation/AssistantResponseActions.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("hand.thumbsup"))
        XCTAssertTrue(source.contains("hand.thumbsdown"))
        XCTAssertTrue(source.contains("About this response"))
        XCTAssertTrue(source.contains("What worked well?"))
        XCTAssertTrue(source.contains("What could be better?"))
        XCTAssertTrue(source.contains("Source unavailable"))
        XCTAssertTrue(source.contains(".sheet(isPresented: $showsFeedback)"))
        XCTAssertTrue(source.contains("Button(\"Done\") { showsFeedback = false }"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"conversation.feedback.done\")"))
        XCTAssertFalse(source.contains("direction == value ? nil : value"))
        XCTAssertFalse(source.contains("if let direction {\n                feedbackFactors(for: direction)\n            }"))
        XCTAssertTrue(source.contains("ResponseFeedbackCopy.options"))
        XCTAssertTrue(source.contains("minWidth: TaisaControlMetric.headerActionHeight"))
        XCTAssertFalse(source.contains("TextField"))
        XCTAssertFalse(source.contains("TextEditor"))
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
