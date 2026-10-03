import SwiftUI

struct PreviewRootView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("Foundation default")
            }
            .navigationTitle("Taisa Preview")
        }
        .accessibilityIdentifier("preview.catalog")
    }
}

#Preview {
    PreviewRootView()
}
