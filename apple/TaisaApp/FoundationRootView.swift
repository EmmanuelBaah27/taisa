import SwiftUI

struct FoundationRootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Taisa")
                .font(.largeTitle.bold())
            Text("Native foundation ready")
                .font(.body)
        }
        .padding()
        .accessibilityIdentifier("foundation.root")
    }
}

#Preview {
    FoundationRootView()
}
