import Testing
@testable import TaisaCore

@Suite struct SyncCapabilityTests {
    @Test func personalHasOnlyLocalStorageCapability() {
        #expect(SyncCapability.forEnvironment(.personal) == .localOnly)
    }

    @Test func previewRetainsFakeCapability() {
        #expect(SyncCapability.forEnvironment(.preview) == .fakePreview)
    }

    @Test func liveEnvironmentsRetainPrivateCloudKitCapability() {
        #expect(SyncCapability.forEnvironment(.development) == .privateCloudKit)
        #expect(SyncCapability.forEnvironment(.production) == .privateCloudKit)
    }
}
