import SwiftUI

struct FoundationRootView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Taisa")
                    .font(.largeTitle.bold())
                Text("Native foundation ready")
                    .font(.body)
#if DEBUG || TAISA_PREVIEW
                NavigationLink("Build diagnostics") {
                    BuildDiagnosticsView()
                }
#endif
            }
            .padding()
            .accessibilityIdentifier("foundation.root")
        }
    }
}

#Preview {
    FoundationRootView()
}
