import Foundation
import TaisaStorage

public struct ProfileDraft: Sendable, Equatable {
    public var displayName: String
    public var headline: String
    public var biography: String
    public init(displayName: String = "", headline: String = "", biography: String = "") {
        self.displayName = displayName; self.headline = headline; self.biography = biography
    }
}

public extension YouClient {
    static func local(
        store: TaisaStore,
        deviceID: String,
        operational: YouOperationalFacts,
        nowMS: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
    ) -> Self {
        let query = YouQuery(store: store, operational: operational)
        let profiles = ProfileCommandRepository(store: store)
        let capabilities = CapabilityCommandRepository(store: store)
        let context: @Sendable () -> MutationContext = {
            .init(id: UUID().uuidString, deviceID: deviceID, timestamp: nowMS())
        }
        return .init(
            load: { try await query.load() },
            saveProfile: { draft in
                let profileID = try await query.load().profile?.id ?? deviceID
                _ = try await profiles.save(
                    id: profileID,
                    displayName: draft.displayName,
                    headline: draft.headline,
                    biography: draft.biography,
                    context: context()
                )
                return try await query.load()
            },
            setCapability: { id, state in
                let evidence = state == .learning ? nil : "explicit-user-review"
                _ = try await capabilities.set(id, to: state, evidence: evidence, context: context())
                return try await query.load()
            }
        )
    }
}

public struct YouClient: Sendable {
    public var load: @Sendable () async throws -> YouSnapshot
    public var saveProfile: @Sendable (ProfileDraft) async throws -> YouSnapshot
    public var setCapability: @Sendable (CapabilityID, CapabilityGovernanceState) async throws -> YouSnapshot

    public init(
        load: @escaping @Sendable () async throws -> YouSnapshot,
        saveProfile: @escaping @Sendable (ProfileDraft) async throws -> YouSnapshot = { _ in throw YouContractError.persistenceFailed },
        setCapability: @escaping @Sendable (CapabilityID, CapabilityGovernanceState) async throws -> YouSnapshot = { _, _ in throw YouContractError.persistenceFailed }
    ) {
        self.load = load; self.saveProfile = saveProfile; self.setCapability = setCapability
    }
}
