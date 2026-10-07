import Foundation
import Testing
@testable import TaisaHome
import TaisaStorage

@Suite(.serialized) @MainActor struct HomeModelTests {
    @Test func firstLoadMovesThroughLoadingToContent() async {
        let gate = LoadGate()
        let model = HomeModel(client: HomeClient { try await gate.next() })

        let load = Task { await model.load() }
        await gate.waitForRequests(1)
        #expect(model.state == .loading)
        await gate.resolveNext(with: populatedSnapshot(title: "Current"))
        await load.value

        #expect(model.state == .content(populatedSnapshot(title: "Current"), isRefreshing: false, issue: nil))
    }

    @Test func emptyLoadPublishesEmpty() async {
        let model = HomeModel(client: HomeClient { .empty })
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func refreshPreservesContentAndClearsRefreshStateOnSuccess() async {
        let gate = LoadGate()
        let model = HomeModel(client: HomeClient { try await gate.next() })
        let initialLoad = Task { await model.load() }
        await gate.waitForRequests(1)
        await gate.resolveNext(with: populatedSnapshot(title: "Initial"))
        await initialLoad.value

        let refresh = Task { await model.load() }
        await gate.waitForRequests(2)
        #expect(model.state == .content(populatedSnapshot(title: "Initial"), isRefreshing: true, issue: nil))
        await gate.resolveNext(with: populatedSnapshot(title: "Updated"))
        await refresh.value
        #expect(model.state == .content(populatedSnapshot(title: "Updated"), isRefreshing: false, issue: nil))
    }

    @Test func failureWithoutContentPublishesSafeIssue() async {
        let model = HomeModel(client: HomeClient { throw StorageError.openFailed })
        await model.load()
        #expect(model.state == .failure(.storageUnavailable))
    }

    @Test func recoveryFailureIsCategorizedWithoutLeakingDetails() async {
        let model = HomeModel(client: HomeClient { throw StorageError.integrityFailed })
        await model.load()
        #expect(model.state == .failure(.recoveryRequired))
    }

    @Test func refreshFailurePreservesContentAndRetryCanRecover() async {
        let responses = ResponseQueue([
            .success(populatedSnapshot(title: "Initial")),
            .failure(StorageError.openFailed),
            .success(populatedSnapshot(title: "Recovered")),
        ])
        let model = HomeModel(client: HomeClient { try await responses.next() })

        await model.load()
        await model.load()
        #expect(model.state == .content(populatedSnapshot(title: "Initial"), isRefreshing: false, issue: .storageUnavailable))
        await model.load()
        #expect(model.state == .content(populatedSnapshot(title: "Recovered"), isRefreshing: false, issue: nil))
    }

    @Test func cancellationDoesNotPublishFailure() async {
        let gate = LoadGate()
        let model = HomeModel(client: HomeClient { try await gate.next() })
        let first = Task { await model.load() }
        await gate.waitForRequests(1)
        let second = Task { await model.load() }
        await gate.waitForRequests(2)
        await gate.resolveNext(with: populatedSnapshot(title: "Stale"))
        await gate.resolveNext(with: populatedSnapshot(title: "Current"))
        await first.value
        await second.value

        #expect(model.state == .content(populatedSnapshot(title: "Current"), isRefreshing: false, issue: nil))
    }

    @Test func olderCompletionCannotOverwriteNewerResult() async {
        let gate = LoadGate(ignoresCancellation: true)
        let model = HomeModel(client: HomeClient { try await gate.next() })
        let older = Task { await model.load() }
        await gate.waitForRequests(1)
        let newer = Task { await model.load() }
        await gate.waitForRequests(2)
        await gate.resolveRequest(1, with: populatedSnapshot(title: "Newest"))
        await newer.value
        await gate.resolveRequest(0, with: populatedSnapshot(title: "Oldest"))
        await older.value

        #expect(model.state == .content(populatedSnapshot(title: "Newest"), isRefreshing: false, issue: nil))
    }

    @Test func completeUndoPlaceAndMoveUseLocalMutationsThenReload() async throws {
        let recorder = MutationRecorder()
        let action = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Work", detail: "", status: "open", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 1)
        let token = WeeklyWorkUndoToken(action: action)
        let responses = ResponseQueue([
            .success(populatedSnapshot(title: "Initial")),
            .success(populatedSnapshot(title: "Completed")),
            .success(populatedSnapshot(title: "Restored")),
            .success(populatedSnapshot(title: "Placed")),
            .success(populatedSnapshot(title: "Moved")),
        ])
        let model = HomeModel(client: HomeClient(
            load: { try await responses.next() },
            complete: { id in await recorder.record("complete", id: id); return token },
            restore: { value in await recorder.record("restore", id: value.action.id) },
            place: { id, _, _ in await recorder.record("place", id: id) },
            move: { id, _, _ in await recorder.record("move", id: id) }
        ))
        await model.load()

        await model.complete(actionID: action.id)
        #expect(model.canUndoCompletion)
        await model.undoCompletion()
        #expect(!model.canUndoCompletion)
        await model.place(actionID: action.id, weekContaining: Date(timeIntervalSince1970: 100), plannedDay: nil)
        await model.move(actionID: action.id, weekContaining: Date(timeIntervalSince1970: 200), plannedDay: Date(timeIntervalSince1970: 300))

        #expect(await recorder.values == ["complete:\(action.id)", "restore:\(action.id)", "place:\(action.id)", "move:\(action.id)"])
        #expect(model.state == .content(populatedSnapshot(title: "Moved"), isRefreshing: false, issue: nil))
    }

    @Test func staleMutationCompletionCannotOverwriteNewerLocalState() async {
        let gate = CompletionGate()
        let responses = ResponseQueue([.success(populatedSnapshot(title: "Newest"))])
        let model = HomeModel(client: HomeClient(load: { try await responses.next() }, complete: { try await gate.next(id: $0) }))
        let olderID = UUID().uuidString
        let newerID = UUID().uuidString

        let older = Task { await model.complete(actionID: olderID) }
        await gate.waitForRequests(1)
        let newer = Task { await model.complete(actionID: newerID) }
        await gate.waitForRequests(2)
        await gate.resolveRequest(1)
        await newer.value
        await gate.resolveRequest(0)
        await older.value

        #expect(model.completionUndoToken?.action.id == newerID)
        #expect(model.state == .content(populatedSnapshot(title: "Newest"), isRefreshing: false, issue: nil))
    }

    @Test func localClientLoadsAndMutatesUsingOnlyEncryptedStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await TaisaStore.open(at: directory.appendingPathComponent("store.sqlite"), keyStore: HomeKeys())
        let deviceID = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_782_086_400)
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let action = ActionRecord(id: UUID().uuidString, goalID: nil, title: "Local", detail: "", status: "open", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 1)
        try await ActionRepository(store: store).create(action, context: .init(id: UUID().uuidString, deviceID: deviceID, timestamp: 1))
        let client = HomeClient.local(store: store, deviceID: deviceID, now: { date }, timeZone: { timeZone })

