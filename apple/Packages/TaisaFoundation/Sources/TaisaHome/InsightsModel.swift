import Observation
import TaisaStorage

public enum InsightsState: Sendable, Equatable {
    case idle
    case loading
    case content(InsightsSnapshot)
    case empty
    case failure
}

public enum InsightDetailState: Sendable, Equatable {
    case idle
    case loading(InsightRecord)
    case content(InsightDetailSnapshot)
    case failure(InsightRecord)
}

@MainActor
@Observable
public final class InsightsModel {
    public private(set) var state: InsightsState = .idle
    public private(set) var detailState: InsightDetailState = .idle

    @ObservationIgnored private let client: InsightsClient
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var detailGeneration = 0

    public init(client: InsightsClient) { self.client = client }

    public func load() async {
        loadGeneration += 1
        let active = loadGeneration
        state = .loading
        do {
            let snapshot = try await client.load()
            guard active == loadGeneration else { return }
            state = snapshot.isEmpty ? .empty : .content(snapshot)
        } catch {
            guard active == loadGeneration else { return }
            state = .failure
        }
    }

    public func loadDetail(insight: InsightRecord) async {
        detailGeneration += 1
        let active = detailGeneration
        detailState = .loading(insight)
        do {
            let detail = try await client.detail(insight)
            guard active == detailGeneration else { return }
            detailState = .content(detail)
        } catch {
            guard active == detailGeneration else { return }
            detailState = .failure(insight)
        }
    }
}
