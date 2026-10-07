import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TaisaContracts
import TaisaNetworking
import TaisaStorage

public struct VoiceGatewayConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let bearerToken: String
    public let ownerID: String

    public init(baseURL: URL, bearerToken: String, ownerID: String) throws {
        guard baseURL.scheme == "https" || baseURL.host == "localhost" || baseURL.host == "127.0.0.1",
              !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ownerID.count <= 200 else { throw VoiceSessionReducerError.invalidCommand }
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.ownerID = ownerID
    }

    func endpoint(_ path: String) -> URL { baseURL.appending(path: path) }
}

public actor GatewayTranscriptionRunner: VoiceTranscriptionRunning {
    private let configuration: VoiceGatewayConfiguration
    private let client: TranscriptionStreamClient
    private let audio: any VoiceFinalizedAudioLoading

    public init(
        configuration: VoiceGatewayConfiguration,
        audio: any VoiceFinalizedAudioLoading,
        transport: any NDJSONStreamTransporting = URLSessionNDJSONStreamTransport()
    ) {
        self.configuration = configuration
        self.audio = audio
        client = .init(transport: transport)
    }

    public func stream(
        for turn: VoiceTurnRecord
    ) async throws -> AsyncThrowingStream<TranscriptionStreamEvent, Error> {
        guard let requestID = UUID(uuidString: turn.transcriptionRequestID) else {
            throw VoiceSessionReducerError.invalidCommand
        }
        return client.stream(.init(
            endpoint: configuration.endpoint("api/v1/transcribe"),
            requestID: requestID, bearerToken: configuration.bearerToken,
            audio: try await audio.audio(for: turn), queuedIsDurable: turn.state == .transcribing
        ))
    }
}

public actor GatewayCoachingRunner: VoiceCoachingRunning {
    private let configuration: VoiceGatewayConfiguration
    private let client: CoachingStreamClient
    private let submittedAt: @Sendable () -> String

    public init(
        configuration: VoiceGatewayConfiguration,
        transport: any NDJSONStreamTransporting = URLSessionNDJSONStreamTransport(),
        submittedAt: @escaping @Sendable () -> String = {
            Date().formatted(.iso8601)
        }
    ) {
        self.configuration = configuration
        client = .init(transport: transport)
        self.submittedAt = submittedAt
    }

    public func stream(
        for turn: VoiceTurnRecord
    ) async throws -> AsyncThrowingStream<CoachingStreamEvent, Error> {
        guard let requestID = UUID(uuidString: turn.coachingRequestID),
              let transcript = turn.acceptedTranscript else {
            throw VoiceSessionReducerError.invalidCommand
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "requestId": requestID.uuidString.lowercased(),
            "submittedAt": submittedAt(),
            "input": transcript,
            "context": ["profile": NSNull(), "recentMessages": [], "memory": [], "evidence": []],
        ])
        return client.stream(.init(
            endpoint: configuration.endpoint("api/v1/coaching/respond/stream"),
            requestID: requestID, idempotencyKey: turn.coachingIdempotencyKey,
            bearerToken: configuration.bearerToken, body: body, queuedIsDurable: turn.state == .coaching
        ))
    }
}

public actor GatewayCoachingReconciliation: CoachingReconciliationLookingUp {
    private struct Envelope<Payload: Decodable>: Decodable { let success: Bool; let data: Payload? }
    private struct Result: Decodable {
        let status: String
        let response: CoachingResponse?
        let idempotencyReceipt: String?
        let code: String?
        let retryable: Bool?
    }

    private let configuration: VoiceGatewayConfiguration
    private let session: URLSession

    public init(configuration: VoiceGatewayConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func reconcile(requestID: UUID) async throws -> CoachingReconciliationResult {
        var request = authenticatedRequest(
            configuration.endpoint("api/v1/coaching/requests/\(requestID.uuidString.lowercased())")
        )
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StreamTransportError.invalidResponse }
        if http.statusCode == 404 { return .safeToRetry }
        guard (200..<300).contains(http.statusCode),
              let result = try JSONDecoder().decode(Envelope<Result>.self, from: data).data else {
            throw StreamTransportError.serverUnavailable
        }
        switch result.status {
        case "start": return .safeToRetry
        case "ambiguous": return .ambiguous
        case "completed":
            guard let response = result.response, let receipt = result.idempotencyReceipt else {
                throw StreamTransportError.invalidResponse
            }
            return .completed(response: response, receipt: receipt)
        case "failed":
            guard let code = result.code, let retryable = result.retryable else {
                throw StreamTransportError.invalidResponse
            }
            return .failed(code: code, retryable: retryable)
        default: throw StreamTransportError.invalidResponse
        }
    }

    public func authorizeRetry(requestID: UUID) async throws {
        var request = authenticatedRequest(
            configuration.endpoint("api/v1/coaching/requests/\(requestID.uuidString.lowercased())/resolve")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"decision":"retry"}"#.utf8)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StreamTransportError.reconciliationRequired
        }
    }

    private func authenticatedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.ownerID, forHTTPHeaderField: "X-User-ID")
        return request
    }
}
