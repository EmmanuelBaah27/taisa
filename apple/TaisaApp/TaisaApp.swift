import SwiftUI
import TaisaDesignSystem

@main
struct TaisaApp: App {
    @State private var runtime = AppRuntime.live()

    var body: some Scene {
        WindowGroup {
            AppRootView(runtime: runtime)
                .buttonStyle(TaisaButtonStyle())
                .preferredColorScheme(.light)
        }
    }
}
