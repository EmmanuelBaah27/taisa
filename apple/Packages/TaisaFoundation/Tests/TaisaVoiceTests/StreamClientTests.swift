import Foundation
import Testing
import TaisaAudio
import TaisaContracts
import TaisaNetworking
@testable import TaisaVoice

@Suite("Strict conversation stream clients")
struct StreamClientTests {
    private let requestID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    @Test("fragmented UTF-8 and split lines stream in order")
    func fragmentedUTF8AndLines() async throws {
        let terminal = #"{"type":"transcript.no_speech","requestId":"11111111-1111-4111-8111-111111111111","sequence":1}"#
        let bytes = Data((#"{"type":"transcript.delta","requestId":"11111111-1111-4111-8111-111111111111","sequence":0,"delta":"café"}"# + "\n" + terminal + "\n").utf8)
        let transport = ScriptedStreamTransport(response: .ok(chunks: bytes.map { Data([$0]) }))
        let client = TranscriptionStreamClient(transport: transport, maximumLineBytes: 1_024)

        let events = try await collect(client.stream(.fixture(requestID: requestID)))

        #expect(events.count == 2)
        #expect(events[0] == .delta(requestId: requestID, sequence: 0, delta: "café"))
        #expect(events[1] == .noSpeech(requestId: requestID, sequence: 1))
    }

    @Test("identical duplicate is ignored but conflicting duplicate fails")
    func duplicateReplayRules() async throws {
        let delta = #"{"type":"transcript.delta","requestId":"11111111-1111-4111-8111-111111111111","sequence":0,"delta":"one"}"#
        let terminal = #"{"type":"transcript.no_speech","requestId":"11111111-1111-4111-8111-111111111111","sequence":1}"#
        let replay = ScriptedStreamTransport(response: .ok(chunks: [Data("\(delta)\n\(delta)\n\(terminal)\n".utf8)]))
        #expect(try await collect(TranscriptionStreamClient(transport: replay).stream(.fixture(requestID: requestID))).count == 2)

        let conflict = delta.replacingOccurrences(of: "one", with: "two")
        let bad = ScriptedStreamTransport(response: .ok(chunks: [Data("\(delta)\n\(conflict)\n\(terminal)\n".utf8)]))
        await #expect(throws: StreamTransportError.protocolViolation(.conflictingDuplicate(sequence: 0))) {
            _ = try await collect(TranscriptionStreamClient(transport: bad).stream(.fixture(requestID: requestID)))
        }
    }

    @Test("line bounds and sequence gaps fail closed")
    func protocolBoundsFailClosed() async throws {
        let oversized = ScriptedStreamTransport(response: .ok(chunks: [Data(repeating: 65, count: 33)]))
        await #expect(throws: StreamTransportError.protocolViolation(.lineTooLarge)) {
            _ = try await collect(TranscriptionStreamClient(transport: oversized, maximumLineBytes: 32).stream(.fixture(requestID: requestID)))
        }

        let gap = #"{"type":"transcript.no_speech","requestId":"11111111-1111-4111-8111-111111111111","sequence":1}"#
        let gapTransport = ScriptedStreamTransport(response: .ok(chunks: [Data("\(gap)\n".utf8)]))
        await #expect(throws: StreamTransportError.protocolViolation(.sequenceMismatch(expected: 0, actual: 1))) {
            _ = try await collect(TranscriptionStreamClient(transport: gapTransport).stream(.fixture(requestID: requestID)))
        }

