import Foundation

enum MarketClock {
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
