import SwiftUI

struct TranscriptCorrectionView: View {
    @Binding var text: String
    let submit: () -> Void

    var body: some View {
        Form {
            Section("Correct transcript") { TextEditor(text: $text).frame(minHeight: 120) }
            Section { Text("Updating this transcript will regenerate Taisa’s affected reply.") }
            Button("Update and regenerate", action: submit)
        }
    }
}
