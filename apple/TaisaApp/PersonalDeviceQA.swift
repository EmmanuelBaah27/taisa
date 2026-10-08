#if TAISA_PERSONAL
import CryptoKit
import Foundation
import GRDB
import TaisaStorage

/// Opt-in device evidence only. Inspection never writes a canary: otherwise a
/// lost installation or unsuccessful restore could look like preserved data.
actor PersonalDeviceQA {
    static let launchArgument = "--taisa-personal-device-qa"
    enum Failure: Error { case canaryConflict }
    struct Evidence: Equatable, Sendable {
        let canaryCount: Int
        let conversationCount: Int
        let hash: String?
    }

    private struct CanaryDigestV1: Encodable {
        let createdAtMS: Int64
        let id: String
        let title: String
        let updatedAtMS: Int64
    }

    private static let canary = ConversationRecord(
        id: "00000000-0000-4000-8000-000000000601",
        title: "Taisa public device QA canary v1", createdAtMS: 0, updatedAtMS: 0)
    private static let mutation = MutationContext(
        id: "00000000-0000-4000-8000-000000000602",
        deviceID: "00000000-0000-4000-8000-000000000603", timestamp: 0)
    private static let digestPayload = CanaryDigestV1(
        createdAtMS: canary.createdAtMS,
        id: canary.id,
        title: canary.title,
        updatedAtMS: canary.updatedAtMS
    )
    private let backend: PersonalRecoveryBackend

    init?(backend: PersonalRecoveryBackend, arguments: [String]) {
        guard arguments.contains(Self.launchArgument) else { return nil }
        self.backend = backend
    }

    func inspect() async throws -> Evidence {
        let store = try await backend.openStore()
        let record = try await ConversationRepository(store: store).get(id: Self.canary.id)
        let count = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM conversations") ?? 0
        }
        // Never hash, render or log unexpected/private content at this ID.
        guard record == Self.canary else {
            return Evidence(canaryCount: 0, conversationCount: count, hash: nil)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(Self.digestPayload))
            .map { String(format: "%02x", $0) }.joined()
        return Evidence(canaryCount: 1, conversationCount: count, hash: digest)
    }

    func createCanary() async throws -> Evidence {
        let repository = ConversationRepository(store: try await backend.openStore())
        if let existing = try await repository.get(id: Self.canary.id) {
            guard existing == Self.canary else { throw Failure.canaryConflict }
        } else {
            // Stable record AND mutation identities make repeated/concurrent taps
            // idempotent in the real repository's encrypted write transaction.
            try await repository.create(Self.canary, context: Self.mutation)
        }
        let evidence = try await inspect()
        guard evidence.canaryCount == 1 else { throw Failure.canaryConflict }
        return evidence
    }
}
#endif
