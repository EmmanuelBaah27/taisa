public enum StorageError: Error, Equatable, Sendable {
    case missingKeyForExistingStore
    case invalidKeyLength
    case randomGenerationFailed
    case keychainFailure(Int32)
    case authenticationFailed
    case openFailed
    case cipherUnavailable
    case integrityFailed
    case configurationFailed
    case migrationFailed
    case schemaMismatch
    case unsupportedMigration
    case unsupportedSchemaVersion(Int)
}
