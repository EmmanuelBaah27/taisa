import Foundation
import Testing
import TaisaAudio
import TaisaContracts
import TaisaNetworking
import TaisaStorage
@testable import TaisaVoice

@Suite("Gateway voice runtime adapters")
struct GatewayRuntimeAdapterTests {
    @Test("configuration accepts HTTPS and local development only")
    func configurationBoundary() throws {
        #expect(throws: VoiceSessionReducerError.invalidCommand) {
            _ = try VoiceGatewayConfiguration(
                baseURL: URL(string: "http://example.com")!, bearerToken: "token", ownerID: "owner"
            )
        }
        _ = try VoiceGatewayConfiguration(
            baseURL: URL(string: "https://voice.example.com")!, bearerToken: "token", ownerID: "owner"
        )
        _ = try VoiceGatewayConfiguration(
            baseURL: URL(string: "http://localhost:3001")!, bearerToken: "token", ownerID: "owner"
        )
    }

    @Test("coaching adapter sends the accepted transcript with stable identities")
    func coachingRequestBoundary() async throws {
        let transport = GatewayTransportSpy(response: NDJSONHTTPResponse(
            statusCode: 200, contentType: "application/x-ndjson",
            chunks: [Data("""
            {"type":"coaching.failed","requestId":"44444444-4444-4444-8444-444444444444","sequence":0,"code":"COACHING_UNAVAILABLE","retryable":false}

            """.utf8)]
        ))
        let configuration = try VoiceGatewayConfiguration(
            baseURL: URL(string: "https://voice.example.com")!, bearerToken: "token", ownerID: "owner"
        )
        let runner = GatewayCoachingRunner(
            configuration: configuration, transport: transport,
            recentMessages: { _ in [
                MessageRecord(
                    id: "55555555-5555-4555-8555-555555555555",
                    conversationID: "22222222-2222-4222-8222-222222222222",
                    role: "assistant", body: "Earlier guidance", createdAtMS: 0
                )
            ] },
            submittedAt: { "2026-10-07T00:00:00Z" }
        )
        let stream = try await runner.stream(for: gatewayTurn())
        for try await _ in stream {}

        let request = try #require(await transport.request)
        #expect(request.url?.absoluteString == "https://voice.example.com/api/v1/coaching/respond/stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "coaching-key")
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["input"] as? String == "accepted transcript")
        #expect(object["requestId"] as? String == "44444444-4444-4444-8444-444444444444")
        let context = try #require(object["context"] as? [String: Any])
        let messages = try #require(context["recentMessages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "assistant")
        #expect(messages[0]["content"] as? String == "Earlier guidance")
    }
}

private actor GatewayTransportSpy: NDJSONStreamTransporting {
    private(set) var request: URLRequest?
    let response: NDJSONHTTPResponse
    init(response: NDJSONHTTPResponse) { self.response = response }
    func execute(_ request: URLRequest) async throws -> NDJSONHTTPResponse {
        self.request = request
        return response
    }
}

private func gatewayTurn() -> VoiceTurnRecord {
    VoiceTurnRecord(
        id: "11111111-1111-4111-8111-111111111111",
        conversationID: "22222222-2222-4222-8222-222222222222",
        transcriptionRequestID: "33333333-3333-4333-8333-333333333333",
        transcriptionIdempotencyKey: "transcription-key",
        coachingRequestID: "44444444-4444-4444-8444-444444444444",
        coachingIdempotencyKey: "coaching-key", state: .coaching, stage: .coaching,
        acceptedTranscript: "accepted transcript", createdAtMS: 1, updatedAtMS: 1
    )
}
