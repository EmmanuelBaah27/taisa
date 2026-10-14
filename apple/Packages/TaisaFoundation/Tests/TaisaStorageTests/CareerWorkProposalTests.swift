import Foundation
import GRDB
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct CareerWorkProposalTests {
    private let goalID = "11111111-1111-4111-8111-111111111111"
    private let proposalID = "22222222-2222-4222-8222-222222222222"
    private let actionID = "33333333-3333-4333-8333-333333333333"
    private let targetVersionID = "44444444-4444-4444-8444-444444444444"

    @Test func exactReviewedPayloadIsAcceptedOnceWithLiteralDigestAndReceipt() async throws {
        let fixture = try await ProposalFixture()
        defer { fixture.remove() }
        let goalVersion = "55555555-5555-4555-8555-555555555555"
        _ = try await fixture.commands.createGoal(id: goalID, title: "Launch", detail: "", source: .user, sourceID: nil, context: fixture.context(goalVersion, 10))
        let proposal = actionProposal(goalVersion: goalVersion)

        #expect(proposal.computedPayloadDigest == "e71348f340bc2ad7dde69551665e05b0677bc008b85fce79db462b5ffa8eabb7")
        let first = try await fixture.proposals.accept(proposal, context: fixture.context(UUID().uuidString, 20))
        let replay = try await fixture.proposals.accept(proposal, context: fixture.context(UUID().uuidString, 30))

        #expect(first == replay)
        #expect(first.decision == .accepted)
        #expect(try await ActionRepository(store: fixture.store).get(id: actionID)?.title == "Draft plan")
        let receipt = try await fixture.receipt(proposalID)
        #expect(receipt?.digest == proposal.payloadDigest)
        #expect(receipt?.targetVersionID == targetVersionID)
        #expect(try await fixture.count("actions") == 1)
    }

    @Test func correctedPayloadIsTheOnlyPayloadApplied() async throws {
        let fixture = try await ProposalFixture()
        defer { fixture.remove() }
        let goalVersion = UUID().uuidString
        _ = try await fixture.commands.createGoal(id: goalID, title: "Launch", detail: "", source: .user, sourceID: nil, context: fixture.context(goalVersion, 10))
        let original = actionProposal(goalVersion: goalVersion)
        let corrected = CareerWorkProposalPayload.action(goalID: goalID, title: "Draft rollout", detail: "Deliver clearly", dueAtMS: 500)
        let digest = "ef3e798e847690629a2abc1e7d21870c7fc5f8af030be295604fd9982b5cff21"

        let result = try await fixture.proposals.correct(original, with: corrected, payloadDigest: digest, context: fixture.context(UUID().uuidString, 20))

        #expect(result.decision == .corrected)
        let action = try #require(try await ActionRepository(store: fixture.store).get(id: actionID))
        #expect(action.title == "Draft rollout")
        #expect(action.detail == "Deliver clearly")
        #expect(action.dueAtMS == 500)
        #expect(try await fixture.receipt(proposalID)?.digest == digest)
    }

    @Test func rejectionRecordsDecisionWithoutCreatingCareerWork() async throws {
        let fixture = try await ProposalFixture()
        defer { fixture.remove() }
        let goalVersion = UUID().uuidString
        _ = try await fixture.commands.createGoal(id: goalID, title: "Launch", detail: "", source: .user, sourceID: nil, context: fixture.context(goalVersion, 10))
        let proposal = actionProposal(goalVersion: goalVersion)

        let first = try await fixture.proposals.reject(proposal, context: fixture.context(UUID().uuidString, 20))
        let replay = try await fixture.proposals.reject(proposal, context: fixture.context(UUID().uuidString, 30))

        #expect(first == replay)
        #expect(first.decision == .rejected)
        #expect(try await ActionRepository(store: fixture.store).get(id: actionID) == nil)
    }

    @Test func goalMilestoneAndEvidenceProposalsUseTheSameExplicitBoundary() async throws {
        let fixture = try await ProposalFixture()
        defer { fixture.remove() }
        let proposedGoalID = UUID().uuidString
        let goalPayload = CareerWorkProposalPayload.goal(title: "Own the launch", detail: "Lead delivery")
        let goalProposal = CareerWorkProposal(id: UUID().uuidString, targetID: proposedGoalID, targetVersionID: UUID().uuidString, basis: nil, payload: goalPayload, payloadDigest: goalPayload.digest)
        _ = try await fixture.proposals.accept(goalProposal, context: fixture.context(UUID().uuidString, 10))

        let goalVersion = try await fixture.recordVersion(entity: "goal", id: proposedGoalID)
        let milestonePayload = CareerWorkProposalPayload.milestone(goalID: proposedGoalID, title: "Beta", targetAtMS: 500)
        let milestoneProposal = CareerWorkProposal(id: UUID().uuidString, targetID: UUID().uuidString, targetVersionID: UUID().uuidString, basis: .init(entity: .goal, id: proposedGoalID, versionID: goalVersion), payload: milestonePayload, payloadDigest: milestonePayload.digest)
        _ = try await fixture.proposals.accept(milestoneProposal, context: fixture.context(UUID().uuidString, 20))

        let evidencePayload = CareerWorkProposalPayload.evidence(goalID: proposedGoalID, actionID: nil, title: "Beta approved", detail: "", occurredAtMS: 25, origin: .conversation, originID: UUID().uuidString)
        let evidenceProposal = CareerWorkProposal(id: UUID().uuidString, targetID: UUID().uuidString, targetVersionID: UUID().uuidString, basis: .init(entity: .goal, id: proposedGoalID, versionID: goalVersion), payload: evidencePayload, payloadDigest: evidencePayload.digest)
        _ = try await fixture.proposals.accept(evidenceProposal, context: fixture.context(UUID().uuidString, 30))

        let snapshot = try #require(try await CareerWorkQuery(store: fixture.store).goal(id: proposedGoalID))
        #expect(snapshot.milestones.map(\.title) == ["Beta"])
        #expect(snapshot.evidence.map(\.title) == ["Beta approved"])
        #expect(snapshot.provenance.first?.origin == .conversation)
    }

    @Test func staleBasisAndDigestMismatchFailClosedWithoutReceiptOrMutation() async throws {
        let fixture = try await ProposalFixture()
        defer { fixture.remove() }
        let oldVersion = UUID().uuidString
        let goal = try await fixture.commands.createGoal(id: goalID, title: "Launch", detail: "", source: .user, sourceID: nil, context: fixture.context(oldVersion, 10))
        _ = try await GoalRepository(store: fixture.store).update(
            .init(id: goal.id, title: "Changed", detail: goal.detail, status: goal.status, createdAtMS: goal.createdAtMS, updatedAtMS: 15),
            context: fixture.context(UUID().uuidString, 15)
        )
        let stale = actionProposal(goalVersion: oldVersion)

        await #expect(throws: CareerWorkProposalError.staleTarget) {
            try await fixture.proposals.accept(stale, context: fixture.context(UUID().uuidString, 20))
        }
        var mismatched = actionProposal(goalVersion: try await fixture.recordVersion(entity: "goal", id: goalID))
        mismatched = .init(id: mismatched.id, targetID: mismatched.targetID, targetVersionID: mismatched.targetVersionID, basis: mismatched.basis, payload: mismatched.payload, payloadDigest: String(repeating: "0", count: 64))
        await #expect(throws: CareerWorkProposalError.payloadMismatch) {
            try await fixture.proposals.accept(mismatched, context: fixture.context(UUID().uuidString, 30))
        }
        #expect(try await fixture.count("career_work_proposal_receipts") == 0)
        #expect(try await fixture.count("actions") == 0)
    }

    @Test func undoIsIdempotent() async throws {
        let fixture = try await ProposalFixture()
        defer { fixture.remove() }
        let goalVersion = UUID().uuidString
        _ = try await fixture.commands.createGoal(id: goalID, title: "Launch", detail: "", source: .user, sourceID: nil, context: fixture.context(goalVersion, 10))
        let proposal = actionProposal(goalVersion: goalVersion)
        _ = try await fixture.proposals.accept(proposal, context: fixture.context(UUID().uuidString, 20))

        let undone = try await fixture.proposals.undo(proposalID: proposalID, payloadDigest: proposal.payloadDigest, context: fixture.context(UUID().uuidString, 30))
        let replay = try await fixture.proposals.undo(proposalID: proposalID, payloadDigest: proposal.payloadDigest, context: fixture.context(UUID().uuidString, 40))
        #expect(undone == replay)
        #expect(undone.decision == .undone)
        #expect(try await ActionRepository(store: fixture.store).get(id: actionID) == nil)
    }

    @Test func undoRefusesToEraseLaterEdits() async throws {
        let fixture = try await ProposalFixture()
        defer { fixture.remove() }
        let goalVersion = UUID().uuidString
        _ = try await fixture.commands.createGoal(id: goalID, title: "Launch", detail: "", source: .user, sourceID: nil, context: fixture.context(goalVersion, 10))
        let proposal = actionProposal(goalVersion: goalVersion)
        _ = try await fixture.proposals.accept(proposal, context: fixture.context(UUID().uuidString, 20))
        let action = try #require(try await ActionRepository(store: fixture.store).get(id: actionID))
        try await ActionRepository(store: fixture.store).update(
            .init(id: action.id, goalID: action.goalID, title: "User changed this", detail: action.detail, status: action.status, dueAtMS: action.dueAtMS, createdAtMS: action.createdAtMS, updatedAtMS: 25),
            context: fixture.context(UUID().uuidString, 25)
        )

        await #expect(throws: CareerWorkProposalError.staleTarget) {
            try await fixture.proposals.undo(proposalID: proposalID, payloadDigest: proposal.payloadDigest, context: fixture.context(UUID().uuidString, 30))
        }
        #expect(try await ActionRepository(store: fixture.store).get(id: actionID)?.title == "User changed this")
        #expect(try await fixture.receipt(proposalID)?.digest == proposal.payloadDigest)
    }

    private func actionProposal(goalVersion: String) -> CareerWorkProposal {
        .init(
            id: proposalID,
            targetID: actionID,
            targetVersionID: targetVersionID,
            basis: .init(entity: .goal, id: goalID, versionID: goalVersion),
            payload: .action(goalID: goalID, title: "Draft plan", detail: "Deliver", dueAtMS: nil),
            payloadDigest: "e71348f340bc2ad7dde69551665e05b0677bc008b85fce79db462b5ffa8eabb7"
        )
    }
}

