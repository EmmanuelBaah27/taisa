import Foundation
import XCTest
import TaisaHome
import TaisaStorage
@testable import Taisa

@MainActor
final class AppRuntimeTests: XCTestCase {
    func testSuccessfulStartBuildsHomeModel() async {
        let runtime = AppRuntime(start: { HomeClient { HomeSnapshot(conversations: [], goals: [], actions: []) } })
        let state = await runtime.start()
        XCTAssertEqual(state, .ready)
        XCTAssertNotNil(runtime.homeModel)
    }

    func testStorageFailuresRouteToRecovery() async {
        for error in [StorageError.missingKeyForExistingStore, .integrityFailed, .authenticationFailed] {
            let runtime = AppRuntime(start: { throw error })
            let state = await runtime.start()
            XCTAssertEqual(state, .recoveryRequired)
            XCTAssertNil(runtime.homeModel)
        }
    }

    func testMissingKeyRouteDoesNotTouchExistingStoreBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("taisa.sqlite")
        let original = Data("existing encrypted store".utf8)
        try original.write(to: storeURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)

        let runtime = AppRuntime(start: { throw StorageError.missingKeyForExistingStore })
        let state = await runtime.start()
        XCTAssertEqual(state, .recoveryRequired)
        XCTAssertEqual(try Data(contentsOf: storeURL), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: storeURL.path)[.systemFileNumber] as? NSNumber,
                       attributes[.systemFileNumber] as? NSNumber)
    }
}
