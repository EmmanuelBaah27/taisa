import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol VoiceGatewayEnrolling: Sendable {
    func enroll(baseURL: URL, code: String) async throws -> VoiceGatewayCredential
}

final class EnrollmentRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum VoiceGatewayEnrollmentError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidGatewayOrigin
    case invalidOrExpiredCode
    case invalidResponse
    case timedOut
    case serverUnavailable

    public var description: String {
        switch self {
        case .invalidGatewayOrigin: "The voice gateway must use a valid HTTPS origin."
        case .invalidOrExpiredCode: "The enrollment code is invalid or expired."
        case .invalidResponse: "The voice gateway returned an invalid enrollment response."
        case .timedOut: "The voice gateway enrollment request timed out."
        case .serverUnavailable: "The voice gateway is unavailable."
        }
    }
}

public actor VoiceGatewayEnrollmentClient: VoiceGatewayEnrolling {
    private struct RequestBody: Encodable { let code: String }
    private struct ResponseEnvelope: Decodable {
        struct Credential: Decodable {
            let credentialId: String
            let token: String
        }

        let success: Bool
        let data: Credential?
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func enroll(baseURL: URL, code: String) async throws -> VoiceGatewayCredential {
        let origin: URL
        do {
            origin = try VoiceGatewayCredential.normalizedOrigin(baseURL)
        } catch {
            throw VoiceGatewayEnrollmentError.invalidGatewayOrigin
        }
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceGatewayEnrollmentError.invalidOrExpiredCode
        }

        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        components?.path = "/api/v1/device-enrollments"
        guard let endpoint = components?.url else {
            throw VoiceGatewayEnrollmentError.invalidGatewayOrigin
        }

        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(code: code))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(
                for: request,
                delegate: EnrollmentRedirectDelegate()
            )
        } catch let error as URLError where error.code == .timedOut {
            throw VoiceGatewayEnrollmentError.timedOut
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VoiceGatewayEnrollmentError.serverUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw VoiceGatewayEnrollmentError.invalidResponse
        }
        switch http.statusCode {
        case 201:
            break
        case 401:
            throw VoiceGatewayEnrollmentError.invalidOrExpiredCode
        case 408, 504:
            throw VoiceGatewayEnrollmentError.timedOut
        case 500...599:
            throw VoiceGatewayEnrollmentError.serverUnavailable
        default:
            throw VoiceGatewayEnrollmentError.invalidResponse
        }

        let envelope: ResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            throw VoiceGatewayEnrollmentError.invalidResponse
        }
        guard envelope.success,
              let payload = envelope.data,
              !payload.credentialId.isEmpty,
              !payload.token.isEmpty
        else {
            throw VoiceGatewayEnrollmentError.invalidResponse
        }
        do {
            return try VoiceGatewayCredential(
                origin: origin,
                credentialID: payload.credentialId,
                bearerToken: payload.token
            )
        } catch {
            throw VoiceGatewayEnrollmentError.invalidResponse
        }
    }
}
