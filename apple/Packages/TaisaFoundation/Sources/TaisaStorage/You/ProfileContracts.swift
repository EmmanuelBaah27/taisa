import Foundation

public enum YouContractError: Error, Sendable, Equatable, CaseIterable {
    case invalidProfile
    case persistenceFailed
}

public struct ProfileInputValidation: Sendable, Equatable {
    public let displayNameMessage: String?
    public let biographyMessage: String?

    public var isValid: Bool {
        displayNameMessage == nil && biographyMessage == nil
    }
}

public enum ProfileInputValidator {
    public static func validate(
        displayName: String,
        biography: String
    ) -> ProfileInputValidation {
        let fields = normalized(displayName: displayName, biography: biography)
        return .init(
            displayNameMessage: message(
                for: fields.displayName,
                limit: 80,
                oversized: "Display name must be 80 characters or fewer.",
                allowsLineBreaks: false,
                unsupported: "Display name cannot contain line breaks or control characters."
            ),
            biographyMessage: message(
                for: fields.biography,
                limit: 2_000,
                oversized: "Bio must be 2,000 characters or fewer.",
                allowsLineBreaks: true,
                unsupported: "Bio contains unsupported control characters."
            )
        )
    }

    static func normalized(
        displayName: String,
        biography: String
    ) -> (displayName: String, biography: String) {
        (
            displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            biography.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func message(
        for value: String,
        limit: Int,
        oversized: String,
        allowsLineBreaks: Bool,
        unsupported: String
    ) -> String? {
        if value.count > limit { return oversized }
        let hasUnsupportedControl = value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar) && !(allowsLineBreaks && scalar.value == 10)
        }
        return hasUnsupportedControl ? unsupported : nil
    }
}

public struct ProfileCommandRepository: Sendable {
    private let repository: ProfileRepository

    public init(store: TaisaStore) { repository = ProfileRepository(store: store) }

    public func get(id: String) async throws -> CareerProfile? {
        try await repository.get(id: id).map {
            CareerProfile(id: $0.id, displayName: $0.displayName, biography: $0.biography, updatedAtMS: $0.updatedAtMS)
        }
    }

    @discardableResult
    public func save(
        id: String,
        displayName: String,
        biography: String,
        context: MutationContext
    ) async throws -> CareerProfile {
        let fields = ProfileInputValidator.normalized(
            displayName: displayName,
            biography: biography
        )
        guard ProfileInputValidator.validate(
            displayName: fields.displayName,
            biography: fields.biography
        ).isValid else { throw YouContractError.invalidProfile }
        do {
            let record = try await repository.saveActiveProfile(
                id: id,
                displayName: fields.displayName,
                biography: fields.biography,
                context: context
            )
            return CareerProfile(
                id: record.id,
                displayName: record.displayName,
                biography: record.biography,
                updatedAtMS: record.updatedAtMS
            )
        } catch let error as YouContractError {
            throw error
        } catch {
            throw YouContractError.persistenceFailed
        }
    }
}
