import Foundation

public enum WeekCalendarError: Error, Sendable, Equatable {
    case invalidWeek
    case plannedDayOutsideWeek
}

public struct LocalWeek: Sendable, Equatable {
    public let start: Date
    public let end: Date
}

public struct WeeklyPlacementDates: Sendable, Equatable {
    public let weekStart: Date
    public let plannedDay: Date?
}

public struct WeekCalendar: Sendable {
    private let calendar: Calendar

    public init(timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 1
        self.calendar = calendar
    }

    public func week(containing date: Date) throws -> LocalWeek {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            throw WeekCalendarError.invalidWeek
        }
        return LocalWeek(start: interval.start, end: interval.end)
    }

    public func placement(weekContaining date: Date, plannedDay: Date?) throws -> WeeklyPlacementDates {
        let week = try week(containing: date)
        let normalizedDay = plannedDay.map(calendar.startOfDay(for:))
        if let normalizedDay, !(week.start..<week.end).contains(normalizedDay) {
            throw WeekCalendarError.plannedDayOutsideWeek
        }
        return WeeklyPlacementDates(weekStart: week.start, plannedDay: normalizedDay)
    }
}
