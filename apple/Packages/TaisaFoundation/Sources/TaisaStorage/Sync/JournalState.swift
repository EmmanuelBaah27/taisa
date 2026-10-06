/// A reserved item has been handed to one uploader. Reservation expiry allows
/// crash recovery; upload by mutation ID remains idempotent after expiry.
public struct ReservedChange: Codable, Sendable, Equatable {
    public let change: PendingChange
    public let reservationID: String
    public let expiresAtMS: Int64
}

public enum JournalState: Codable, Sendable, Equatable {
    case pending
    case retrying(category: String, attempts: Int)
    case reserved(reservationID: String, expiresAtMS: Int64, attempts: Int)
    /// Local replacement is distinct from confirmation by the transport.
    case superseded(by: String, remotelyAcknowledgedAtMS: Int64?)
    case remotelyAcknowledged(atMS: Int64)
}

public enum JournalCoverage: Codable, Sendable, Equatable {
    case confirmed
    case waitingFor(String)
    case unverifiable
}
