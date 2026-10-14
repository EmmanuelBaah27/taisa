import Foundation
import XCTest
import TaisaHome
import TaisaStorage
import TaisaVoice
import TaisaYou
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

    func testSavedVoiceDraftWithUnreadableTurnRestoresRetryFromPersistedTranscript() {
        let conversationID = UUID().uuidString
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
            voiceTurnID: UUID().uuidString,
            recoveryKind: .saved,
            createdAtMS: 1,
            updatedAtMS: 2
        )

        let restoration = ConversationRuntimeFactory.restoration(
            draft: draft,
            linkedVoiceTurn: nil,
            resumableVoiceTurn: nil,
            fallbackVoiceTurn: fallbackTurn,
            recoveryTranscript: "Persisted transcript"
        )

        XCTAssertEqual(restoration.voiceTurn.id, fallbackTurn.id)
        XCTAssertEqual(restoration.voiceTurn.state, .terminalFailure)
        XCTAssertEqual(restoration.voiceTurn.stage, .finished)
        XCTAssertEqual(restoration.voiceTurn.acceptedTranscript, "Persisted transcript")
        XCTAssertEqual(restoration.composer, .failure(.retryable))
    }

    func testSavedVoiceDraftWithUnreadableTurnWithoutLinkedTranscriptRemainsPaused() {
        let conversationID = UUID().uuidString
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
            voiceTurnID: UUID().uuidString,
            recoveryKind: .saved,
            createdAtMS: 20,
            updatedAtMS: 21
        )

        let restoration = ConversationRuntimeFactory.restoration(
            draft: draft,
            linkedVoiceTurn: nil,
            resumableVoiceTurn: nil,
            fallbackVoiceTurn: fallbackTurn,
            recoveryTranscript: nil
        )

        XCTAssertEqual(restoration.voiceTurn.id, fallbackTurn.id)
        XCTAssertEqual(restoration.voiceTurn.state, .draft)
        XCTAssertEqual(restoration.composer, .paused)
    }

    func testFinalizedVoiceDraftRestoresAsReadyToSendInsteadOfResumable() {
        let conversationID = UUID().uuidString
        let linkedTurn = VoiceTurnRecord(
            id: UUID().uuidString, conversationID: conversationID,
            transcriptionRequestID: UUID().uuidString,
            transcriptionIdempotencyKey: UUID().uuidString,
            coachingRequestID: UUID().uuidString,
            coachingIdempotencyKey: UUID().uuidString,
            state: .paused, stage: .capture,
            audioFileID: UUID().uuidString, audioSHA256: "saved-audio",
            audioDurationMS: 2_000, cleanupState: .pending,
            createdAtMS: 1, updatedAtMS: 2
        )
        let draft = ConversationDraftRecord(
            id: UUID().uuidString, conversationID: conversationID,
            inputMode: .voice, text: nil, voiceTurnID: linkedTurn.id,
            recoveryKind: .saved, createdAtMS: 1, updatedAtMS: 2
        )

        let restoration = ConversationRuntimeFactory.restoration(
            draft: draft, linkedVoiceTurn: linkedTurn,
            resumableVoiceTurn: nil,
            fallbackVoiceTurn: voiceTurn(
                conversationID: conversationID, state: .draft, stage: .capture
            )
        )

        XCTAssertEqual(restoration.composer, .savedVoiceDraft)
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

    func testLiveRuntimeUsesMutationCapableLocalHomeClient() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/App/AppRuntime.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("let context = try await backend.voiceStoreContext()"))
        XCTAssertTrue(source.contains("HomeClient.local(store: store, deviceID: context.deviceID.uuidString)"))
        XCTAssertTrue(source.contains("CareerWorkClient.local(store: store, deviceID: context.deviceID.uuidString)"))
        XCTAssertFalse(source.contains("HomeClient { try await HomeQuery"))
    }

    func testSuccessfulStartBuildsHomeModel() async {
        let runtime = AppRuntime(start: { .test(home: HomeClient { HomeSnapshot(conversations: [], goals: [], actions: []) }) })
        let state = await runtime.start()
        XCTAssertEqual(state, .ready)
        XCTAssertNotNil(runtime.homeModel)
        XCTAssertNotNil(runtime.careerWorkModel)
        XCTAssertNotNil(runtime.insightsModel)
        XCTAssertNotNil(runtime.youModel)
    }

    func testStorageFailuresRouteToRecovery() async {
        for error in [StorageError.missingKeyForExistingStore, .integrityFailed, .authenticationFailed] {
            let runtime = AppRuntime(start: { throw error })
            let state = await runtime.start()
            XCTAssertEqual(state, .recoveryRequired)
            XCTAssertNil(runtime.homeModel)
            XCTAssertNil(runtime.careerWorkModel)
            XCTAssertNil(runtime.insightsModel)
            XCTAssertNil(runtime.youModel)
        }
    }

    func testRecoveryRetryReopensRuntimeAfterTransientStoreFailure() async {
        let attempts = StartAttempts()
        let runtime = AppRuntime(start: {
            guard await attempts.next() > 1 else { throw StorageError.authenticationFailed }
            return .test(home: HomeClient { HomeSnapshot(conversations: [], goals: [], actions: []) })
        })

        let failedState = await runtime.start()
        XCTAssertEqual(failedState, .recoveryRequired)
        let recoveredState = await runtime.retryRecovery()
        XCTAssertEqual(recoveredState, .ready)
        XCTAssertNotNil(runtime.homeModel)
        XCTAssertNotNil(runtime.youModel)
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

private extension AppRuntime.Clients {
    static func test(home: HomeClient) -> Self {
        .init(
            home: home,
            you: YouClient(load: { .init(profile: nil, capabilities: [], diagnostics: .unknown) }),
            insights: InsightsClient(load: { .empty }, detail: { insight in
                .init(insight: insight, sources: [], revisions: [])
            })
        )
    }
}

private actor StartAttempts {
    private var count = 0
    func next() -> Int { count += 1; return count }
}
