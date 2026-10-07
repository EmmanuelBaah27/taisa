import Foundation
import GRDB

public enum InsightCommandError: Error, Sendable, Equatable {
    case proposalNotFound
    case insightNotFound
    case sourceNotFound
    case invalidState
}

public struct InsightCommandRepository: Sendable {
    private let store: TaisaStore
    private let insights: InsightRepository
    private let sources: InsightSourceRepository
    private let revisions: InsightRevisionRepository

    public init(store: TaisaStore) {
        self.store = store
        insights = InsightRepository(store: store)
        sources = InsightSourceRepository(store: store)
        revisions = InsightRevisionRepository(store: store)
    }

    public func propose(body: String, sourceType: String, sourceID: String, context: MutationContext) async throws -> InsightRevisionRecord {
        let proposal = InsightRevisionRecord(id: UUID().uuidString, insightID: nil, proposedBody: body, status: .proposed, sourceType: sourceType, sourceID: sourceID, createdAtMS: context.timestamp, resolvedAtMS: nil)
        try await revisions.create(proposal, context: context)
        return proposal
    }

    public func confirm(proposalID: String, editedBody: String?, isTimeSensitive: Bool, homeEligibleUntilMS: Int64?, context: MutationContext) async throws -> InsightRecord {
        guard let proposal = try await revisions.get(id: proposalID) else { throw InsightCommandError.proposalNotFound }
        guard proposal.status == .proposed, proposal.insightID == nil else { throw InsightCommandError.invalidState }
        guard let sourceID = proposal.sourceID, try await sourceExists(type: proposal.sourceType, id: sourceID) else {
            throw InsightCommandError.sourceNotFound
        }
        let insight = InsightRecord(id: UUID().uuidString, body: editedBody ?? proposal.proposedBody, status: .confirmed, isTimeSensitive: isTimeSensitive, homeEligibleUntilMS: homeEligibleUntilMS, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
        try await atomicWrite { db in
            try insights.core.create(insight, context: context, db: db)
            try sources.core.create(
                InsightSourceRecord(id: UUID().uuidString, insightID: insight.id, sourceType: proposal.sourceType, sourceID: sourceID, excerpt: "", createdAtMS: context.timestamp),
                context: childContext(context), db: db
            )
            try revisions.core.update(
                InsightRevisionRecord(id: proposal.id, insightID: insight.id, proposedBody: proposal.proposedBody, status: .accepted, sourceType: proposal.sourceType, sourceID: sourceID, createdAtMS: proposal.createdAtMS, resolvedAtMS: context.timestamp),
                context: childContext(context), db: db
            )
        }
        return insight
    }

    public func proposal(id: String) async throws -> InsightRevisionRecord? { try await revisions.get(id: id) }

    public func proposeRevision(insightID: String, body: String, sourceType: String, sourceID: String, context: MutationContext) async throws -> InsightRevisionRecord {
        guard try await insights.get(id: insightID) != nil else { throw InsightCommandError.insightNotFound }
        guard try await sourceExists(type: sourceType, id: sourceID) else { throw InsightCommandError.sourceNotFound }
        let revision = InsightRevisionRecord(id: UUID().uuidString, insightID: insightID, proposedBody: body, status: .proposed, sourceType: sourceType, sourceID: sourceID, createdAtMS: context.timestamp, resolvedAtMS: nil)
        try await revisions.create(revision, context: context)
        return revision
    }

    public func acceptRevision(id: String, context: MutationContext) async throws {
        guard let revision = try await revisions.get(id: id) else { throw InsightCommandError.proposalNotFound }
        guard revision.status == .proposed, let insightID = revision.insightID,
              let insight = try await insights.get(id: insightID) else { throw InsightCommandError.invalidState }
        try await atomicWrite { db in
            try insights.core.update(InsightRecord(id: insight.id, body: revision.proposedBody, status: .confirmed, isTimeSensitive: insight.isTimeSensitive, homeEligibleUntilMS: insight.homeEligibleUntilMS, createdAtMS: insight.createdAtMS, updatedAtMS: context.timestamp), context: context, db: db)
            try revisions.core.update(InsightRevisionRecord(id: revision.id, insightID: insight.id, proposedBody: revision.proposedBody, status: .accepted, sourceType: revision.sourceType, sourceID: revision.sourceID, createdAtMS: revision.createdAtMS, resolvedAtMS: context.timestamp), context: childContext(context), db: db)
        }
    }

    public func addSupportingEvidence(insightID: String, sourceType: String, sourceID: String, excerpt: String, context: MutationContext) async throws {
        guard try await insights.get(id: insightID) != nil else { throw InsightCommandError.insightNotFound }
        guard try await sourceExists(type: sourceType, id: sourceID) else { throw InsightCommandError.sourceNotFound }
        try await sources.create(
            InsightSourceRecord(id: UUID().uuidString, insightID: insightID, sourceType: sourceType, sourceID: sourceID, excerpt: excerpt, createdAtMS: context.timestamp),
            context: context
        )
    }

    public func flagContradiction(insightID: String, context: MutationContext) async throws {
        guard let insight = try await insights.get(id: insightID) else { throw InsightCommandError.insightNotFound }
        try await insights.update(
            InsightRecord(id: insight.id, body: insight.body, status: .reviewNeeded, isTimeSensitive: false, homeEligibleUntilMS: nil, createdAtMS: insight.createdAtMS, updatedAtMS: context.timestamp),
            context: context
        )
    }

    public func retain(insightID: String, context: MutationContext) async throws {
        guard let insight = try await insights.get(id: insightID) else { throw InsightCommandError.insightNotFound }
        guard insight.status == .reviewNeeded else { throw InsightCommandError.invalidState }
        try await insights.update(InsightRecord(id: insight.id, body: insight.body, status: .confirmed, isTimeSensitive: false, homeEligibleUntilMS: nil, createdAtMS: insight.createdAtMS, updatedAtMS: context.timestamp), context: context)
    }

    public func refine(insightID: String, body: String, sourceType: String, sourceID: String, context: MutationContext) async throws -> InsightRecord {
        guard let old = try await insights.get(id: insightID) else { throw InsightCommandError.insightNotFound }
        guard old.status == .reviewNeeded else { throw InsightCommandError.invalidState }
        guard try await sourceExists(type: sourceType, id: sourceID) else { throw InsightCommandError.sourceNotFound }
        let refined = InsightRecord(id: UUID().uuidString, body: body, status: .confirmed, isTimeSensitive: false, homeEligibleUntilMS: nil, createdAtMS: context.timestamp, updatedAtMS: context.timestamp)
        let revision = InsightRevisionRecord(id: UUID().uuidString, insightID: refined.id, proposedBody: body, status: .accepted, sourceType: sourceType, sourceID: sourceID, createdAtMS: context.timestamp, resolvedAtMS: context.timestamp)
        try await atomicWrite { db in
            try insights.core.update(InsightRecord(id: old.id, body: old.body, status: .superseded, isTimeSensitive: false, homeEligibleUntilMS: nil, createdAtMS: old.createdAtMS, updatedAtMS: context.timestamp), context: context, db: db)
            try insights.core.create(refined, context: childContext(context), db: db)
            try sources.core.create(InsightSourceRecord(id: UUID().uuidString, insightID: refined.id, sourceType: sourceType, sourceID: sourceID, excerpt: "", createdAtMS: context.timestamp), context: childContext(context), db: db)
            try revisions.core.create(revision, context: childContext(context), db: db)
        }
        return refined
    }

    public func retire(insightID: String, context: MutationContext) async throws {
        guard let insight = try await insights.get(id: insightID) else { throw InsightCommandError.insightNotFound }
        guard insight.status == .reviewNeeded else { throw InsightCommandError.invalidState }
        try await insights.update(InsightRecord(id: insight.id, body: insight.body, status: .retired, isTimeSensitive: false, homeEligibleUntilMS: nil, createdAtMS: insight.createdAtMS, updatedAtMS: context.timestamp), context: context)
    }

    private func atomicWrite(_ body: @Sendable (Database) throws -> Void) async throws {
        do { try await store.write(body) }
        catch let error as InsightCommandError { throw error }
        catch let error as RepositoryError { throw error }
        catch { throw RepositoryError.persistenceFailed }
    }

    private func childContext(_ context: MutationContext) -> MutationContext {
        MutationContext(id: UUID().uuidString, deviceID: context.deviceID, timestamp: context.timestamp)
    }

    private func sourceExists(type: String, id: String) async throws -> Bool {
        let table: String
        switch type {
        case "conversation": table = "conversations"
        case "message": table = "messages"
        case "evidence": table = "evidence"
        case "action": table = "actions"
        default: return false
        }
        return try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE id = ? COLLATE NOCASE", arguments: [id]) == 1
        }
    }
}
