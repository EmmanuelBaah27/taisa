import Foundation
import GRDB
import Testing
@testable import TaisaStorage

private actor AssistantResponseKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized)
struct AssistantResponseRepositoryTests {
    @Test func schemaSevenCreatesEveryStrictCompanionTable() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let state = try await fixture.store.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"),
                try ["assistant_response_metadata", "assistant_response_sources", "assistant_proposals", "response_feedback", "preference_profiles"].allSatisfy { try db.tableExists($0) },
                try Int.fetchOne(db, sql: "SELECT count(*) FROM pragma_foreign_key_check")
            )
        }
        #expect(state.0 == 7)
        #expect(state.1 == ["v1", "v2", "v3", "v4", "v5", "v6", "v7"])
        #expect(state.2)
        #expect(state.3 == 0)
    }

    @Test(arguments: AssistantResponseFailurePoint.allCases)
    func responsePersistenceRollsBackEveryPartialStage(_ failurePoint: AssistantResponseFailurePoint) async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        try await fixture.seedConversation()
        let repository = AssistantResponseRepository(store: fixture.store, failurePoint: failurePoint)

        await #expect(throws: RepositoryError.self) {
            try await repository.persist(fixture.write)
        }
        let counts = try await fixture.companionCounts()
        #expect(counts == [0, 0, 0, 0])
    }

    @Test func persistsAndBatchLoadsMessageMetadataSourcesAndProposal() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        try await fixture.seedConversation()
        try await AssistantResponseRepository(store: fixture.store).persist(fixture.write)

        let snapshot = try await ConversationQuery(store: fixture.store).loadConversation(id: fixture.conversationID)
        #expect(snapshot.visibleMessages.map(\.id) == [fixture.messageID])
        #expect(snapshot.assistantResponses[fixture.messageID]?.metadata.requestID == fixture.requestID)
        #expect(snapshot.assistantResponses[fixture.messageID]?.sources.map(\.ordinal) == [0, 1])
        #expect(snapshot.assistantResponses[fixture.messageID]?.proposal?.state == .pending)
    }

    @Test func feedbackUpsertCanonicalizesFactorsAndEnforcesOneRowPerResponse() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        try await fixture.seedConversation()
        let repository = AssistantResponseRepository(store: fixture.store)
        try await repository.persist(fixture.write)

        try await repository.upsertFeedback(.init(
            responseMessageID: fixture.messageID, direction: .helpful,
            factors: [.communicationClarity, .coverage, .coverage], detail: "Useful", updatedAtMS: 30
        ))
        try await repository.upsertFeedback(.init(
            responseMessageID: fixture.messageID, direction: .notHelpful,
            factors: [.intentAlignment, .evidenceFidelity], detail: nil, updatedAtMS: 31
        ))

        let response = try await repository.response(messageID: fixture.messageID)
        #expect(response?.feedback?.direction == .notHelpful)
        #expect(response?.feedback?.factors == [.evidenceFidelity, .intentAlignment])
        #expect(try await fixture.store.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM response_feedback") } == 1)
    }

    @Test func selectedFeedbackCanBeRemovedIdempotently() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        try await fixture.seedConversation()
        let repository = AssistantResponseRepository(store: fixture.store)
        try await repository.persist(fixture.write)
        try await repository.upsertFeedback(.init(
            responseMessageID: fixture.messageID, direction: .helpful,
            factors: [.coverage], detail: nil, updatedAtMS: 30
        ))

        try await repository.removeFeedback(responseMessageID: fixture.messageID)
        try await repository.removeFeedback(responseMessageID: fixture.messageID)

        #expect(try await repository.response(messageID: fixture.messageID)?.feedback == nil)
    }

    @Test func correctionSupersedesTheOriginalPendingProposalInTheSameTransaction() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        try await fixture.seedConversation()
        let userID = "10000000-0000-4000-8000-000000000010"
        try await fixture.store.write { db in
            try db.execute(sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, 'user', 'Original', 19)", arguments: [userID, fixture.conversationID])
        }
        try await AssistantResponseRepository(store: fixture.store).persist(fixture.write)
        let correction = ConversationCorrection(
            revisionID: "10000000-0000-4000-8000-000000000011",
            originalUserMessageID: userID,
            originalAssistantMessageID: fixture.messageID,
            correctedUserMessage: .init(id: "10000000-0000-4000-8000-000000000012", conversationID: fixture.conversationID, role: "user", body: "Corrected", createdAtMS: 30),
            regeneratedAssistantMessage: .init(id: "10000000-0000-4000-8000-000000000013", conversationID: fixture.conversationID, role: "assistant", body: "Replacement", createdAtMS: 31),
            createdAtMS: 30
        )

        try await ConversationRepository(store: fixture.store).applyCorrection(
            correction,
            context: .init(id: "10000000-0000-4000-8000-000000000014", deviceID: "10000000-0000-4000-8000-000000000015", timestamp: 30)
        )

        #expect(try await AssistantResponseRepository(store: fixture.store).response(messageID: fixture.messageID)?.proposal?.state == .superseded)
    }
}

private struct Fixture {
    let directory: URL
    let store: TaisaStore
    let conversationID = "10000000-0000-4000-8000-000000000001"
    let messageID = "10000000-0000-4000-8000-000000000002"
    let requestID = "10000000-0000-4000-8000-000000000003"

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await TaisaStore.open(at: directory.appending(path: "taisa.sqlite"), keyStore: AssistantResponseKeys())
    }

    var write: AssistantResponseWrite {
        .init(
            message: .init(id: messageID, conversationID: conversationID, role: "assistant", body: "A grounded response", createdAtMS: 20),
            metadata: .init(responseMessageID: messageID, requestID: requestID, idempotencyReceipt: "receipt-1", mode: .coach, relevance: "career-relevant", contextSufficiency: "sufficient", stance: "nudge", inference: "Momentum is visible", confidence: "medium", approach: "Offer one next step", createdAtMS: 20),
            sources: [
                .init(id: "10000000-0000-4000-8000-000000000004", responseMessageID: messageID, ordinal: 0, sourceID: "goal-opaque", sourceType: "goal", excerpt: nil),
                .init(id: "10000000-0000-4000-8000-000000000005", responseMessageID: messageID, ordinal: 1, sourceID: "message-opaque", sourceType: "message", excerpt: "A safe excerpt"),
            ],
            proposal: .init(id: "10000000-0000-4000-8000-000000000006", responseMessageID: messageID, kind: "action", canonicalPayload: Data(#"{"kind":"action"}"#.utf8), payloadDigest: "digest-1", state: .pending, targetType: nil, targetID: nil, targetVersionID: nil, decisionReceipt: nil, createdAtMS: 20, resolvedAtMS: nil)
        )
    }

    func seedConversation() async throws {
        try await store.write { db in
            try db.execute(sql: "INSERT INTO conversations (id, title, lifecycle, title_authority, created_at_ms, updated_at_ms) VALUES (?, '', 'active', 'localFallback', 1, 1)", arguments: [conversationID])
        }
    }

    func companionCounts() async throws -> [Int] {
        try await store.read { db in
            try ["messages", "assistant_response_metadata", "assistant_response_sources", "assistant_proposals"].map {
                try Int.fetchOne(db, sql: "SELECT count(*) FROM \($0)") ?? -1
            }
        }
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
