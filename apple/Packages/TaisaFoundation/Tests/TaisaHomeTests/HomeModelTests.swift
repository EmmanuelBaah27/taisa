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
