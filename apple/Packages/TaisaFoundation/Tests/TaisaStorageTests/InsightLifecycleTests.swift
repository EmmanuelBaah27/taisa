import Foundation
import GRDB
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct InsightLifecycleTests {
    @Test func proposalStaysOutOfCurrentUntilConfirmedWithInspectableSource() async throws {
        let fixture = try await InsightFixture()
        defer { fixture.remove() }
        let source = try await fixture.createConversation()

        let proposal = try await fixture.commands.propose(
            body: "Morning focus improves delivery.",
            sourceType: "conversation",
            sourceID: source.id,
            context: fixture.context(10)
        )
        #expect(try await fixture.query.current().isEmpty)
        #expect(try await fixture.query.lead(atMS: 100) == nil)

        let confirmed = try await fixture.commands.confirm(
            proposalID: proposal.id,
            editedBody: nil,
            isTimeSensitive: true,
            homeEligibleUntilMS: 1_000,
            context: fixture.context(20)
        )

        #expect(try await fixture.query.current() == [confirmed])
        #expect(try await fixture.query.lead(atMS: 100) == confirmed)
        #expect(try await fixture.query.sources(insightID: confirmed.id).map(\.sourceID) == [source.id])
        #expect(try await fixture.query.revisions(insightID: confirmed.id).map(\.status) == [.accepted])
    }

    @Test func confirmationRejectsMissingSourceWithoutCreatingTruth() async throws {
        let fixture = try await InsightFixture()
        defer { fixture.remove() }
        let proposal = try await fixture.commands.propose(
            body: "Unsupported claim",
            sourceType: "conversation",
            sourceID: UUID().uuidString,
            context: fixture.context(10)
        )

        await #expect(throws: InsightCommandError.sourceNotFound) {
            try await fixture.commands.confirm(proposalID: proposal.id, editedBody: nil, isTimeSensitive: false, homeEligibleUntilMS: nil, context: fixture.context(20))
        }
        #expect(try await fixture.query.current().isEmpty)
    }

    @Test func supportingEvidenceDoesNotRewriteMeaningAndContradictionRequiresReview() async throws {
        let fixture = try await InsightFixture()
        defer { fixture.remove() }
        let first = try await fixture.createConversation(title: "First")
        let second = try await fixture.createConversation(title: "Second")
        let proposal = try await fixture.commands.propose(body: "Protect mornings.", sourceType: "conversation", sourceID: first.id, context: fixture.context(10))
        let insight = try await fixture.commands.confirm(proposalID: proposal.id, editedBody: nil, isTimeSensitive: true, homeEligibleUntilMS: 1_000, context: fixture.context(20))

        try await fixture.commands.addSupportingEvidence(insightID: insight.id, sourceType: "conversation", sourceID: second.id, excerpt: "Repeated pattern", context: fixture.context(30))
        #expect(try await fixture.query.current().first?.body == "Protect mornings.")
        #expect(try await fixture.query.sources(insightID: insight.id).count == 2)

        try await fixture.commands.flagContradiction(insightID: insight.id, context: fixture.context(40))
        #expect(try await fixture.query.current().isEmpty)
        #expect(try await fixture.query.reviewNeeded().map(\.id) == [insight.id])
        #expect(try await fixture.query.lead(atMS: 100) == nil)
    }

    @Test func confirmationRollsBackEveryRecordWhenEvidenceLinkFails() async throws {
        let fixture = try await InsightFixture()
        defer { fixture.remove() }
        let source = try await fixture.createConversation()
        let proposal = try await fixture.commands.propose(body: "Atomic truth", sourceType: "conversation", sourceID: source.id, context: fixture.context(10))
        try await fixture.store.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_insight_source BEFORE INSERT ON insight_sources BEGIN SELECT RAISE(ABORT, 'forced failure'); END")
        }

        await #expect(throws: RepositoryError.persistenceFailed) {
            try await fixture.commands.confirm(proposalID: proposal.id, editedBody: nil, isTimeSensitive: true, homeEligibleUntilMS: 1_000, context: fixture.context(20))
        }

        #expect(try await fixture.query.current().isEmpty)
        #expect(try await fixture.commands.proposal(id: proposal.id)?.status == .proposed)
        #expect(try await fixture.store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE entity_type IN ('insight', 'insight_source')") } == 0)
    }

    @Test func revisionMustBeAcceptedBeforeItChangesConfirmedMeaning() async throws {
        let fixture = try await InsightFixture()
        defer { fixture.remove() }
        let source = try await fixture.createConversation()
        let initial = try await fixture.commands.propose(body: "Protect mornings.", sourceType: "conversation", sourceID: source.id, context: fixture.context(10))
        let insight = try await fixture.commands.confirm(proposalID: initial.id, editedBody: nil, isTimeSensitive: false, homeEligibleUntilMS: nil, context: fixture.context(20))

        let revision = try await fixture.commands.proposeRevision(insightID: insight.id, body: "Protect the first focus block.", sourceType: "conversation", sourceID: source.id, context: fixture.context(30))
        #expect(try await fixture.query.current().first?.body == "Protect mornings.")
        try await fixture.commands.acceptRevision(id: revision.id, context: fixture.context(40))
        #expect(try await fixture.query.current().first?.body == "Protect the first focus block.")
        #expect(try await fixture.query.revisions(insightID: insight.id).map(\.status) == [.accepted, .accepted])
    }

    @Test func retainRefineAndRetireResolveReviewWithoutLosingHistory() async throws {
        let fixture = try await InsightFixture()
        defer { fixture.remove() }
        let source = try await fixture.createConversation()
        let initial = try await fixture.commands.propose(body: "Old meaning", sourceType: "conversation", sourceID: source.id, context: fixture.context(10))
        let retained = try await fixture.commands.confirm(proposalID: initial.id, editedBody: nil, isTimeSensitive: true, homeEligibleUntilMS: 1_000, context: fixture.context(20))
        try await fixture.commands.flagContradiction(insightID: retained.id, context: fixture.context(30))
        try await fixture.commands.retain(insightID: retained.id, context: fixture.context(40))
        #expect(try await fixture.query.current().map(\.id) == [retained.id])

        try await fixture.commands.flagContradiction(insightID: retained.id, context: fixture.context(50))
        let refined = try await fixture.commands.refine(insightID: retained.id, body: "New meaning", sourceType: "conversation", sourceID: source.id, context: fixture.context(60))
        #expect(try await fixture.query.current().map(\.id) == [refined.id])
        #expect(try await fixture.query.history().map(\.id) == [retained.id])

        try await fixture.commands.flagContradiction(insightID: refined.id, context: fixture.context(70))
        try await fixture.commands.retire(insightID: refined.id, context: fixture.context(80))
        #expect(try await fixture.query.current().isEmpty)
        #expect(Set(try await fixture.query.history().map(\.id)) == Set([retained.id, refined.id]))
    }

    @Test func leadSelectionIsDeterministicAndExcludesExpiredInsights() async throws {
        let fixture = try await InsightFixture()
        defer { fixture.remove() }
        let source = try await fixture.createConversation()
        for (body, expiry, time) in [("Later", Int64(900), Int64(10)), ("Sooner", Int64(500), Int64(20)), ("Expired", Int64(99), Int64(30))] {
            let proposal = try await fixture.commands.propose(body: body, sourceType: "conversation", sourceID: source.id, context: fixture.context(time))
            _ = try await fixture.commands.confirm(proposalID: proposal.id, editedBody: nil, isTimeSensitive: true, homeEligibleUntilMS: expiry, context: fixture.context(time + 1))
        }
        #expect(try await fixture.query.lead(atMS: 100)?.body == "Sooner")
    }
}

private struct InsightFixture {
    let directory: URL
    let store: TaisaStore
    let commands: InsightCommandRepository
    let query: InsightQuery
    let deviceID = UUID().uuidString

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: InsightKeys())
        commands = InsightCommandRepository(store: store)
        query = InsightQuery(store: store)
    }
    func createConversation(title: String = "Source") async throws -> ConversationRecord {
        let record = ConversationRecord(id: UUID().uuidString, title: title, createdAtMS: 1, updatedAtMS: 1)
        try await ConversationRepository(store: store).create(record, context: context(1))
        return record
    }
    func context(_ timestamp: Int64) -> MutationContext { .init(id: UUID().uuidString, deviceID: deviceID, timestamp: timestamp) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor InsightKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
