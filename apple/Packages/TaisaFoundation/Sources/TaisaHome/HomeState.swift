import TaisaStorage

public enum HomeIssue: Sendable, Equatable {
    case storageUnavailable
    case recoveryRequired
}

public enum HomeState: Sendable, Equatable {
    case idle
    case loading
    case empty
    case content(HomeSnapshot, isRefreshing: Bool, issue: HomeIssue?)
    case failure(HomeIssue)
}
