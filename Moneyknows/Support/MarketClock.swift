import Foundation

enum MarketClock {
    enum USSessionWindow {
        case premarket
        case regular
        case aftermarket
    }

    static let easternTimeZone = TimeZone(identifier: "America/New_York")!

    static func usDateString(from date: Date = Date()) -> String {
        usDateFormatter.string(from: date)
    }

    static func date(fromUSDate string: String) -> Date? {
        usDateFormatter.date(from: string)
    }

    static func usTimeString(from date: Date = Date()) -> String {
        usTimeFormatter.string(from: date)
    }

    static func regularSessionEndTime(from date: Date = Date()) -> String {
        let current = usTimeString(from: date)
        return current > "16:00" ? "16:00" : current
    }

    static func normalizeEndTime(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        guard let regex = try? NSRegularExpression(pattern: #"^(\d{1,2}):?(\d{2})$"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let hoursRange = Range(match.range(at: 1), in: trimmed),
              let minutesRange = Range(match.range(at: 2), in: trimmed),
              let hours = Int(trimmed[hoursRange]),
              let minutes = Int(trimmed[minutesRange]),
              (0...23).contains(hours),
              (0...59).contains(minutes)
        else {
            return nil
        }
        return String(format: "%02d:%02d", hours, minutes)
    }

    static func isValidRegularSessionEndTime(_ normalized: String?) -> Bool {
        guard let normalized else { return false }
        if normalized.isEmpty { return true }
        return normalized >= "09:30" && normalized <= "16:00"
    }

    static func resolvedPriceSlopeEndTime(_ raw: String, now: Date = Date()) throws -> String {
        let normalized = normalizeEndTime(raw)
        guard isValidRegularSessionEndTime(normalized) else {
            throw AppError.http(status: 400, message: L10n.Market.invalidEndTime, errorCode: nil)
        }
        if let normalized, !normalized.isEmpty {
            return normalized
        }
        return regularSessionEndTime(from: now)
    }

    static func lastTradingDate(from date: Date = Date()) -> String {
        let today = usDateString(from: date)
        let time = usTimeString(from: date)
        if time >= "09:30", isUSTradingDay(today) {
            return today
        }
        return previousTradingDay(before: today)
    }

    static func extendedHoursDate(from date: Date = Date()) -> String {
        let today = usDateString(from: date)
        if isUSTradingDay(today) {
            return usTimeString(from: date) < "04:00" ? previousTradingDay(before: today) : today
        }
        return lastTradingDate(from: date)
    }

    static func isUSTradingDay(_ dateString: String) -> Bool {
        guard let date = date(fromUSDate: dateString) else { return false }
        return isUSWeekday(date) && !isUSMarketHoliday(dateString)
    }

    static func isSessionActive(_ session: USSessionWindow, at date: Date = Date()) -> Bool {
        guard isUSTradingDay(usDateString(from: date)) else { return false }
        let time = usTimeString(from: date)
        switch session {
        case .premarket:
            return time >= "04:00" && time < "09:30"
        case .regular:
            return time >= "09:30" && time < "16:00"
        case .aftermarket:
            return time >= "16:00" && time < "20:00"
        }
    }

    static func shouldPoll(session: USSessionWindow, date: String, now: Date = Date()) -> Bool {
        date == usDateString(from: now) && isSessionActive(session, at: now)
    }

    static func nanosecondsUntilNextMinute(from date: Date = Date()) -> UInt64 {
        let calendar = Calendar(identifier: .gregorian)
        let second = calendar.component(.second, from: date)
        let nanosecond = calendar.component(.nanosecond, from: date)
        let remaining = 60_000_000_000 - (UInt64(second) * 1_000_000_000 + UInt64(nanosecond))
        return max(250_000_000, remaining)
    }

    private static func previousTradingDay(before dateString: String) -> String {
        guard var cursor = date(fromUSDate: dateString) else { return dateString }
        for _ in 0..<14 {
            cursor = easternCalendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            let candidate = usDateString(from: cursor)
            if isUSTradingDay(candidate) { return candidate }
        }
        return dateString
    }

    private static func isUSWeekday(_ date: Date) -> Bool {
        let weekday = easternCalendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    static func isUSMarketHoliday(_ dateString: String) -> Bool {
        usMarketHolidays(forYear: year(in: dateString)).contains(dateString)
    }

    private static func year(in dateString: String) -> Int {
        Int(dateString.prefix(4)) ?? 0
    }

    private static func usMarketHolidays(forYear year: Int) -> Set<String> {
        guard year >= 1971 else { return [] }
        var days: Set<String> = [
            observed(year: year, month: 1, day: 1),
            nthWeekday(2, n: 3, month: 1, year: year),
            nthWeekday(2, n: 3, month: 2, year: year),
            goodFriday(year: year),
            lastWeekday(2, month: 5, year: year),
            observed(year: year, month: 6, day: 19),
            observed(year: year, month: 7, day: 4),
            nthWeekday(2, n: 1, month: 9, year: year),
            nthWeekday(5, n: 4, month: 11, year: year),
            observed(year: year, month: 12, day: 25),
        ]
        let nextNewYear = observed(year: year + 1, month: 1, day: 1)
        if nextNewYear.hasPrefix(String(year)) {
            days.insert(nextNewYear)
        }
        return days
    }

    private static func observed(year: Int, month: Int, day: Int) -> String {
        guard let date = easternDate(year: year, month: month, day: day) else {
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
        let weekday = easternCalendar.component(.weekday, from: date)
        if weekday == 7, let friday = easternCalendar.date(byAdding: .day, value: -1, to: date) {
            return usDateString(from: friday)
        }
        if weekday == 1, let monday = easternCalendar.date(byAdding: .day, value: 1, to: date) {
            return usDateString(from: monday)
        }
        return usDateString(from: date)
    }

    private static func nthWeekday(_ weekday: Int, n: Int, month: Int, year: Int) -> String {
        guard var date = easternDate(year: year, month: month, day: 1) else {
            return String(format: "%04d-%02d-01", year, month)
        }
        var count = 0
        while easternCalendar.component(.month, from: date) == month {
            if easternCalendar.component(.weekday, from: date) == weekday {
                count += 1
                if count == n {
                    return usDateString(from: date)
                }
            }
            date = easternCalendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return usDateString(from: date)
    }

    private static func lastWeekday(_ weekday: Int, month: Int, year: Int) -> String {
        guard let start = easternDate(year: year, month: month, day: 1),
              let nextMonth = easternCalendar.date(byAdding: .month, value: 1, to: start),
              var date = easternCalendar.date(byAdding: .day, value: -1, to: nextMonth)
        else {
            return String(format: "%04d-%02d-01", year, month)
        }
        while easternCalendar.component(.weekday, from: date) != weekday {
            date = easternCalendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return usDateString(from: date)
    }

    private static func goodFriday(year: Int) -> String {
        let easter = easterDate(year: year)
        let friday = easternCalendar.date(byAdding: .day, value: -2, to: easter) ?? easter
        return usDateString(from: friday)
    }

    private static func easterDate(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return easternDate(year: year, month: month, day: day) ?? Date(timeIntervalSince1970: 0)
    }

    private static func easternDate(year: Int, month: Int, day: Int) -> Date? {
        var parts = DateComponents()
        parts.calendar = easternCalendar
        parts.timeZone = easternTimeZone
        parts.year = year
        parts.month = month
        parts.day = day
        return easternCalendar.date(from: parts)
    }

    private static let easternCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = easternTimeZone
        return calendar
    }()

    private static let usDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let usTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
