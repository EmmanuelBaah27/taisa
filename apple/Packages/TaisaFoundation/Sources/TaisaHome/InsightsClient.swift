import TaisaStorage

public struct InsightsSnapshot: Sendable, Equatable {
    public let current: [InsightRecord]
    public let reviewNeeded: [InsightRecord]
    public let history: [InsightRecord]

    public init(current: [InsightRecord], reviewNeeded: [InsightRecord], history: [InsightRecord]) {
        self.current = current
        self.reviewNeeded = reviewNeeded
        self.history = history
    }

    public static let empty = InsightsSnapshot(current: [], reviewNeeded: [], history: [])
    public var isEmpty: Bool { current.isEmpty && reviewNeeded.isEmpty && history.isEmpty }
}

public struct InsightDetailSnapshot: Sendable, Equatable {
    public let insight: InsightRecord
    public let sources: [InsightSourceRecord]
    public let revisions: [InsightRevisionRecord]

    public init(insight: InsightRecord, sources: [InsightSourceRecord], revisions: [InsightRevisionRecord]) {
        self.insight = insight
        self.sources = sources
        self.revisions = revisions
    }
}

public struct InsightsClient: Sendable {
    public var load: @Sendable () async throws -> InsightsSnapshot
    public var detail: @Sendable (InsightRecord) async throws -> InsightDetailSnapshot

    public init(
        load: @escaping @Sendable () async throws -> InsightsSnapshot,
        detail: @escaping @Sendable (InsightRecord) async throws -> InsightDetailSnapshot
    ) {
        self.load = load
        self.detail = detail
    }
}

public extension InsightsClient {
    static func local(store: TaisaStore) -> InsightsClient {
        let query = InsightQuery(store: store)
        return InsightsClient(
            load: {
                async let current = query.current()
                async let reviewNeeded = query.reviewNeeded()
                async let history = query.history()
                return try await InsightsSnapshot(
                    current: current,
                    reviewNeeded: reviewNeeded,
                    history: history
                )
            },
            detail: { insight in
                async let sources = query.sources(insightID: insight.id)
                async let revisions = query.revisions(insightID: insight.id)
                return try await InsightDetailSnapshot(
                    insight: insight,
                    sources: sources,
                    revisions: revisions
                )
            }
        )
    }
}
