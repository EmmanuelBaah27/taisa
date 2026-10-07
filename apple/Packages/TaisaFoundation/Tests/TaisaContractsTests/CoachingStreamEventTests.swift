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
}
