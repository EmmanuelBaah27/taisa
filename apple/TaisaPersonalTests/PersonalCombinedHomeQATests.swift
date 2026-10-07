import Testing
import TaisaHome
@testable import TaisaPersonal

@Suite @MainActor struct PersonalCombinedHomeQATests {
    @Test func fixtureExposesCombinedHomeWithoutUsingThePersonalStore() async throws {
        let fixture = PersonalCombinedHomeQA.fixture()

        await fixture.home.load()
        guard case let .content(snapshot, isRefreshing, issue) = fixture.home.state else {
            Issue.record("Expected a populated combined Home fixture")
            return
        }

        #expect(!isRefreshing)
        #expect(issue == nil)
        #expect(snapshot.thisWeek.count == 1)
        #expect(snapshot.unresolvedPriorWeekCount == 2)
        #expect(snapshot.leadInsight != nil)
        #expect(snapshot.hasConfirmedInsightHistory)

        await fixture.insights.load()
        guard case let .content(insights) = fixture.insights.state else {
            Issue.record("Expected current, review-needed, and historical insight fixtures")
            return
        }
        #expect(insights.current.count == 1)
        #expect(insights.reviewNeeded.count == 1)
        #expect(insights.history.count == 1)
    }

    @Test func fixtureSupportsCompletionAndImmediateUndo() async throws {
        let fixture = PersonalCombinedHomeQA.fixture()
        await fixture.home.load()
        guard case let .content(initial, _, _) = fixture.home.state,
              let item = initial.thisWeek.first else {
            Issue.record("Expected an initial weekly item")
            return
        }

        await fixture.home.complete(actionID: item.action.id)
        guard case let .content(completed, _, _) = fixture.home.state else {
            Issue.record("Expected Home to remain usable after completion")
            return
        }
        #expect(completed.thisWeek.isEmpty)
        #expect(fixture.home.canUndoCompletion)

        await fixture.home.undoCompletion()
        guard case let .content(restored, _, _) = fixture.home.state else {
            Issue.record("Expected Home to remain usable after Undo")
            return
        }
        #expect(restored.thisWeek.map(\.action.id) == [item.action.id])
        #expect(!fixture.home.canUndoCompletion)
    }
}
