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
        return local(store: store, deviceID: deviceID, query: query, nowMS: nowMS)
    }

    static func local(
        store: TaisaStore,
        deviceID: String,
        operational: @escaping @Sendable () async -> YouOperationalFacts,
        nowMS: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
    ) -> Self {
        local(store: store, deviceID: deviceID, query: YouQuery(store: store, operational: operational), nowMS: nowMS)
    }

    private static func local(
        store: TaisaStore,
        deviceID: String,
        query: YouQuery,
        nowMS: @escaping @Sendable () -> Int64
    ) -> Self {
        let profiles = ProfileCommandRepository(store: store)
        let context: @Sendable () -> MutationContext = {
            .init(id: UUID().uuidString, deviceID: deviceID, timestamp: nowMS())
        }
        return .init(
            load: {
                let snapshot = try await query.load()
                guard let profile = snapshot.profile,
                      profile.biography.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !profile.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return snapshot }
                // Compatibility move through the existing encrypted mutation path.
                // Clearing the moved source prevents an intentionally cleared Bio
                // from resurrecting the old headline on the next launch.
                _ = try await profiles.save(
                    id: profile.id,
                    displayName: profile.displayName,
                    headline: "",
                    biography: profile.headline,
                    context: context()
                )
                return try await query.load()
            },
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
            }
        )
    }
}

public struct YouClient: Sendable {
    public var load: @Sendable () async throws -> YouSnapshot
    public var saveProfile: @Sendable (ProfileDraft) async throws -> YouSnapshot

    public init(
        load: @escaping @Sendable () async throws -> YouSnapshot,
        saveProfile: @escaping @Sendable (ProfileDraft) async throws -> YouSnapshot = { _ in throw YouContractError.persistenceFailed }
    ) {
        self.load = load; self.saveProfile = saveProfile
    }
}
