import SwiftUI
import TaisaDesignSystem

@main
struct TaisaPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            PreviewCatalogView()
                .taisaTypography(.body)
                .buttonStyle(TaisaButtonStyle())
        }
    }
}
