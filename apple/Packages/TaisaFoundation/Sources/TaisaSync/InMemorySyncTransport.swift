import Foundation

/// Deterministic transport shared by independent local stores. It never opens CloudKit.
public actor InMemorySyncTransport: SyncTransport {
    private var fingerprint: Data
    private var accountOverride: SyncAccountState?
    private var changes: [EncryptedChange] = []
    private var nextSendError: SyncTransportError?
    private var nextFetchError: SyncTransportError?
    private var nextPartialFailures: [String: SyncTransportError] = [:]
    private var duplicateNextFetch = false
    private var reverseNextFetch = false
    private var accountAfterSend: Data?
    private var cancelFetchedTurn = false
    private var pageLimit = 200

    public init(accountFingerprint: Data) { fingerprint = accountFingerprint }

    public func accountState() async -> SyncAccountState { accountOverride ?? .available(fingerprint: fingerprint) }
    public func setAccountFingerprint(_ value: Data) { fingerprint = value; accountOverride = nil }
    public func setAccountState(_ value: SyncAccountState?) { accountOverride = value }
    public func failNextSend(_ error: SyncTransportError) { nextSendError = error }
    public func failNextFetch(_ error: SyncTransportError) { nextFetchError = error }
    public func failNextItems(_ failures: [String: SyncTransportError]) { nextPartialFailures = failures }
    public func duplicateNextDownload() { duplicateNextFetch = true }
    public func reverseNextDownload() { reverseNextFetch = true }
    public func changeAccountAfterNextSend(to value: Data) { accountAfterSend = value }
    public func cancelNextFetch() { cancelFetchedTurn = true }
    public func setPageLimit(_ value: Int) { pageLimit = max(1, value) }
    public func allChanges() -> [EncryptedChange] { changes }

    public func send(_ incoming: [EncryptedChange]) async throws -> SyncSendResult {
        if let error = nextSendError { nextSendError = nil; throw error }
        let failures = nextPartialFailures
        nextPartialFailures = [:]
        var acknowledgements: [String] = []
        for change in incoming {
            if failures[change.id] != nil { continue }
            if let existing = changes.first(where: { $0.id == change.id }) {
                guard existing.envelope.metadata == change.envelope.metadata else { throw SyncTransportError.permission }
            } else {
                changes.append(change)
            }
            acknowledgements.append(change.id)
        }
        if let accountAfterSend {
            fingerprint = accountAfterSend
            self.accountAfterSend = nil
        }
        return SyncSendResult(acknowledgedIDs: acknowledgements, failures: failures)
    }

    public func fetch(after token: Data?) async throws -> SyncFetchPage {
        if let error = nextFetchError { nextFetchError = nil; throw error }
        let offset: Int
        if let token {
            guard let text = String(data: token, encoding: .utf8), let parsed = Int(text), parsed >= 0, parsed <= changes.count else {
                throw SyncTransportError.tokenExpired
            }
            offset = parsed
        } else { offset = 0 }
        let end = min(changes.count, offset + pageLimit)
        var page = Array(changes[offset..<end])
        if reverseNextFetch { page.reverse(); reverseNextFetch = false }
        if duplicateNextFetch, let first = page.first { page.append(first); duplicateNextFetch = false }
        if cancelFetchedTurn {
            cancelFetchedTurn = false
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return SyncFetchPage(changes: page, token: Data(String(end).utf8), hasMore: end < changes.count)
    }
}
