import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TaisaAudio
import TaisaContracts
import TaisaNetworking

public struct TranscriptionStreamRequest: Sendable {
    public let endpoint: URL
    public let requestID: UUID
    public let bearerToken: String
    public let audio: FinalizedAudio
    public var queuedIsDurable: Bool

    public init(endpoint: URL, requestID: UUID, bearerToken: String, audio: FinalizedAudio, queuedIsDurable: Bool) {
        self.endpoint = endpoint
        self.requestID = requestID
        self.bearerToken = bearerToken
        self.audio = audio
        self.queuedIsDurable = queuedIsDurable
    }
}

public struct TranscriptionStreamClient: Sendable {
    private let transport: any NDJSONStreamTransporting
    private let maximumLineBytes: Int

    public init(transport: any NDJSONStreamTransporting, maximumLineBytes: Int = 64 * 1_024) {
        self.transport = transport
        self.maximumLineBytes = maximumLineBytes
    }

    public func stream(_ input: TranscriptionStreamRequest) -> AsyncThrowingStream<TranscriptionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard input.queuedIsDurable else { throw StreamTransportError.stageNotDurable }
                    var request = URLRequest(url: input.endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("Bearer \(input.bearerToken)", forHTTPHeaderField: "Authorization")
                    request.setValue(input.requestID.uuidString.lowercased(), forHTTPHeaderField: "X-Request-ID")
                    let boundary = "Taisa-\(input.requestID.uuidString)"
                    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    do {
                        request.httpBody = try multipartBody(input, boundary: boundary)
                    } catch {
                        throw StreamTransportError.invalidLocalAudio
                    }
                    let response = try await transport.execute(request)
                    for try await event in try strictEventStream(response: response, maximumLineBytes: maximumLineBytes, eventType: TranscriptionStreamEvent.self) {
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

    private func multipartBody(_ input: TranscriptionStreamRequest, boundary: String) throws -> Data {
        let audio = try Data(contentsOf: input.audio.url, options: .mappedIfSafe)
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"durationSeconds\"\r\n\r\n\(input.audio.duration)\r\n".utf8))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"audio.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
