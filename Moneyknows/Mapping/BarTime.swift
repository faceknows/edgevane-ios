import Foundation

enum BarTime {
    /// JS `Date` / Lightweight Charts clip at ±8.64e15 ms. Keep bars inside 1970–2100 UTC
    /// so overflow values like `1e20` are dropped instead of becoming Invalid Date.
    static let minUnixSeconds: Double = 0
    static let maxUnixSeconds: Double = 4_102_444_800

    static func parseUnix(_ value: Double) -> Date? {
        unixSeconds(value).map { Date(timeIntervalSince1970: $0) }
    }

    static func parse(_ raw: String, date: String? = nil) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed), value.isFinite {
            if let unix = unixSeconds(value) {
                return Date(timeIntervalSince1970: unix)
            }
            if value > 1_000_000_000 {
                return nil
            }
        }
        if let parsed = isoFractional.date(from: trimmed) { return parsed }
        if let parsed = isoInternet.date(from: trimmed) { return parsed }
        if let clock = clockComponents(trimmed), let date, let combined = combine(date: date, clock: clock) {
            return combined
        }
        if trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
           let parsed = MarketClock.date(fromUSDate: trimmed)
        {
            return parsed
        }
        for formatter in dateFormatters {
            if let parsed = formatter.date(from: trimmed) { return parsed }
        }
        return nil
    }

    private static func unixSeconds(_ value: Double) -> Double? {
        let seconds: Double
        if value > 1_000_000_000_000 {
            seconds = value / 1000
        } else if value > 1_000_000_000 {
            seconds = value
        } else {
            return nil
        }
        guard seconds.isFinite, seconds >= minUnixSeconds, seconds <= maxUnixSeconds else {
            return nil
        }
        return seconds
    }

    private static func clockComponents(_ raw: String) -> DateComponents? {
        let match = raw.range(of: #"^(\d{1,2}):(\d{2})(?::(\d{2}))?$"#, options: .regularExpression)
            ?? raw.range(of: #"^(\d{2})(\d{2})$"#, options: .regularExpression)
        guard match != nil else { return nil }
        let parts = raw.split(whereSeparator: { $0 == ":" })
        let hours: Int
        let minutes: Int
        let seconds: Int
        if parts.count == 1, raw.count == 4, let compact = Int(raw) {
            hours = compact / 100
            minutes = compact % 100
            seconds = 0
        } else if parts.count >= 2 {
            guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            hours = h
            minutes = m
            seconds = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        } else {
            return nil
        }
        guard (0...23).contains(hours), (0...59).contains(minutes), (0...59).contains(seconds) else {
            return nil
        }
        var components = DateComponents()
        components.hour = hours
        components.minute = minutes
        components.second = seconds
        return components
    }

    private static func combine(date: String, clock: DateComponents) -> Date? {
        guard let day = MarketClock.date(fromUSDate: date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = MarketClock.easternTimeZone
        return calendar.date(
            bySettingHour: clock.hour ?? 0,
            minute: clock.minute ?? 0,
            second: clock.second ?? 0,
            of: day
        )
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoInternet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"].map { format in
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()
}
