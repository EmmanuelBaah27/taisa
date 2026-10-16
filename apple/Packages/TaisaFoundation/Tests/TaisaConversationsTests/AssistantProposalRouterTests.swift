import CryptoKit
import Foundation
import Testing
import TaisaContracts
import TaisaStorage
@testable import TaisaConversations

private actor ProposalRouterTestKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

@Suite(.serialized)
struct AssistantProposalRouterTests {
    @Test func routesAllSixKindsAndReplaysAcceptIdempotently() async throws {
        let fixture = try await proposalFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let router = AssistantProposalRouter(store: fixture.store)
        let deviceID = UUID(uuidString: "00000000-0000-4000-8000-000000000999")!

        let goal = try await accept(
            #"{"kind":"goal","title":"Lead planning","description":"Own the process","priority":"high","targetDate":null}"#,
            ordinal: 1, fixture: fixture, router: router, deviceID: deviceID
        )
        #expect(try await GoalRepository(store: fixture.store).get(id: goal.targetID!)?.title == "Lead planning")

        let action = try await accept(
            #"{"kind":"action","title":"Draft agenda","description":null,"priority":"medium","dueAt":null,"goalId":null}"#,
            ordinal: 2, fixture: fixture, router: router, deviceID: deviceID
        )
        #expect(try await ActionRepository(store: fixture.store).get(id: action.targetID!)?.title == "Draft agenda")

        let weekly = try await accept(
            #"{"kind":"weekly_work","actionId":"\#(action.targetID!)","weekStart":"2026-10-12T00:00:00.000Z","plannedDay":"2026-10-14T00:00:00.000Z"}"#,
            ordinal: 3, fixture: fixture, router: router, deviceID: deviceID
        )
        #expect(weekly.targetID == action.targetID)
        let weekDate = try #require(ISO8601DateFormatter().date(from: "2026-10-12T00:00:00Z"))
        let week = try await WeeklyWorkQuery(store: fixture.store).snapshot(
            weekContaining: weekDate,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        #expect(week.items.contains(where: { $0.action.id == action.targetID }))

        let evidence = try await accept(
            #"{"kind":"evidence","statement":"Led the planning session","occurredAt":"2026-10-15T00:00:00.000Z","goalId":"\#(goal.targetID!)","actionId":null}"#,
            ordinal: 4, fixture: fixture, router: router, deviceID: deviceID
        )
        #expect(try await EvidenceRepository(store: fixture.store).get(id: evidence.targetID!)?.goalID == goal.targetID)

        let memory = try await accept(
            #"{"kind":"memory","memory":{"operation":"propose","candidate":{"type":"preference","statement":"Prefers concise options","provenance":"user-stated","lifecycle":"proposed","confidence":"tentative","sourceMessageIds":[],"supersedesId":null},"reason":"Stated directly","requiresConfirmation":true}}"#,
            ordinal: 5, fixture: fixture, router: router, deviceID: deviceID
        )
        #expect(try await MemoryRepository(store: fixture.store).get(id: memory.targetID!)?.content == "Prefers concise options")

        let insight = try await accept(
            #"{"kind":"insight","body":"Planning improves when ownership is explicit.","isTimeSensitive":false,"homeEligibleUntil":null}"#,
            ordinal: 6, fixture: fixture, router: router, deviceID: deviceID
        )
        #expect(try await InsightRepository(store: fixture.store).get(id: insight.targetID!)?.status == .reviewNeeded)
    }

    @Test func dismissDoesNotWriteDestinationAndStaleTargetBecomesExplicit() async throws {
        let fixture = try await proposalFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let router = AssistantProposalRouter(store: fixture.store)
        let dismissedID = try await store(
            #"{"kind":"goal","title":"Do not create","description":null,"priority":null,"targetDate":null}"#,
            ordinal: 10, fixture: fixture
        )
        let dismissed = try await router.dismiss(proposalID: dismissedID, resolvedAtMS: 20)
        #expect(dismissed.state == .dismissed)
        #expect(dismissed.targetID == nil)

        let staleID = try await store(
            #"{"kind":"weekly_work","actionId":"00000000-0000-4000-8000-000000000123","weekStart":"2026-10-12T00:00:00.000Z","plannedDay":null}"#,
            ordinal: 11, fixture: fixture
        )
        let stale = try await router.accept(
            proposalID: staleID,
            deviceID: UUID(uuidString: "00000000-0000-4000-8000-000000000999")!,
            resolvedAtMS: 21
        )
        #expect(stale.state == .stale)
        #expect(try await router.accept(
            proposalID: staleID,
            deviceID: UUID(uuidString: "00000000-0000-4000-8000-000000000999")!,
            resolvedAtMS: 22
        ) == stale)
    }
}

