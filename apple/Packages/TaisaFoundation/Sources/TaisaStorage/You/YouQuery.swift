import GRDB

public enum YouHealth: String, Codable, Sendable { case healthy, degraded, unavailable, unknown }
public enum YouRecoveryStatus: String, Codable, Sendable { case ready, setupRequired, recoveryRequired, unknown }
public enum YouPermissionStatus: String, Codable, Sendable { case granted, denied, restricted, notDetermined }
public enum YouProtectionStatus: String, Codable, Sendable { case enabled, disabled, unknown }

public struct YouOperationalFacts: Codable, Sendable, Equatable {
    public let store: YouHealth
    public let recovery: YouRecoveryStatus
    public let microphone: YouPermissionStatus
    public let gateway: YouHealth
    public let appProtection: YouProtectionStatus

    public init(store: YouHealth, recovery: YouRecoveryStatus, microphone: YouPermissionStatus, gateway: YouHealth, appProtection: YouProtectionStatus) {
        self.store = store
        self.recovery = recovery
        self.microphone = microphone
        self.gateway = gateway
        self.appProtection = appProtection
    }

    public static let unknown = YouOperationalFacts(store: .unknown, recovery: .unknown, microphone: .notDetermined, gateway: .unknown, appProtection: .unknown)
}

public struct YouSnapshot: Codable, Sendable, Equatable {
    public let profile: ProfileRecord?
    public let diagnostics: YouOperationalFacts
    public init(profile: ProfileRecord?, diagnostics: YouOperationalFacts) {
        self.profile = profile; self.diagnostics = diagnostics
    }
}

public struct YouQuery: Sendable {
    private let store: TaisaStore
    private let operational: YouOperationalFacts

    public init(store: TaisaStore, operational: YouOperationalFacts = .unknown) {
        self.store = store
        self.operational = operational
    }

    public func load() async throws -> YouSnapshot {
        do {
            let profile = try await store.read { db -> ProfileRecord? in
                guard let row = try Row.fetchOne(db, sql: "SELECT id, display_name, headline, biography, updated_at_ms FROM profile ORDER BY updated_at_ms DESC LIMIT 1") else { return nil }
                return ProfileRecord(
                    id: row["id"],
                    displayName: row["display_name"],
                    headline: row["headline"],
                    biography: row["biography"],
                    updatedAtMS: row["updated_at_ms"]
                )
            }
            return YouSnapshot(profile: profile, diagnostics: operational)
        } catch let error as YouContractError {
            throw error
        } catch {
            throw YouContractError.persistenceFailed
        }
    }
}
