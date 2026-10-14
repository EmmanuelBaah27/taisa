import TaisaStorage

public struct ProfileDraft: Sendable, Equatable {
    public var displayName: String
    public var headline: String
    public var biography: String
    public init(displayName: String = "", headline: String = "", biography: String = "") {
        self.displayName = displayName; self.headline = headline; self.biography = biography
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
