import Foundation
import XCTest
import TaisaHome
import TaisaStorage
import TaisaVoice
import TaisaYou
@testable import Taisa

@MainActor
final class AppRuntimeTests: XCTestCase {
    func testInterruptedCaptureWithoutSavedDraftStartsFromFreshReplyState() {
        let conversationID = UUID().uuidString
        let interruptedTurn = voiceTurn(
            conversationID: conversationID,
            state: .paused,
            stage: .capture
        )
        let fallbackTurn = voiceTurn(
            conversationID: conversationID,
            state: .draft,
            stage: .capture
        )

        let restoration = ConversationRuntimeFactory.restoration(
            draft: nil,
            linkedVoiceTurn: nil,
            resumableVoiceTurn: interruptedTurn,
            fallbackVoiceTurn: fallbackTurn
        )

        XCTAssertEqual(restoration.voiceTurn.id, interruptedTurn.id)
        XCTAssertEqual(restoration.composer, .waitingForReply)
        XCTAssertTrue(restoration.cleansInterruptedCapture)
    }

    func testRecordingCaptureWithoutSavedDraftStartsFromFreshReplyState() {
        let conversationID = UUID().uuidString
        let interruptedTurn = voiceTurn(
            conversationID: conversationID,
            state: .recording,
            stage: .capture
        )
        let fallbackTurn = voiceTurn(
            conversationID: conversationID,
            state: .draft,
            stage: .capture
        )

        let restoration = ConversationRuntimeFactory.restoration(
            draft: nil,
            linkedVoiceTurn: nil,
            resumableVoiceTurn: interruptedTurn,
            fallbackVoiceTurn: fallbackTurn
        )

        XCTAssertEqual(restoration.voiceTurn.id, interruptedTurn.id)
        XCTAssertEqual(restoration.composer, .waitingForReply)
        XCTAssertTrue(restoration.cleansInterruptedCapture)
    }

    func testFinalizedCaptureWithoutDraftRemainsAvailableToSend() {
        let conversationID = UUID().uuidString
        let finalizedTurn = VoiceTurnRecord(
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
        let fallbackTurn = voiceTurn(
            conversationID: conversationID,
            state: .draft,
            stage: .capture
        )

        let restoration = ConversationRuntimeFactory.restoration(
            draft: nil,
            linkedVoiceTurn: nil,
            resumableVoiceTurn: finalizedTurn,
            fallbackVoiceTurn: fallbackTurn
        )

        XCTAssertEqual(restoration.voiceTurn.id, finalizedTurn.id)
        XCTAssertEqual(restoration.composer, .savedVoiceDraft)
        XCTAssertFalse(restoration.cleansInterruptedCapture)
    }

    func testInterruptedCaptureCleanupRetriesBeforeFreshReplyState() {
        let conversationID = UUID().uuidString
        let cleanupTurn = VoiceTurnRecord(
            id: UUID().uuidString, conversationID: conversationID,
            transcriptionRequestID: UUID().uuidString,
            transcriptionIdempotencyKey: UUID().uuidString,
            coachingRequestID: UUID().uuidString,
            coachingIdempotencyKey: UUID().uuidString,
            state: .terminalFailure, stage: .cleanup,
            audioFileID: UUID().uuidString, failureCode: "CAPTURE_INTERRUPTED",
            cleanupState: .pending, createdAtMS: 1, updatedAtMS: 2
        )
        let fallbackTurn = voiceTurn(
            conversationID: conversationID,
            state: .draft,
            stage: .capture
        )

        let restoration = ConversationRuntimeFactory.restoration(
            draft: nil,
            linkedVoiceTurn: nil,
            resumableVoiceTurn: cleanupTurn,
            fallbackVoiceTurn: fallbackTurn
        )

        XCTAssertEqual(restoration.voiceTurn.id, cleanupTurn.id)
        XCTAssertEqual(restoration.composer, .waitingForReply)
        XCTAssertTrue(restoration.cleansInterruptedCapture)
    }

    func testInterruptedCaptureCleanupCannotOwnTheReadableChatRuntime() {
        let conversationID = UUID().uuidString
        let interruptedTurn = voiceTurn(
            conversationID: conversationID,
            state: .terminalFailure,
            stage: .cleanup
        )
        let fallbackTurn = voiceTurn(
            conversationID: conversationID,
            state: .draft,
            stage: .capture
        )
        let restoration = ConversationRuntimeFactory.restoration(
            draft: nil,
            linkedVoiceTurn: nil,
            resumableVoiceTurn: interruptedTurn,
            fallbackVoiceTurn: fallbackTurn
        )

        XCTAssertEqual(
            ConversationRuntimeFactory.runtimeInitialTurn(
                restoration: restoration,
                fallbackVoiceTurn: fallbackTurn,
                hasPendingConversationRequest: false
            ).id,
            fallbackTurn.id
        )
    }

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

    func testUnsavedFinishedVoiceResponseFailureRestoresRetryAlert() {
        let conversationID = UUID().uuidString
        let failedTurn = voiceTurn(
            conversationID: conversationID,
            state: .terminalFailure,
            stage: .finished
        )
        let fallbackTurn = voiceTurn(
            conversationID: conversationID,
            state: .draft,
            stage: .capture
        )

        let restoration = ConversationRuntimeFactory.restoration(
            draft: nil,
            linkedVoiceTurn: nil,
            resumableVoiceTurn: failedTurn,
            fallbackVoiceTurn: fallbackTurn
        )

        XCTAssertEqual(restoration.voiceTurn.id, failedTurn.id)
        XCTAssertEqual(restoration.composer, .failure(.retryable))
        XCTAssertFalse(restoration.cleansInterruptedCapture)
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

    func testOperationalFactsRemainHonestWithoutLiveHealthProof() {
        let facts = AppRuntime.operationalFacts(
            hasGatewayConfiguration: true,
            microphone: .denied
        )

        XCTAssertEqual(facts.store, .healthy)
        XCTAssertEqual(facts.recovery, .unknown)
        XCTAssertEqual(facts.microphone, .denied)
        XCTAssertEqual(facts.gateway, .unknown)
    }

    func testLiveRuntimeKeepsConversationOpeningAvailableWithoutVoiceEnrollment() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/App/AppRuntime.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("conversationFactory: ConversationRuntimeFactory("))
        XCTAssertTrue(source.contains("configuration: configuration"))
        XCTAssertFalse(source.contains("configuration.map { ConversationRuntimeFactory"))
    }

