import Foundation
import XCTest
import TaisaHome
import TaisaStorage
@testable import Taisa

@MainActor
final class AppRuntimeTests: XCTestCase {
    func testLiveRuntimeUsesMutationCapableLocalHomeClient() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("TaisaApp/App/AppRuntime.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("let context = try await backend.voiceStoreContext()"))
        XCTAssertTrue(source.contains("HomeClient.local(store: store, deviceID: context.deviceID.uuidString)"))
        XCTAssertFalse(source.contains("HomeClient { try await HomeQuery"))
    }

    func testSuccessfulStartBuildsHomeModel() async {
        let runtime = AppRuntime(start: { .test(home: HomeClient { HomeSnapshot(conversations: [], goals: [], actions: []) }) })
        let state = await runtime.start()
        XCTAssertEqual(state, .ready)
        XCTAssertNotNil(runtime.homeModel)
        XCTAssertNotNil(runtime.insightsModel)
    }

    func testStorageFailuresRouteToRecovery() async {
        for error in [StorageError.missingKeyForExistingStore, .integrityFailed, .authenticationFailed] {
            let runtime = AppRuntime(start: { throw error })
            let state = await runtime.start()
            XCTAssertEqual(state, .recoveryRequired)
            XCTAssertNil(runtime.homeModel)
            XCTAssertNil(runtime.insightsModel)
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

private extension AppRuntime.Clients {
    static func test(home: HomeClient) -> Self {
        .init(
            home: home,
            insights: InsightsClient(load: { .empty }, detail: { insight in
                .init(insight: insight, sources: [], revisions: [])
            })
        )
    }
}
