import Testing
@testable import TaisaPreviewSupport

@Suite("Denied preview transport")
struct DeniedNetworkTransportTests {
    @Test func transportNeverStartsARequest() async {
        await #expect(throws: PreviewTransportError.externalNetworkingDenied) {
            try await DeniedNetworkTransport().send(.fixture)
        }
    }
}
