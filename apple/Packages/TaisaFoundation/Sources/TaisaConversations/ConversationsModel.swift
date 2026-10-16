import Foundation
import Observation
import TaisaStorage

public enum ConversationsIssue: Sendable, Equatable {
    case storageUnavailable
    case recoveryRequired
    case renameFailed(id: String, title: String)
    case deleteFailed(id: String)
    case discardFailed(id: String)
}

public struct ConversationsNotice: Identifiable, Sendable, Equatable {
    public let id: Int
    public let issue: ConversationsIssue

    public init(id: Int, issue: ConversationsIssue) {
        self.id = id
        self.issue = issue
    }
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
            load: {
                let index = try await query.loadIndex()
                var repaired = false
                for conversation in index.conversations where conversation.titleAuthority == .localFallback {
                    guard let firstUserMessage = try await query.loadConversation(id: conversation.id)
                        .visibleMessages.first(where: { $0.role == "user" })?.body,
                          let title = ConversationTitleDeriver.derive(from: firstUserMessage),
                          title != conversation.title else { continue }
                    try await repository.update(.init(
                        id: conversation.id,
                        title: title,
                        lifecycle: conversation.lifecycle,
                        titleAuthority: .localFallback,
                        createdAtMS: conversation.createdAtMS,
                        updatedAtMS: conversation.updatedAtMS
                    ), context: context())
                    repaired = true
                }
                return repaired ? try await query.loadIndex() : index
            },
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
    public private(set) var notices: [ConversationsNotice] = []
    @ObservationIgnored private let client: ConversationsClient
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var nextNoticeID = 0

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
                conversations: loaded.conversations.sorted(by: Self.newerConversation),
                lastMessagePreviews: loaded.lastMessagePreviews
            )
            state = sorted.drafts.isEmpty && sorted.conversations.isEmpty
                ? .empty
                : .content(sorted, isRefreshing: false, issue: nil)
        } catch {
            guard generation == activeGeneration else { return }
            let issue = Self.issue(for: error)
            if issue == .recoveryRequired {
                notices.removeAll()
                state = .failure(issue)
            } else if let retained {
                state = .content(retained, isRefreshing: false, issue: nil)
                enqueue(issue)
            } else {
                state = .failure(issue)
            }
        }
    }

    public func discardDraft(id: String) async {
        await mutate(fallback: .discardFailed(id: id)) { try await client.discardDraft(id) }
    }

    public func renameConversation(id: String, title: String) async {
        await mutate(fallback: .renameFailed(id: id, title: title)) {
            try await client.renameConversation(id, title)
        }
    }

    public func deleteConversation(id: String) async {
        await mutate(fallback: .deleteFailed(id: id)) { try await client.deleteConversation(id) }
    }

    public func dismissNotice(id: Int) {
        notices.removeAll { $0.id == id }
    }

    private func mutate(fallback: ConversationsIssue, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
        } catch {
            let mapped = Self.issue(for: error)
            let issue = mapped == .recoveryRequired ? mapped : fallback
            if issue == .recoveryRequired {
                notices.removeAll()
                state = .failure(issue)
            } else if let retained = state.snapshot {
                state = .content(retained, isRefreshing: false, issue: nil)
                enqueue(issue)
            } else {
                state = .failure(issue)
            }
        }
    }

    private func enqueue(_ issue: ConversationsIssue) {
        nextNoticeID += 1
        notices.append(ConversationsNotice(id: nextNoticeID, issue: issue))
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
