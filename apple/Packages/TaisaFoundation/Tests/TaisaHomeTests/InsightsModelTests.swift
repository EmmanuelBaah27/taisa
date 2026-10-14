import Foundation
import Testing
@testable import TaisaHome
import TaisaStorage

@Suite @MainActor struct InsightsModelTests {
    @Test func loadPublishesCurrentReviewAndHistoryWithoutFlatteningThem() async {
        let current = insight("Current", status: .confirmed)
        let review = insight("Review", status: .reviewNeeded)
        let retired = insight("Retired", status: .retired)
        let model = InsightsModel(client: InsightsClient(
            load: { InsightsSnapshot(current: [current], reviewNeeded: [review], history: [retired]) },
            detail: { _ in InsightDetailSnapshot(insight: current, sources: [], revisions: []) }
        ))

        await model.load()

        #expect(model.state == .content(.init(current: [current], reviewNeeded: [review], history: [retired])))
    }

    @Test func detailLoadsGroundingAndRevisionEvidence() async {
        let record = insight("Grounded", status: .confirmed)
        let source = InsightSourceRecord(
            id: "00000000-0000-0000-0000-000000000010",
            insightID: record.id,
            sourceType: "conversation",
            sourceID: "00000000-0000-0000-0000-000000000011",
            excerpt: "Source excerpt",
            createdAtMS: 1
        )
        let revision = InsightRevisionRecord(
            id: "00000000-0000-0000-0000-000000000012",
            insightID: record.id,
            proposedBody: "Earlier wording",
            status: .accepted,
            sourceType: "conversation",
            sourceID: source.sourceID,
            createdAtMS: 1,
            resolvedAtMS: 2
        )
        let expected = InsightDetailSnapshot(insight: record, sources: [source], revisions: [revision])
        let model = InsightsModel(client: InsightsClient(load: { .empty }, detail: { _ in expected }))

        await model.loadDetail(insight: record)

        #expect(model.detailState == .content(expected))
    }

    @Test func storageFailurePublishesSafeFailureState() async {
        let model = InsightsModel(client: InsightsClient(
            load: { throw StorageError.openFailed },
            detail: { _ in throw StorageError.openFailed }
        ))

        await model.load()

        #expect(model.state == .failure)
    }
}

private func insight(_ body: String, status: InsightStatus) -> InsightRecord {
    InsightRecord(
        id: UUID().uuidString,
        body: body,
        status: status,
        isTimeSensitive: false,
        homeEligibleUntilMS: nil,
        createdAtMS: 1,
        updatedAtMS: 2
    )
}
