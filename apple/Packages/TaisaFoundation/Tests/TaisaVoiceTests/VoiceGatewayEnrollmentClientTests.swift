import Foundation
import Testing
@testable import TaisaVoice

@Suite("Voice gateway enrollment client")
struct VoiceGatewayEnrollmentClientTests {
    @Test("requires an HTTPS gateway before making a request")
    func httpsOnly() async throws {
        let client = enrollmentClient(host: "insecure.example.com") { _ in
            Issue.record("HTTP gateway must fail before transport")
            throw URLError(.badURL)
        }

        await #expect(throws: VoiceGatewayEnrollmentError.invalidGatewayOrigin) {
            _ = try await client.enroll(
                baseURL: #require(URL(string: "http://insecure.example.com")),
                code: "one-time-code"
            )
        }
    }

    @Test("posts the exact enrollment endpoint and JSON body once")
    func exactRequest() async throws {
        let host = "request.example.com"
        let counter = RequestCounter()
        let client = enrollmentClient(host: host) { request in
            try await counter.record(request, body: request.bodyData())
            return try successResponse(request: request)
        }

        _ = try await client.enroll(
            baseURL: #require(URL(string: "https://\(host)/ignored/path")),
            code: "entered-code"
        )

        let recorded = try #require(await counter.requests.first)
        let request = recorded.request
        #expect(await counter.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://\(host)/api/v1/device-enrollments")
        #expect(request.timeoutInterval == 30)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let object = try #require(try JSONSerialization.jsonObject(with: recorded.body) as? [String: String])
        #expect(object == ["code": "entered-code"])
    }

    @Test("decodes a valid 201 credential and binds it to the gateway origin")
    func success() async throws {
        let host = "success.example.com"
        let client = enrollmentClient(host: host, handler: successResponse)

        let credential = try await client.enroll(
            baseURL: #require(URL(string: "https://\(host)")),
            code: "one-time-code"
        )

        #expect(credential.origin.absoluteString == "https://\(host)")
        #expect(credential.credentialID == "credential-1")
        #expect(credential.bearerToken == "opaque-token")
    }

    @Test("maps rejected enrollment codes without exposing response content")
    func rejectedCode() async throws {
        let secret = "private-response-value"
        let host = "rejected.example.com"
        let client = enrollmentClient(host: host) { request in
            try response(request: request, status: 401, body: """
            {"success":false,"error":{"code":"INVALID_ENROLLMENT_CODE","message":"\(secret)"}}
            """)
        }

        do {
            _ = try await client.enroll(
                baseURL: #require(URL(string: "https://\(host)")),
                code: "wrong-code"
            )
            Issue.record("Expected invalid or expired code")
        } catch {
            #expect(error as? VoiceGatewayEnrollmentError == .invalidOrExpiredCode)
            #expect(!String(describing: error).contains(secret))
        }
    }

    @Test("rejects malformed 201 success envelopes")
    func malformedSuccess() async throws {
        let host = "malformed.example.com"
        let client = enrollmentClient(host: host) { request in
            try response(request: request, status: 201, body: """
            {"success":true,"data":{"credentialId":"","token":""}}
            """)
        }

        await #expect(throws: VoiceGatewayEnrollmentError.invalidResponse) {
            _ = try await client.enroll(
                baseURL: #require(URL(string: "https://\(host)")),
                code: "one-time-code"
            )
        }
    }

    @Test("maps timeout and server failures to stable content-free errors", arguments: [
        (URLError(.timedOut), VoiceGatewayEnrollmentError.timedOut),
        (URLError(.cannotConnectToHost), VoiceGatewayEnrollmentError.serverUnavailable),
    ])
    func transportFailure(input: (URLError, VoiceGatewayEnrollmentError)) async throws {
        let host = "failure-\(input.0.code.rawValue).example.com"
        let client = enrollmentClient(host: host) { _ in throw input.0 }

        await #expect(throws: input.1) {
            _ = try await client.enroll(
                baseURL: #require(URL(string: "https://\(host)")),
                code: "one-time-code"
            )
        }
    }

    @Test("maps gateway server errors without decoding private bodies")
    func serverFailure() async throws {
        let host = "server.example.com"
        let client = enrollmentClient(host: host) { request in
            try response(request: request, status: 503, body: "private upstream detail")
        }

        await #expect(throws: VoiceGatewayEnrollmentError.serverUnavailable) {
            _ = try await client.enroll(
                baseURL: #require(URL(string: "https://\(host)")),
                code: "one-time-code"
            )
        }
    }

    @Test("never follows redirects that could replay the enrollment code", arguments: [
        "https://approved.example.com/alternate",
        "https://redirect-target.example.com/capture",
    ])
    func rejectsRedirects(location: String) async throws {
        let source = try #require(URL(string: "https://approved.example.com/api/v1/device-enrollments"))
        let response = try #require(HTTPURLResponse(
            url: source,
            statusCode: 307,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": location]
        ))
        let task = URLSession.shared.dataTask(with: source)
        let redirected = URLRequest(url: try #require(URL(string: location)))

        let decision = await withCheckedContinuation { continuation in
            EnrollmentRedirectDelegate().urlSession(
                .shared,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: redirected,
                completionHandler: { continuation.resume(returning: $0) }
            )
        }

        #expect(decision == nil)
    }
}

private actor RequestCounter {
    struct Recorded: Sendable {
        let request: URLRequest
        let body: Data
    }

    private(set) var requests: [Recorded] = []
    func record(_ request: URLRequest, body: Data) { requests.append(Recorded(request: request, body: body)) }
}

private extension URLRequest {
    func bodyData() throws -> Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private func enrollmentClient(
    host: String,
    handler: @escaping @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)
) -> VoiceGatewayEnrollmentClient {
    EnrollmentURLProtocol.registry.register(host: host, handler: handler)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EnrollmentURLProtocol.self]
    return VoiceGatewayEnrollmentClient(session: URLSession(configuration: configuration))
}

private func successResponse(request: URLRequest) throws -> (HTTPURLResponse, Data) {
    try response(request: request, status: 201, body: """
    {"success":true,"data":{"credentialId":"credential-1","token":"opaque-token"}}
    """)
}

private func response(request: URLRequest, status: Int, body: String) throws -> (HTTPURLResponse, Data) {
    let url = try #require(request.url)
    return (
        try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )),
        Data(body.utf8)
    )
}

private final class EnrollmentURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = EnrollmentRequestRegistry()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = request
        Task {
            do {
                let handler = try Self.registry.handler(for: request.url?.host)
                let (response, data) = try await handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private final class EnrollmentRequestRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]

    func register(host: String, handler: @escaping Handler) {
        lock.withLock { handlers[host] = handler }
    }

    func handler(for host: String?) throws -> Handler {
        try lock.withLock {
            guard let host, let handler = handlers[host] else { throw URLError(.badURL) }
            return handler
        }
    }
}
