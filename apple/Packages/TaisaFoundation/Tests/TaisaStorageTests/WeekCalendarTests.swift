import Foundation
import Testing
@testable import TaisaStorage

@Suite struct WeekCalendarTests {
    @Test func localWeekRunsMondayThroughSundayAcrossSpringDST() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let instant = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))

        let week = try WeekCalendar(timeZone: zone).week(containing: instant)

        #expect(calendar.component(.weekday, from: week.start) == 2)
        #expect(calendar.dateComponents([.year, .month, .day], from: week.start) == DateComponents(year: 2026, month: 3, day: 2))
        #expect(calendar.dateComponents([.year, .month, .day], from: week.end) == DateComponents(year: 2026, month: 3, day: 9))
        #expect(week.end.timeIntervalSince(week.start) == 167 * 60 * 60)
    }

    @Test func plannedDayMustBelongToTheLocalWeek() throws {
        let zone = try #require(TimeZone(identifier: "Africa/Accra"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)))
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 20)))
        let followingMonday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let weeks = WeekCalendar(timeZone: zone)

        let placement = try weeks.placement(weekContaining: monday, plannedDay: sunday)
        #expect(placement.weekStart == calendar.startOfDay(for: monday))
        #expect(placement.plannedDay == calendar.startOfDay(for: sunday))
        #expect(throws: WeekCalendarError.plannedDayOutsideWeek) {
            try weeks.placement(weekContaining: monday, plannedDay: followingMonday)
        }
    }
}
