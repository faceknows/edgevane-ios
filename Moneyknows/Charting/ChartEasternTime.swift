import Foundation

enum ChartEasternTime {
    struct CalendarDay: Equatable {
        var year: Int
        var month: Int
        var day: Int
    }

    enum TickKind: Equatable {
        case year
        case month
        case dayOfMonth
        case time
        case timeWithSeconds
    }

    static func parse(_ raw: String) -> (instant: Date?, calendarDay: CalendarDay?) {
        if raw.contains("T") {
            return (isoFormatter.date(from: raw), nil)
        }
        return (nil, calendarDay(fromDateOnly: raw))
    }

    static func calendarDay(for date: Date) -> CalendarDay? {
        calendarDay(fromDateOnly: MarketClock.usDateString(from: date))
    }

    static func calendarDay(fromDateOnly raw: String) -> CalendarDay? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            return nil
        }
        return CalendarDay(year: year, month: month, day: day)
    }

    static func dateString(_ day: CalendarDay) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }

    static func date(calendarDay: CalendarDay) -> Date? {
        MarketClock.date(fromUSDate: dateString(calendarDay))
    }

    static func tickLabel(utc: Date?, calendarDay: CalendarDay?, kind: TickKind) -> String {
        if let calendarDay {
            return calendarTick(calendarDay, kind: kind)
        }
        guard let utc else { return "" }
        switch kind {
        case .year:
            return yearFormatter.string(from: utc)
        case .month:
            return monthFormatter.string(from: utc)
        case .dayOfMonth:
            return dayFormatter.string(from: utc)
        case .time:
            return MarketClock.usTimeString(from: utc)
        case .timeWithSeconds:
            return timeWithSecondsFormatter.string(from: utc)
        }
    }

    static func crosshairLabel(utc: Date?, calendarDay: CalendarDay?) -> String {
        if let calendarDay {
            return dateString(calendarDay)
        }
        guard let utc else { return "" }
        return MarketClock.usTimeString(from: utc)
    }

    private static func calendarTick(_ day: CalendarDay, kind: TickKind) -> String {
        switch kind {
        case .year:
            return String(format: "%04d", day.year)
        case .month:
            guard let date = date(calendarDay: day) else {
                return String(format: "%02d", day.month)
            }
            return monthFormatter.string(from: date)
        case .dayOfMonth:
            return String(day.day)
        case .time, .timeWithSeconds:
            return dateString(day)
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let yearFormatter = easternFormatter("yyyy")
    private static let monthFormatter = easternFormatter("MMM")
    private static let dayFormatter = easternFormatter("d")
    private static let timeWithSecondsFormatter = easternFormatter("HH:mm:ss")

    private static func easternFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = MarketClock.easternTimeZone
        formatter.dateFormat = format
        return formatter
    }
}
