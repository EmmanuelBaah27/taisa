import SwiftUI
import TaisaHome
import TaisaStorage

struct HomeScenarioView: View {
    let mode: HomeScenarioMode
    @State private var model: HomeModel

    init(mode: HomeScenarioMode) {
        self.mode = mode
        let state: HomeState
        switch mode {
        case .loading:
            state = .loading
        case .empty:
            state = .empty
        case .content:
            state = .content(.previewContent, isRefreshing: false, issue: nil)
        case .refreshing:
            state = .content(.previewContent, isRefreshing: true, issue: nil)
        case .failure:
            state = .failure(.storageUnavailable)
        case .recovery:
            state = .failure(.recoveryRequired)
        }
        _model = State(initialValue: HomeModel(client: HomeClient { .previewEmpty }, initialState: state))
    }

    var body: some View {
        HomeView(model: model, ownsNavigation: false)
            .frame(minHeight: 700)
    }
}
