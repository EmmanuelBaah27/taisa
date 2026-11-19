import Foundation

public enum YouContractError: Error, Sendable, Equatable, CaseIterable {
    case invalidProfile
    case persistenceFailed
}

public struct ProfileInputValidation: Sendable, Equatable {
    public let displayNameMessage: String?
    public let headlineMessage: String?
    public let biographyMessage: String?

    public var isValid: Bool {
        displayNameMessage == nil && headlineMessage == nil && biographyMessage == nil
    }
}

public enum ProfileInputValidator {
    public static func validate(
        displayName: String,
        headline: String,
        biography: String
    ) -> ProfileInputValidation {
        let fields = normalized(displayName: displayName, headline: headline, biography: biography)
        return .init(
            displayNameMessage: message(
                for: fields.displayName,
                limit: 80,
                oversized: "Display name must be 80 characters or fewer.",
                allowsLineBreaks: false,
                unsupported: "Display name cannot contain line breaks or control characters."
            ),
            headlineMessage: message(
                for: fields.headline,
                limit: 160,
                oversized: "Headline must be 160 characters or fewer.",
                allowsLineBreaks: false,
                unsupported: "Headline cannot contain line breaks or control characters."
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
        headline: String,
        biography: String
    ) -> (displayName: String, headline: String, biography: String) {
        (
            displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            headline.trimmingCharacters(in: .whitespacesAndNewlines),
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

    public func get(id: String) async throws -> ProfileRecord? { try await repository.get(id: id) }

    @discardableResult
    public func save(
        id: String,
        displayName: String,
        headline: String,
        biography: String,
        context: MutationContext
    ) async throws -> ProfileRecord {
        let fields = ProfileInputValidator.normalized(
            displayName: displayName,
            headline: headline,
            biography: biography
        )
        guard ProfileInputValidator.validate(
            displayName: fields.displayName,
            headline: fields.headline,
            biography: fields.biography
        ).isValid else { throw YouContractError.invalidProfile }
        let record = ProfileRecord(
            id: id,
            displayName: fields.displayName,
            headline: fields.headline,
            biography: fields.biography,
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
