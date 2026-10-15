import Foundation

public enum YouContractError: Error, Sendable, Equatable, CaseIterable {
    case invalidProfile
    case persistenceFailed
}

public struct ProfileCommandRepository: Sendable {
    private let repository: ProfileRepository

    public init(store: TaisaStore) { repository = ProfileRepository(store: store) }

    public func get(id: String) async throws -> ProfileRecord? { try await repository.get(id: id) }

    @discardableResult
    public func save(
        id: String,
        displayName: String,
        headline: String,
        biography: String,
        context: MutationContext
    ) async throws -> ProfileRecord {
        let fields = [displayName, headline, biography].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields[0].count <= 80, fields[1].count <= 160, fields[2].count <= 2_000,
              fields.allSatisfy({ !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) })
        else { throw YouContractError.invalidProfile }
        let record = ProfileRecord(
            id: id,
            displayName: fields[0],
            headline: fields[1],
            biography: fields[2],
            updatedAtMS: context.timestamp
        )
        do {
            if try await repository.get(id: id) == nil {
                try await repository.create(record, context: context)
            } else {
                try await repository.update(record, context: context)
            }
            return record
        } catch let error as YouContractError {
            throw error
        } catch {
            throw YouContractError.persistenceFailed
        }
    }
}
