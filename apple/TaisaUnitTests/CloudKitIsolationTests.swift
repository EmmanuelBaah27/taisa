import XCTest
@testable import Taisa

final class CloudKitIsolationTests: XCTestCase {
    func testOnlyApprovedAppIdentitiesCanUseLiveCloudKit() {
        XCTAssertEqual(CloudKitRuntimeConfiguration.containerIdentifier(for: "com.taisa.app.dev"), "iCloud.com.taisa.app.dev")
        XCTAssertEqual(CloudKitRuntimeConfiguration.containerIdentifier(for: "com.taisa.app"), "iCloud.com.taisa.app")
        XCTAssertNil(CloudKitRuntimeConfiguration.containerIdentifier(for: "com.taisa.app.preview"))
        XCTAssertNil(CloudKitRuntimeConfiguration.containerIdentifier(for: "com.taisa.app.attacker"))
    }
}
