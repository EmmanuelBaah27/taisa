import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TaisaContracts

public enum StreamTransportError: Error, Sendable, Equatable {
    case stageNotDurable
    case invalidLocalAudio
    case invalidResponse
    case authentication
    case rateLimited
    case costLimitReached
    case reconciliationRequired
    case serverUnavailable
    case timedOut
    case cancelled
    case protocolViolation(StrictNDJSONError)
}

public struct NDJSONHTTPResponse: Sendable {
    public let statusCode: Int
    public let contentType: String?
    public let errorCode: String?
    public let chunks: AsyncThrowingStream<Data, Error>

    public init(statusCode: Int, contentType: String?, errorCode: String? = nil, chunks: [Data]) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.errorCode = errorCode
        self.chunks = AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }

    init(statusCode: Int, contentType: String?, errorCode: String? = nil, chunks: AsyncThrowingStream<Data, Error>) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.errorCode = errorCode
        self.chunks = chunks
    }
}

public protocol NDJSONStreamTransporting: Sendable {
    func execute(_ request: URLRequest) async throws -> NDJSONHTTPResponse
}

public actor URLSessionNDJSONStreamTransport: NDJSONStreamTransporting {
    private let session: URLSession
    private let chunkBytes: Int

    public init(session: URLSession = .shared, chunkBytes: Int = 4_096) {
        self.session = session
        self.chunkBytes = max(1, chunkBytes)
    }

    public func execute(_ request: URLRequest) async throws -> NDJSONHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw StreamTransportError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            var boundedBody = Data()
            for try await byte in bytes {
                guard boundedBody.count < 8 * 1_024 else { break }
                boundedBody.append(byte)
            }
            let code = ((try? JSONSerialization.jsonObject(with: boundedBody)) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["code"] as? String }
            return NDJSONHTTPResponse(
                statusCode: http.statusCode,
                contentType: http.value(forHTTPHeaderField: "Content-Type"),
                errorCode: code,
                chunks: []
            )
        }
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    var chunk = Data()
                    chunk.reserveCapacity(chunkBytes)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunk.append(byte)
                        if chunk.count == chunkBytes {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return NDJSONHTTPResponse(
            statusCode: http.statusCode,
            contentType: http.value(forHTTPHeaderField: "Content-Type"),
            chunks: stream
        )
    }
}

public func strictEventStream<Event: StrictStreamEvent>(
    response: NDJSONHTTPResponse,
    maximumLineBytes: Int,
    eventType: Event.Type = Event.self
) throws -> AsyncThrowingStream<Event, Error> {
    try validate(response)
    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var decoder = StrictNDJSONDecoder<Event>(maximumLineBytes: maximumLineBytes)
                for try await chunk in response.chunks {
                    try Task.checkCancellation()
                    for event in try decoder.append(chunk) { continuation.yield(event) }
                }
                for event in try decoder.finish() { continuation.yield(event) }
                continuation.finish()
            } catch let error as StrictNDJSONError {
                continuation.finish(throwing: StreamTransportError.protocolViolation(error))
            } catch is CancellationError {
                continuation.finish(throwing: StreamTransportError.cancelled)
            } catch let error as URLError where error.code == .timedOut {
                continuation.finish(throwing: StreamTransportError.timedOut)
            } catch {
                continuation.finish(throwing: StreamTransportError.serverUnavailable)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

private func validate(_ response: NDJSONHTTPResponse) throws {
    if response.errorCode == "COST_LIMIT_REACHED" || response.errorCode == "COST_LIMIT_EXCEEDED" {
        throw StreamTransportError.costLimitReached
    }
    switch response.statusCode {
    case 200..<300:
        guard response.contentType?.lowercased().contains("application/x-ndjson") == true else {
            throw StreamTransportError.invalidResponse
        }
    case 401, 403: throw StreamTransportError.authentication
    case 402: throw StreamTransportError.costLimitReached
    case 409: throw StreamTransportError.reconciliationRequired
    case 429: throw StreamTransportError.rateLimited
    case 500...599: throw StreamTransportError.serverUnavailable
    default: throw StreamTransportError.invalidResponse
    }
}