        let terminal = #"{"type":"transcript.no_speech","requestId":"11111111-1111-4111-8111-111111111111","sequence":0}"#
        let postTerminal = #"{"type":"transcript.delta","requestId":"11111111-1111-4111-8111-111111111111","sequence":1,"delta":"late"}"#
        let late = ScriptedStreamTransport(response: .ok(chunks: [Data("\(terminal)\n\(postTerminal)\n".utf8)]))
        await #expect(throws: StreamTransportError.protocolViolation(.eventAfterTerminal)) {
            _ = try await collect(TranscriptionStreamClient(transport: late).stream(.fixture(requestID: requestID)))
        }
    }

    @Test("request mismatch, missing terminal, and timeout stay typed")
    func terminalAndTransportFailuresStayTyped() async throws {
        let wrong = #"{"type":"transcript.no_speech","requestId":"22222222-2222-4222-8222-222222222222","sequence":0}"#
        let mismatch = ScriptedStreamTransport(response: .ok(chunks: [Data(wrong.utf8)]))
        await #expect(throws: StreamTransportError.protocolViolation(.requestMismatch)) {
            _ = try await collect(TranscriptionStreamClient(transport: mismatch).stream(.fixture(requestID: requestID)))
        }

        let delta = #"{"type":"transcript.delta","requestId":"11111111-1111-4111-8111-111111111111","sequence":0,"delta":"partial"}"#
        let missing = ScriptedStreamTransport(response: .ok(chunks: [Data(delta.utf8)]))
        await #expect(throws: StreamTransportError.protocolViolation(.missingTerminal)) {
            _ = try await collect(TranscriptionStreamClient(transport: missing).stream(.fixture(requestID: requestID)))
        }

        let timeout = ScriptedStreamTransport(error: URLError(.timedOut))
        await #expect(throws: StreamTransportError.timedOut) {
            _ = try await collect(TranscriptionStreamClient(transport: timeout).stream(.fixture(requestID: requestID)))
        }
    }

    @Test("durable queue gates audio upload")
    func durabilityGate() async throws {
        let transport = ScriptedStreamTransport(response: .ok(chunks: []))
        let client = TranscriptionStreamClient(transport: transport)
        var request = TranscriptionStreamRequest.fixture(requestID: requestID)
        request.queuedIsDurable = false
        await #expect(throws: StreamTransportError.stageNotDurable) { _ = try await collect(client.stream(request)) }
        #expect(await transport.callCount == 0)
    }

    @Test(arguments: [
        (401, StreamTransportError.authentication),
        (429, StreamTransportError.rateLimited),
        (409, StreamTransportError.reconciliationRequired),
        (402, StreamTransportError.costLimitReached),
        (503, StreamTransportError.serverUnavailable),
    ])
    func mapsHTTPFailure(status: Int, expected: StreamTransportError) async throws {
        let transport = ScriptedStreamTransport(response: .failure(statusCode: status))
        await #expect(throws: expected) {
            _ = try await collect(TranscriptionStreamClient(transport: transport).stream(.fixture(requestID: requestID)))
        }
    }

    @Test("cost error code is distinguished from generic rate limiting")
    func mapsCostCode() async throws {
        let response = NDJSONHTTPResponse(statusCode: 429, contentType: "application/json", errorCode: "COST_LIMIT_REACHED", chunks: [])
        await #expect(throws: StreamTransportError.costLimitReached) {
            _ = try await collect(TranscriptionStreamClient(transport: ScriptedStreamTransport(response: response)).stream(.fixture(requestID: requestID)))
        }
    }

    @Test("coaching applies request and idempotency identities")
    func coachingHeaders() async throws {
        let terminal = Data(#"{"type":"coaching.failed","requestId":"11111111-1111-4111-8111-111111111111","sequence":0,"code":"COACHING_UNAVAILABLE","retryable":true}"#.utf8)
        let transport = ScriptedStreamTransport(response: .ok(chunks: [terminal]))
        let client = CoachingStreamClient(transport: transport)
        _ = try await collect(client.stream(.init(endpoint: URL(string: "https://example.test/coaching")!, requestID: requestID, idempotencyKey: "turn-1", bearerToken: "token", body: Data("{}".utf8), queuedIsDurable: true)))
        let request = try #require(await transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "X-Request-ID") == requestID.uuidString.lowercased())
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "turn-1")
    }

    @Test("transcription applies owner-bound durable idempotency identities")
    func transcriptionHeaders() async throws {
        let terminal = Data(#"{"type":"transcript.no_speech","requestId":"11111111-1111-4111-8111-111111111111","sequence":0}"#.utf8)
        let transport = ScriptedStreamTransport(response: .ok(chunks: [terminal]))
        _ = try await collect(
            TranscriptionStreamClient(transport: transport).stream(.fixture(requestID: requestID))
        )
        let request = try #require(await transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "X-User-ID") == "device-1")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "transcription-key")
    }
}

private func collect<Event>(_ stream: AsyncThrowingStream<Event, Error>) async throws -> [Event] {
    var events: [Event] = []
    for try await event in stream { events.append(event) }
    return events
}

private actor ScriptedStreamTransport: NDJSONStreamTransporting {
    let response: NDJSONHTTPResponse?
    let error: Error?
    private(set) var callCount = 0
    private(set) var lastRequest: URLRequest?
    init(response: NDJSONHTTPResponse) { self.response = response; self.error = nil }
    init(error: Error) { self.response = nil; self.error = error }
    func execute(_ request: URLRequest) async throws -> NDJSONHTTPResponse {
        callCount += 1
        lastRequest = request
        if let error { throw error }
        return response!
    }
}

private extension NDJSONHTTPResponse {
    static func ok(chunks: [Data]) -> Self { .init(statusCode: 200, contentType: "application/x-ndjson", chunks: chunks) }
    static func failure(statusCode: Int) -> Self { .init(statusCode: statusCode, contentType: "application/json", chunks: []) }
}

private extension TranscriptionStreamRequest {
    static func fixture(requestID: UUID) -> Self {
        .init(
            endpoint: URL(string: "https://example.test/transcribe")!,
            requestID: requestID, bearerToken: "token", ownerID: "device-1",
            idempotencyKey: "transcription-key",
            audio: .init(fileID: UUID(), url: URL(fileURLWithPath: "/etc/hosts"), duration: 1, byteCount: 1, sha256: String(repeating: "a", count: 64)),
            queuedIsDurable: true
        )
    }
}