private struct ProposalFixture {
    let directory: URL
    let store: TaisaStore
    let commands: CareerWorkCommandRepository
    let proposals: CareerWorkProposalRepository
    let deviceID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: ProposalKeys())
        commands = CareerWorkCommandRepository(store: store)
        proposals = CareerWorkProposalRepository(store: store)
    }

    func context(_ id: String, _ timestamp: Int64) -> MutationContext { .init(id: id, deviceID: deviceID, timestamp: timestamp) }
    func count(_ table: String) async throws -> Int { try await store.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM \(table)") ?? 0 } }
    func recordVersion(entity: String, id: String) async throws -> String {
        try await store.read { db in
            guard let version = try String.fetchOne(db, sql: "SELECT version_id FROM field_versions WHERE entity_type = ? AND entity_id = ? AND field_name = '__record' ORDER BY rowid DESC LIMIT 1", arguments: [entity, id]) else {
                throw CareerWorkProposalError.staleTarget
            }
            return version
        }
    }
    func receipt(_ id: String) async throws -> (digest: String, targetVersionID: String)? {
        try await store.read { db in
            try Row.fetchOne(db, sql: "SELECT payload_digest, target_version_id FROM career_work_proposal_receipts WHERE proposal_id = ?", arguments: [id]).map { ($0["payload_digest"], $0["target_version_id"]) }
        }
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor ProposalKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}
