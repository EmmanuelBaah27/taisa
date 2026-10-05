import Foundation
import Testing
@testable import TaisaContracts

@Suite("Transcription stream event fixtures")
struct TranscriptionStreamEventTests {
    static let fixturesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "shared/fixtures/transcription")

    static let validFixtureURLs = [
        "delta.valid.json",
        "completed-clear.valid.json",
        "completed-uncertain.valid.json",
        "no-speech.valid.json",
        "failed.valid.json",
    ].map { fixturesRoot.appending(path: $0) }

    static let invalidFixtureURLs = [
        "unknown-type.invalid.json",
        "completed-empty.invalid.json",
    ].map { fixturesRoot.appending(path: $0) }

    @Test(arguments: validFixtureURLs)
    func decodesEveryCanonicalFixture(_ url: URL) throws {
        _ = try JSONDecoder().decode(
            TranscriptionStreamEvent.self,
            from: Data(contentsOf: url)
        )
    }

    @Test(arguments: invalidFixtureURLs)
    func rejectsEveryInvalidFixture(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TranscriptionStreamEvent.self, from: data)
        }
    }

    @Test(arguments: malformedEvents)
    func rejectsMalformedBoundaryValues(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                TranscriptionStreamEvent.self,
                from: Data(json.utf8)
            )
        }
    }

    static let malformedEvents = [
        #"{"type":"transcript.delta","requestId":"not-a-uuid","sequence":0,"delta":"text"}"#,
        #"{"type":"transcript.delta","requestId":"00000000-0000-4000-8000-000000000001","sequence":-1,"delta":"text"}"#,
        #"{"type":"transcript.no_speech","requestId":"00000000-0000-4000-8000-000000000001","sequence":0,"extra":true}"#,
        #"{"type":"transcript.failed","requestId":"00000000-0000-4000-8000-000000000001","sequence":0,"code":"RAW_PROVIDER_ERROR"}"#,
        #"{"type":"transcript.completed","requestId":"00000000-0000-4000-8000-000000000001","sequence":0,"transcript":"text","durationSeconds":0,"quality":"clear","usage":{"provider":"openai","model":"fixture","estimatedCostUsd":0}}"#,
        #"{"type":"transcript.completed","requestId":"00000000-0000-4000-8000-000000000001","sequence":0,"transcript":"text","durationSeconds":1,"quality":"clear","usage":{"provider":"openai","model":"fixture","estimatedCostUsd":-1}}"#,
        #"{"type":"transcript.completed","requestId":"00000000-0000-4000-8000-000000000001","sequence":0,"transcript":"text","durationSeconds":1,"quality":"clear","usage":{"provider":"openai","model":"fixture","audioSeconds":null,"estimatedCostUsd":0}}"#,
    ]
}
