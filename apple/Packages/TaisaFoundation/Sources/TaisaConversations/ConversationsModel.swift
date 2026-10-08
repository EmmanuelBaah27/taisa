import Foundation
import Observation
import TaisaStorage

public enum ConversationsIssue: Sendable, Equatable {
    case storageUnavailable
    case recoveryRequired
}

public enum ConversationsState: Sendable, Equatable {
    case idle
    case loading
    case empty
    case content(ConversationIndexSnapshot, isRefreshing: Bool, issue: ConversationsIssue?)
    case failure(ConversationsIssue)
}

public struct ConversationsClient: Sendable {
    public var load: @Sendable () async throws -> ConversationIndexSnapshot
    public var discardDraft: @Sendable (String) async throws -> Void
    public var renameConversation: @Sendable (String, String) async throws -> Void
    public var deleteConversation: @Sendable (String) async throws -> Void

    public init(
        load: @escaping @Sendable () async throws -> ConversationIndexSnapshot,
        discardDraft: @escaping @Sendable (String) async throws -> Void = { _ in },
        renameConversation: @escaping @Sendable (String, String) async throws -> Void = { _, _ in },
        deleteConversation: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.load = load
        self.discardDraft = discardDraft
        self.renameConversation = renameConversation
        self.deleteConversation = deleteConversation
    }

    public static func local(store: TaisaStore, deviceID: String = UUID().uuidString) -> ConversationsClient {
        let query = ConversationQuery(store: store)
        let repository = ConversationRepository(store: store)
        let context: @Sendable () -> MutationContext = {
            MutationContext(
                id: UUID().uuidString,
                deviceID: deviceID,
                timestamp: Int64(Date().timeIntervalSince1970 * 1_000)
            )
        }
        return ConversationsClient(
            load: { try await query.loadIndex() },
            discardDraft: { try await repository.discardDraft(id: $0) },
            renameConversation: { try await repository.rename(id: $0, title: $1, context: context()) },
            deleteConversation: { try await repository.delete(id: $0, context: context()) }
        )
    }
}

@MainActor
@Observable
public final class ConversationsModel {
    public private(set) var state: ConversationsState
    @ObservationIgnored private let client: ConversationsClient
    @ObservationIgnored private var generation = 0

    public init(client: ConversationsClient, initialState: ConversationsState = .idle) {
        self.client = client
        self.state = initialState
    }

    public var snapshot: ConversationIndexSnapshot {
        state.snapshot ?? ConversationIndexSnapshot(drafts: [], conversations: [])
    }

    public func load() async {
        generation += 1
        let activeGeneration = generation
        let retained = state.snapshot
        state = retained.map { .content($0, isRefreshing: true, issue: nil) } ?? .loading

        do {
            let loaded = try await client.load()
            guard generation == activeGeneration else { return }
            let sorted = ConversationIndexSnapshot(
                drafts: loaded.drafts.sorted(by: Self.newerDraft),
                conversations: loaded.conversations.sorted(by: Self.newerConversation)
            )
            state = sorted.drafts.isEmpty && sorted.conversations.isEmpty
                ? .empty
                : .content(sorted, isRefreshing: false, issue: nil)
        } catch {
            guard generation == activeGeneration else { return }
            let issue = Self.issue(for: error)
            state = retained.map { .content($0, isRefreshing: false, issue: issue) } ?? .failure(issue)
        }
    }

    public func discardDraft(id: String) async {
        await mutate { try await client.discardDraft(id) }
    }

    public func renameConversation(id: String, title: String) async {
        await mutate { try await client.renameConversation(id, title) }
    }

    public func deleteConversation(id: String) async {
        await mutate { try await client.deleteConversation(id) }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
        } catch {
            let issue = Self.issue(for: error)
            if let retained = state.snapshot {
                state = .content(retained, isRefreshing: false, issue: issue)
            } else {
                state = .failure(issue)
            }
        }
    }

    private static func newerDraft(_ lhs: ConversationDraftRecord, _ rhs: ConversationDraftRecord) -> Bool {
        lhs.updatedAtMS == rhs.updatedAtMS ? lhs.id < rhs.id : lhs.updatedAtMS > rhs.updatedAtMS
    }

    private static func newerConversation(_ lhs: ConversationRecord, _ rhs: ConversationRecord) -> Bool {
        lhs.updatedAtMS == rhs.updatedAtMS ? lhs.id < rhs.id : lhs.updatedAtMS > rhs.updatedAtMS
    }

    private static func issue(for error: any Error) -> ConversationsIssue {
        guard let storage = error as? StorageError else { return .storageUnavailable }
        switch storage {
        case .missingKeyForExistingStore, .authenticationFailed, .integrityFailed,
             .schemaMismatch, .unsupportedMigration, .unsupportedSchemaVersion:
            return .recoveryRequired
        default:
            return .storageUnavailable
        }
    }
}

private extension ConversationsState {
    var snapshot: ConversationIndexSnapshot? {
        guard case let .content(snapshot, _, _) = self else { return nil }
        return snapshot
    }
}