private func accept(
    _ json: String,
    ordinal: Int,
    fixture: (directory: URL, store: TaisaStore, conversationID: String),
    router: AssistantProposalRouter,
    deviceID: UUID
) async throws -> AssistantProposalRecord {
    let id = try await store(json, ordinal: ordinal, fixture: fixture)
    let first = try await router.accept(proposalID: id, deviceID: deviceID, resolvedAtMS: Int64(100 + ordinal))
    let replay = try await router.accept(proposalID: id, deviceID: deviceID, resolvedAtMS: Int64(200 + ordinal))
    #expect(replay == first)
    return first
}

private func store(
    _ json: String,
    ordinal: Int,
    fixture: (directory: URL, store: TaisaStore, conversationID: String)
) async throws -> String {
    let proposal = try JSONDecoder().decode(CoachingProposal.self, from: Data(json.utf8))
    let payload = try JSONEncoder().encode(proposal)
    let messageID = String(format: "00000000-0000-4000-8000-%012d", ordinal)
    let proposalID = String(format: "10000000-0000-4000-8000-%012d", ordinal)
    let message = MessageRecord(
        id: messageID, conversationID: fixture.conversationID,
        role: "assistant", body: "Reply \(ordinal)", createdAtMS: Int64(ordinal)
    )
    try await AssistantResponseRepository(store: fixture.store).persist(.init(
        message: message,
        metadata: .init(
            responseMessageID: messageID,
            requestID: String(format: "20000000-0000-4000-8000-%012d", ordinal),
            idempotencyReceipt: "receipt-\(ordinal)", mode: .coach,
            relevance: "career-relevant", contextSufficiency: "sufficient", stance: "nudge",
            inference: "Grounded", confidence: "medium", approach: "Offer one step",
            createdAtMS: Int64(ordinal)
        ),
        sources: [],
        proposal: .init(
            id: proposalID, responseMessageID: messageID, kind: proposalKind(proposal),
            canonicalPayload: payload,
            payloadDigest: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
            state: .pending, targetType: nil, targetID: nil, targetVersionID: nil,
            decisionReceipt: nil, createdAtMS: Int64(ordinal), resolvedAtMS: nil
        )
    ))
    return proposalID
}

private func proposalKind(_ proposal: CoachingProposal) -> String {
    switch proposal {
    case .goal: "goal"; case .action: "action"; case .weeklyWork: "weekly_work"
    case .evidence: "evidence"; case .memory: "memory"; case .insight: "insight"
    }
}

private func proposalFixture() async throws -> (directory: URL, store: TaisaStore, conversationID: String) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = try await TaisaStore.open(
        at: directory.appendingPathComponent("store.sqlite"), keyStore: ProposalRouterTestKeys()
    )
    let conversationID = "30000000-0000-4000-8000-000000000001"
    try await ConversationRepository(store: store).create(.init(
        id: conversationID, title: "Proposal routing", lifecycle: .completed,
        titleAuthority: .localFallback, createdAtMS: 0, updatedAtMS: 0
    ), context: .init(
        id: "30000000-0000-4000-8000-000000000002",
        deviceID: "30000000-0000-4000-8000-000000000003", timestamp: 0
    ))
    return (directory, store, conversationID)
}