        try await client.place(action.id, date, nil)
        #expect(try await client.load().thisWeek.map(\.action.id) == [action.id])
        let token = try await client.complete(action.id)
        #expect(try await client.load().thisWeek.isEmpty)
        try await client.restore(token)
        #expect(try await client.load().thisWeek.map(\.action.id) == [action.id])
    }
}

private extension HomeSnapshot {
    static let empty = HomeSnapshot(conversations: [], goals: [], actions: [])
}

private func populatedSnapshot(title: String) -> HomeSnapshot {
    HomeSnapshot(
        conversations: [ConversationRecord(id: "00000000-0000-0000-0000-000000000001", title: title, createdAtMS: 1, updatedAtMS: 1)],
        goals: [],
        actions: []
    )
}

private actor ResponseQueue {
    private var responses: [Result<HomeSnapshot, any Error>]
    init(_ responses: [Result<HomeSnapshot, any Error>]) { self.responses = responses }
    func next() throws -> HomeSnapshot { try responses.removeFirst().get() }
}

private actor LoadGate {
    private struct Request {
        let continuation: CheckedContinuation<HomeSnapshot, any Error>
    }
    private var requests: [Request] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var requestCount = 0
    private let ignoresCancellation: Bool

    init(ignoresCancellation: Bool = false) {
        self.ignoresCancellation = ignoresCancellation
    }

    func next() async throws -> HomeSnapshot {
        let value = try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(continuation: continuation))
            requestCount += 1
            releaseWaiters()
        }
        if !ignoresCancellation { try Task.checkCancellation() }
        return value
    }

    func waitForRequests(_ count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func resolveNext(with snapshot: HomeSnapshot) {
        requests.first(where: { _ in true })?.continuation.resume(returning: snapshot)
        requests.removeFirst()
    }

    func resolveRequest(_ index: Int, with snapshot: HomeSnapshot) {
        requests[index].continuation.resume(returning: snapshot)
        requests.remove(at: index)
    }

    private func releaseWaiters() {
        let ready = waiters.filter { requestCount >= $0.0 }
        waiters.removeAll { requestCount >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

private actor MutationRecorder {
    private(set) var values: [String] = []
    func record(_ operation: String, id: String) { values.append("\(operation):\(id)") }
}

private actor HomeKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { self.key = key }
}

private actor CompletionGate {
    private struct Request { let id: String; let continuation: CheckedContinuation<WeeklyWorkUndoToken, any Error> }
    private var requests: [Request] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func next(id: String) async throws -> WeeklyWorkUndoToken {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(id: id, continuation: continuation))
            let ready = waiters.filter { requests.count >= $0.0 }
            waiters.removeAll { requests.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func resolveRequest(_ index: Int) {
        let request = requests.remove(at: index)
        request.continuation.resume(returning: WeeklyWorkUndoToken(action: ActionRecord(id: request.id, goalID: nil, title: "", detail: "", status: "open", dueAtMS: nil, createdAtMS: 1, updatedAtMS: 1)))
    }
}
