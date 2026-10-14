import GRDB

public enum YouHealth: String, Codable, Sendable { case healthy, degraded, unavailable, unknown }
public enum YouRecoveryStatus: String, Codable, Sendable { case ready, setupRequired, recoveryRequired, unknown }
public enum YouPermissionStatus: String, Codable, Sendable { case granted, denied, restricted, notDetermined }
public enum YouProtectionStatus: String, Codable, Sendable { case enabled, disabled, unknown }
public enum CapabilityAvailability: String, Codable, Sendable { case available, limited, unavailable, unknown }

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

public struct CapabilityOverview: Codable, Sendable, Equatable, Identifiable {
    public let id: CapabilityID
    public let chosenState: CapabilityGovernanceState
    public let availability: CapabilityAvailability
    public let decidedAtMS: Int64?
    public init(id: CapabilityID, chosenState: CapabilityGovernanceState, availability: CapabilityAvailability, decidedAtMS: Int64?) {
        self.id = id; self.chosenState = chosenState; self.availability = availability; self.decidedAtMS = decidedAtMS
    }
}

public struct YouSnapshot: Codable, Sendable, Equatable {
    public let profile: ProfileRecord?
    public let capabilities: [CapabilityOverview]
    public let diagnostics: YouOperationalFacts
    public init(profile: ProfileRecord?, capabilities: [CapabilityOverview], diagnostics: YouOperationalFacts) {
        self.profile = profile; self.capabilities = capabilities; self.diagnostics = diagnostics
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
            let chosen = try await CapabilityCommandRepository(store: store).list()
            let byID = Dictionary(uniqueKeysWithValues: chosen.map { ($0.capability, $0) })
            let capabilities = CapabilityID.allCases.map { id in
                CapabilityOverview(
                    id: id,
                    chosenState: byID[id]?.state ?? .learning,
                    availability: availability(for: id),
                    decidedAtMS: byID[id]?.decidedAtMS
                )
            }
            return YouSnapshot(profile: profile, capabilities: capabilities, diagnostics: operational)
        } catch let error as YouContractError {
            throw error
        } catch {
            throw YouContractError.persistenceFailed
        }
    }

    private func availability(for capability: CapabilityID) -> CapabilityAvailability {
        guard operational.store == .healthy else {
            return operational.store == .unavailable ? .unavailable : .unknown
        }
        switch capability {
        case .insights:
            return .available
        case .voice:
            if operational.microphone == .denied || operational.microphone == .restricted || operational.gateway == .unavailable { return .unavailable }
            if operational.microphone == .granted && operational.gateway == .healthy { return .available }
            return operational.gateway == .degraded ? .limited : .unknown
        case .seniorSelf:
            if operational.gateway == .unavailable { return .unavailable }
            if operational.gateway == .healthy { return .available }
            return operational.gateway == .degraded ? .limited : .unknown
        }
    }
}
