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
        #expect(state.0 == 8)
        #expect(state.1 == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8"])
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

    @Test func schemaSixPartialMessageIsReconciledWithoutDuplicate() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        try await fixture.seedConversation()
        try await fixture.store.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, 'assistant', ?, ?)",
                arguments: [fixture.messageID, fixture.conversationID, fixture.write.message.body, fixture.write.message.createdAtMS]
            )
        }

        try await AssistantResponseRepository(store: fixture.store).persist(fixture.write)

        #expect(try await fixture.companionCounts() == [1, 1, 2, 1])
        #expect(try await AssistantResponseRepository(store: fixture.store).response(messageID: fixture.messageID) != nil)
    }

    @Test func existingConflictingMessageRejectsCompanionReconciliation() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        try await fixture.seedConversation()
        try await fixture.store.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, 'assistant', 'Different response', ?)",
                arguments: [fixture.messageID, fixture.conversationID, fixture.write.message.createdAtMS]
            )
        }

        await #expect(throws: RepositoryError.mutationCollision) {
            try await AssistantResponseRepository(store: fixture.store).persist(fixture.write)
        }
        #expect(try await fixture.companionCounts() == [1, 0, 0, 0])
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

    @Test func olderFeedbackCompletionCannotOverwriteNewerSelection() async throws {
        let fixture = try await Fixture(); defer { fixture.remove() }
        try await fixture.seedConversation()
        let repository = AssistantResponseRepository(store: fixture.store)
        try await repository.persist(fixture.write)
        try await repository.upsertFeedback(.init(
            responseMessageID: fixture.messageID, direction: .helpful,
            factors: [.coverage], detail: nil, updatedAtMS: 31
        ))
        try await repository.upsertFeedback(.init(
            responseMessageID: fixture.messageID, direction: .notHelpful,
            factors: [.intentAlignment], detail: nil, updatedAtMS: 30
        ))
        let feedback = try #require(await repository.response(messageID: fixture.messageID)?.feedback)
        #expect(feedback.direction == .helpful)
        #expect(feedback.factors == [.coverage])
    }

    @Test func materializedPreferenceProfileIsBoundedCanonicalAndLocal() async throws {
        let fixture = try await Fixture(); defer { fixture.remove() }
        let repository = AssistantResponseRepository(store: fixture.store)
        try await repository.replacePreferenceProfile([
            .init(factor: .relationalFit, direction: .helpful),
            .init(factor: .coverage, direction: .notHelpful),
        ], updatedAtMS: 40)
        #expect(try await repository.preferenceProfile() == [
            .init(factor: .coverage, direction: .notHelpful),
            .init(factor: .relationalFit, direction: .helpful),
        ])
        #expect(try await ChangeJournal(store: fixture.store).pending(limit: 10).isEmpty)
    }

    @Test func sourceDisplayIgnoresProviderExcerptAndUsesOnlyLocalTruth() async throws {
        let fixture = try await Fixture(); defer { fixture.remove() }
        try await fixture.seedConversation()
        let repository = AssistantResponseRepository(store: fixture.store)
        try await repository.persist(fixture.write)
        let stored = try #require(await repository.response(messageID: fixture.messageID))
        let resolved = try #require(await repository.resolveSources(in: [fixture.messageID: stored])[fixture.messageID])
        #expect(resolved.sources.map(\.excerpt) == [nil, nil])
    }

    @Test func tombstonedLocalSourceIsNeverDisclosed() async throws {
        let fixture = try await Fixture(); defer { fixture.remove() }
        try await fixture.seedConversation()
        let repository = AssistantResponseRepository(store: fixture.store)
        let source = AssistantResponseSourceRecord(
            id: "10000000-0000-4000-8000-000000000007",
            responseMessageID: fixture.messageID, ordinal: 0,
            sourceID: fixture.messageID, sourceType: "message", excerpt: "provider text"
        )
        let write = AssistantResponseWrite(
            message: fixture.write.message, metadata: fixture.write.metadata,
            sources: [source], proposal: fixture.write.proposal
        )
        try await repository.persist(write)
        let stored = try #require(await repository.response(messageID: fixture.messageID))
        #expect(try await repository.resolveSources(in: [fixture.messageID: stored])[fixture.messageID]?.sources.first?.excerpt == "A grounded response")
        try await fixture.store.write { db in
            try db.execute(
                sql: "INSERT INTO tombstones (id, entity_type, entity_id, deletion_version_id, deleted_at_ms) VALUES (?, 'message', ?, ?, 30)",
                arguments: [UUID().uuidString, fixture.messageID, UUID().uuidString]
            )
        }
        #expect(try await repository.resolveSources(in: [fixture.messageID: stored])[fixture.messageID]?.sources.first?.excerpt == nil)
    }

    @Test func proposalDestinationAndResolutionRollbackTogetherThenRetry() async throws {
        let fixture = try await Fixture(); defer { fixture.remove() }
        try await fixture.seedConversation()
        let responses = AssistantResponseRepository(store: fixture.store)
        try await responses.persist(fixture.write)
        let targetID = "10000000-0000-4000-8000-000000000020"
        let versionID = "10000000-0000-4000-8000-000000000021"
        let destination = AssistantProposalDestination.goal(.init(
            id: targetID, title: "Atomic goal", detail: "", status: "active",
            createdAtMS: 20, updatedAtMS: 20
        ))
        let context = MutationContext(
            id: versionID, deviceID: "10000000-0000-4000-8000-000000000022", timestamp: 20
        )
        let failing = AssistantProposalAcceptanceRepository(store: fixture.store, failAfterDestination: true)
        await #expect(throws: AssistantProposalAcceptanceError.injectedFailure) {
            try await failing.accept(
                proposalID: "10000000-0000-4000-8000-000000000006", payloadDigest: "digest-1",
                destination: destination, context: context, targetType: "goal", targetID: targetID,
                targetVersionID: versionID, decisionReceipt: "accepted:test", resolvedAtMS: 30
            )
        }
        #expect(try await GoalRepository(store: fixture.store).get(id: targetID) == nil)
        #expect(try await responses.proposal(id: "10000000-0000-4000-8000-000000000006")?.state == .pending)

        let accepted = try await AssistantProposalAcceptanceRepository(store: fixture.store).accept(
            proposalID: "10000000-0000-4000-8000-000000000006", payloadDigest: "digest-1",
            destination: destination, context: context, targetType: "goal", targetID: targetID,
            targetVersionID: versionID, decisionReceipt: "accepted:test", resolvedAtMS: 30
        )
        #expect(accepted.state == .accepted)
        #expect(try await GoalRepository(store: fixture.store).get(id: targetID)?.title == "Atomic goal")
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
