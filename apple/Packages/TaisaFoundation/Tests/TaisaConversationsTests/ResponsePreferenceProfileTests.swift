import Testing
import TaisaStorage
@testable import TaisaConversations

struct ResponsePreferenceProfileTests {
    @Test func requiresTwoMatchingRecentSignalsAndNeutralizesConflicts() {
        let feedback = [
            item(1, .helpful, [.communicationClarity, .evidenceFidelity]),
            item(2, .helpful, [.communicationClarity]),
            item(3, .notHelpful, [.coverage]),
            item(4, .helpful, [.coverage]),
            item(5, .notHelpful, [.relationalFit]),
            item(6, .notHelpful, [.relationalFit]),
        ]
        #expect(ResponsePreferenceProfile.derive(from: feedback) == [
            .init(factor: .communicationClarity, direction: .helpful),
            .init(factor: .relationalFit, direction: .notHelpful),
        ])
    }

    @Test func usesOnlyLatestTenAndCapsOutputAtFive() {
        let factors = ResponseQualityFactor.allCases.filter { $0 != .evidenceFidelity }
        let feedback = (0..<12).map { index in
            item(index, .helpful, index < 10 ? factors : [.coverage])
        }
        #expect(ResponsePreferenceProfile.derive(from: feedback).count == 5)
        #expect(!ResponsePreferenceProfile.derive(from: feedback).contains { $0.factor == .evidenceFidelity })
    }

    private func item(_ index: Int, _ direction: ResponseFeedbackDirection, _ factors: [ResponseQualityFactor]) -> ResponseFeedbackRecord {
        .init(responseMessageID: String(format: "10000000-0000-4000-8000-%012d", index), direction: direction, factors: factors, detail: "Never routed as instructions", updatedAtMS: Int64(index))
    }
}