    func testExistingConversationOpensWithoutVoiceEnrollment() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(
            at: directory.appendingPathComponent("store.sqlite"),
            keyStore: AppRuntimeTestKeys()
        )
        let conversationID = "00000000-0000-4000-8000-000000000601"
        let repository = ConversationRepository(store: store)
        let context = MutationContext(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 1)
        try await repository.create(.init(
            id: conversationID,
            title: "A stored conversation",
            lifecycle: .completed,
            titleAuthority: .localFallback,
            createdAtMS: 1,
            updatedAtMS: 1
        ), context: context)
        try await repository.createMessage(.init(
            id: "00000000-0000-4000-8000-000000000602",
            conversationID: conversationID,
            role: "user",
            body: "This message must remain readable offline.",
            createdAtMS: 2
        ), context: .init(id: UUID().uuidString, deviceID: context.deviceID, timestamp: 2))

        let model = try await ConversationRuntimeFactory(
            store: store,
            deviceID: UUID(),
            configuration: nil
        ).makeModel(
            route: .init(id: conversationID, localTitle: "A stored conversation"),
            entryIntent: nil,
            dismiss: {}
        )
        await model.start()

        XCTAssertEqual(model.messages.map(\.body), ["This message must remain readable offline."])
        XCTAssertEqual(model.title, "A stored conversation")
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
        XCTAssertTrue(source.contains("ConversationsClient.local(store: store, deviceID: context.deviceID.uuidString)"))
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

    func testSuccessfulRestoreRebuildsEveryRuntimeClient() async {
        let attempts = StartAttempts()
        let runtime = AppRuntime(start: {
            _ = await attempts.next()
            return .test(home: HomeClient { HomeSnapshot(conversations: [], goals: [], actions: []) })
        })

        let startedState = await runtime.start()
        XCTAssertEqual(startedState, .ready)
        let originalYouModel = try! XCTUnwrap(runtime.youModel)

        let restoredState = await runtime.reloadAfterRestore()
        XCTAssertEqual(restoredState, .ready)
        let attemptCount = await attempts.value
        XCTAssertEqual(attemptCount, 2)
        XCTAssertFalse(originalYouModel === runtime.youModel)
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
            you: YouClient(load: { .init(profile: nil, diagnostics: .unknown) }),
            insights: InsightsClient(load: { .empty }, detail: { insight in
                .init(insight: insight, sources: [], revisions: [])
            })
        )
    }
}

private actor StartAttempts {
    private var count = 0
    func next() -> Int { count += 1; return count }
    var value: Int { count }
}

private actor AppRuntimeTestKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
