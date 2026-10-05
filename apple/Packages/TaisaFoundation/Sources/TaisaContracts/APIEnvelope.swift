public struct APIErrorEnvelope: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct APIEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let success: Bool
    public let data: Payload
    public let error: APIErrorEnvelope?

    public init(success: Bool, data: Payload, error: APIErrorEnvelope? = nil) {
        self.success = success
        self.data = data
        self.error = error
    }
}
