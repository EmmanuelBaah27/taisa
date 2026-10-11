import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TaisaContracts
import TaisaNetworking

public struct CoachingStreamRequest: Sendable {
    public let endpoint: URL
    public let requestID: UUID
    public let idempotencyKey: String
    public let bearerToken: String
    public let body: Data
    public let queuedIsDurable: Bool

    public init(endpoint: URL, requestID: UUID, idempotencyKey: String, bearerToken: String, body: Data, queuedIsDurable: Bool) {
        self.endpoint = endpoint
        self.requestID = requestID
        self.idempotencyKey = idempotencyKey
        self.bearerToken = bearerToken
        self.body = body
        self.queuedIsDurable = queuedIsDurable
    }
}

public struct CoachingStreamClient: Sendable {
    private let transport: any NDJSONStreamTransporting
    private let maximumLineBytes: Int

    public init(transport: any NDJSONStreamTransporting, maximumLineBytes: Int = 256 * 1_024) {
        self.transport = transport
        self.maximumLineBytes = maximumLineBytes
    }

    public func stream(_ input: CoachingStreamRequest) -> AsyncThrowingStream<CoachingStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard input.queuedIsDurable else { throw StreamTransportError.stageNotDurable }
                    var request = URLRequest(url: input.endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.httpBody = input.body
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(input.bearerToken)", forHTTPHeaderField: "Authorization")
                    request.setValue(input.requestID.uuidString.lowercased(), forHTTPHeaderField: "X-Request-ID")
                    request.setValue(input.idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
                    let response = try await transport.execute(request)
                    for try await event in try strictEventStream(response: response, maximumLineBytes: maximumLineBytes, eventType: CoachingStreamEvent.self) {
                        guard event.streamRequestID == input.requestID else {
                            throw StreamTransportError.protocolViolation(.requestMismatch)
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch let error as StreamTransportError { continuation.finish(throwing: error) }
                catch let error as URLError where error.code == .timedOut { continuation.finish(throwing: StreamTransportError.timedOut) }
                catch let error as URLError where error.code == .cancelled { continuation.finish(throwing: StreamTransportError.cancelled) }
                catch is CancellationError { continuation.finish(throwing: StreamTransportError.cancelled) }
                catch { continuation.finish(throwing: StreamTransportError.serverUnavailable) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
