import SwiftUI
import TaisaHome
import TaisaStorage

struct HomeScenarioView: View {
    let mode: HomeScenarioMode
    @State private var model: HomeModel

    init(mode: HomeScenarioMode) {
        self.mode = mode
        let client: HomeClient
        switch mode {
        case .loading:
            client = HomeClient { try await Task.sleep(for: .seconds(3_600)); return .previewEmpty }
        case .empty:
            client = HomeClient { .previewEmpty }
        case .content:
            client = HomeClient { .previewContent }
        case .refreshing:
            let loader = RefreshingPreviewLoader()
            client = HomeClient { try await loader.load() }
        case .failure:
            client = HomeClient { throw HomeQueryError.readFailed }
        }
        _model = State(initialValue: HomeModel(client: client))
    }

    var body: some View {
        HomeView(model: model)
            .task {
                guard case .refreshing = mode else { return }
                while model.state != .content(.previewContent, isRefreshing: false, issue: nil) {
                    await Task.yield()
                }
                await model.load()
            }
    }
}

private actor RefreshingPreviewLoader {
    private var count = 0

    func load() async throws -> HomeSnapshot {
        count += 1
        if count == 1 { return .previewContent }
        try await Task.sleep(for: .seconds(3_600))
        return .previewContent
    }
}
