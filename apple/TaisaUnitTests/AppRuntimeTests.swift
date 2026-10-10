import Foundation
import XCTest
import TaisaHome
import TaisaStorage
import TaisaVoice
@testable import Taisa

@MainActor
final class AppRuntimeTests: XCTestCase {
    func testSavedTerminalVoiceFailureRestoresTheLinkedTurnForRetry() {
        let conversationID = UUID().uuidString
        let linkedTurn = voiceTurn(
            conversationID: conversationID,
            state: .terminalFailure,
            stage: .finished
        )
        let unrelatedResumableTurn = voiceTurn(
            conversationID: conversationID,
            state: .paused,
            stage: .capture
        )
        let fallbackTurn = voiceTurn(
            conversationID: conversationID,
            state: .draft,
            stage: .capture
        )
        let draft = ConversationDraftRecord(
            id: UUID().uuidString,
            conversationID: conversationID,
            inputMode: .voice,
            text: nil,
            voiceTurnID: linkedTurn.id,
            recoveryKind: .saved,
            createdAtMS: 1,
            updatedAtMS: 2
        )

        let restoration = ConversationRuntimeFactory.restoration(
            draft: draft,
            linkedVoiceTurn: linkedTurn,
            resumableVoiceTurn: unrelatedResumableTurn,
            fallbackVoiceTurn: fallbackTurn
        )

        XCTAssertEqual(restoration.voiceTurn.id, linkedTurn.id)
        XCTAssertEqual(restoration.composer, .failure(.retryable))
    }

    func testVoiceConfigurationUsesEnrolledOriginBoundCredential() async throws {
        let store = InMemoryVoiceGatewayCredentialStore()
        let credential = try VoiceGatewayCredential(
            origin: XCTUnwrap(URL(string: "https://voice.example.com/path?ignored=true")),
            credentialID: "credential-1",
            bearerToken: "secret-token"
        )
        try await store.save(credential)

        let configuration = try await AppRuntime.voiceConfiguration(
            gatewayURLString: "https://voice.example.com/another-path",
            credentialStore: store
        )

        XCTAssertEqual(configuration?.baseURL, URL(string: "https://voice.example.com"))
        XCTAssertEqual(configuration?.bearerToken, "secret-token")
        XCTAssertEqual(configuration?.ownerID, "credential-1")
    }

    func testVoiceConfigurationIsUnavailableWithoutEnrollment() async throws {
        let configuration = try await AppRuntime.voiceConfiguration(
            gatewayURLString: "https://voice.example.com",
            credentialStore: InMemoryVoiceGatewayCredentialStore()
        )

        XCTAssertNil(configuration)
    }
    func testSuccessfulStartBuildsHomeModel() async {
        let runtime = AppRuntime(start: { HomeClient { HomeSnapshot(conversations: [], goals: [], actions: []) } })
        let state = await runtime.start()
        XCTAssertEqual(state, .ready)
        XCTAssertNotNil(runtime.homeModel)
    }

    func testStorageFailuresRouteToRecovery() async {
        for error in [StorageError.missingKeyForExistingStore, .integrityFailed, .authenticationFailed] {
            let runtime = AppRuntime(start: { throw error })
            let state = await runtime.start()
            XCTAssertEqual(state, .recoveryRequired)
            XCTAssertNil(runtime.homeModel)
        }
    }

    func testMissingKeyRouteDoesNotTouchExistingStoreBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("taisa.sqlite")
        let original = Data("existing encrypted store".utf8)
        try original.write(to: storeURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)

        let runtime = AppRuntime(start: { throw StorageError.missingKeyForExistingStore })
        let state = await runtime.start()
        XCTAssertEqual(state, .recoveryRequired)
        XCTAssertEqual(try Data(contentsOf: storeURL), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: storeURL.path)[.systemFileNumber] as? NSNumber,
                       attributes[.systemFileNumber] as? NSNumber)
    }

    private func voiceTurn(
        conversationID: String,
        state: VoiceTurnState,
        stage: VoiceTurnStage
    ) -> VoiceTurnRecord {
        VoiceTurnRecord(
            id: UUID().uuidString,
            conversationID: conversationID,
            transcriptionRequestID: UUID().uuidString,
            transcriptionIdempotencyKey: UUID().uuidString,
            coachingRequestID: UUID().uuidString,
            coachingIdempotencyKey: UUID().uuidString,
            state: state,
            stage: stage,
            acceptedTranscript: "Recorded words",
            createdAtMS: 1,
            updatedAtMS: 2
        )
    }
}
