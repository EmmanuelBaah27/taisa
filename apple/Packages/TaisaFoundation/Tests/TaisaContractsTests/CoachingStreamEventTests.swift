import Foundation
import Testing
@testable import TaisaContracts

@Suite("Coaching stream contracts")
struct CoachingStreamEventTests {
    static let fixturesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "shared/fixtures/coaching-stream")

    @Test(arguments: ["completed.valid.json", "failed.valid.json"])
    func decodesCanonicalValidStreams(_ name: String) throws {
        let data = try Data(contentsOf: Self.fixturesRoot.appending(path: name))
        let events = try JSONDecoder().decode([CoachingStreamEvent].self, from: data)
        #expect(!events.isEmpty)
    }

    @Test(arguments: [
        "wrong-request.invalid.json",
        "gap.invalid.json",
        "conflicting-duplicate.invalid.json",
        "unknown-field.invalid.json",
        "post-terminal.invalid.json",
    ])
    func strictDecoderRejectsCanonicalInvalidStreams(_ name: String) throws {
        let data = try Data(contentsOf: Self.fixturesRoot.appending(path: name))
        let objects = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let lines = try objects.map { try JSONSerialization.data(withJSONObject: $0) + Data([0x0A]) }
        var decoder = StrictNDJSONDecoder<CoachingStreamEvent>(maximumLineBytes: 65_536)

        #expect(throws: StrictNDJSONError.self) {
            for line in lines { _ = try decoder.append(line) }
            _ = try decoder.finish()
        }
    }

    @Test func fragmentedInputProducesOrderedEvents() throws {
        let requestID = "00000000-0000-4000-8000-000000000109"
        let first = Data(#"{"type":"coaching.delta","requestId":"\#(requestID)","sequence":0,"delta":"A"}"#.utf8)
        let terminal = Data(#"{"type":"coaching.failed","requestId":"\#(requestID)","sequence":1,"code":"COACHING_UNAVAILABLE","retryable":true}"#.utf8)
        let stream = first + Data([0x0A]) + terminal + Data([0x0A])
        var decoder = StrictNDJSONDecoder<CoachingStreamEvent>(maximumLineBytes: 65_536)

        #expect(try decoder.append(stream.prefix(17)).isEmpty)
        let events = try decoder.append(stream.dropFirst(17))
        #expect(events.count == 2)
        #expect(try decoder.finish().isEmpty)
    }

    @Test func oversizedLineFailsBeforeUnboundedBuffering() throws {
        var decoder = StrictNDJSONDecoder<CoachingStreamEvent>(maximumLineBytes: 32)
        #expect(throws: StrictNDJSONError.self) {
            _ = try decoder.append(Data(repeating: 0x41, count: 33))
        }
    }

    @Test func completionDecodesOptionalTitleSuggestion() throws {
        let data = completedEvent(
            proposal: "null",
            titleSuggestion: #""Design review preparation""#
        )

        let event = try JSONDecoder().decode(CoachingStreamEvent.self, from: data)
        guard case let .completed(_, _, response, _) = event else {
            Issue.record("Expected a completed coaching response")
            return
        }
        #expect(response.titleSuggestion == "Design review preparation")
    }

    @Test(arguments: [
        #"{"kind":"goal","title":"Lead a launch","description":null,"priority":"high","targetDate":"2026-11-01T00:00:00Z"}"#,
        #"{"kind":"action","title":"Draft the brief","description":"One page","priority":"medium","dueAt":null,"goalId":"goal-1"}"#,
        #"{"kind":"weekly_work","actionId":"action-1","weekStart":"2026-10-19T00:00:00Z","plannedDay":null}"#,
        #"{"kind":"evidence","statement":"Led the review","occurredAt":"2026-10-16T00:00:00Z","goalId":"goal-1","actionId":null}"#,
        #"{"kind":"memory","memory":{"operation":"support","targetId":"memory-1","sourceMessageId":"message-1","reason":"New supporting evidence","requiresConfirmation":false}}"#,
        #"{"kind":"insight","body":"Protect preparation time","isTimeSensitive":true,"homeEligibleUntil":null}"#,
    ])
    func decodesEveryTypedProposalKind(_ proposal: String) throws {
        let event = try JSONDecoder().decode(CoachingStreamEvent.self, from: completedEvent(proposal: proposal))
        guard case let .completed(_, _, response, _) = event else {
            Issue.record("Expected a completed coaching response")
            return
        }
        #expect(response.proposal != nil)
        #expect(response.explanation.confidence == .medium)
    }

    @Test(arguments: [
        #"{"kind":"unknown"}"#,
        #"{"kind":"goal","title":"Lead","description":null,"priority":null,"targetDate":null,"extra":true}"#,
        #"{"kind":"goal","title":"   ","description":null,"priority":null,"targetDate":null}"#,
        #"{"kind":"memory","memory":{"operation":"support","targetId":"memory-1","sourceMessageId":"message-1","reason":"Support","requiresConfirmation":true}}"#,
        #"[{"kind":"goal","title":"Lead","description":null,"priority":null,"targetDate":null}]"#,
    ])
    func rejectsUnknownMalformedOrMultipleProposals(_ proposal: String) {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CoachingStreamEvent.self, from: completedEvent(proposal: proposal))
        }
    }

    private func completedEvent(proposal: String, titleSuggestion: String = "null") -> Data {
        let requestID = "00000000-0000-4000-8000-000000000109"
        return Data(#"{"type":"coaching.completed","requestId":"\#(requestID)","sequence":0,"response":{"requestId":"\#(requestID)","reply":"Reply","mode":"coach","relevance":"career-relevant","contextSufficiency":"sufficient","stance":"nudge","explanation":{"mode":"nudge","evidence":[],"inference":"A bounded inference","confidence":"medium","approach":"Offer one useful next step"},"proposal":\#(proposal),"usage":{"provider":"anthropic","model":"fixture","estimatedCostUsd":0},"titleSuggestion":\#(titleSuggestion)},"idempotencyReceipt":"receipt"}"#.utf8)
    }
}
