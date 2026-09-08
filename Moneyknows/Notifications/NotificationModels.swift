import Foundation

enum NotificationKind: String, CaseIterable, Identifiable {
    case marketTrendUpReversal = "market_trend_up_reversal"
    case marketTrendDownReversal = "market_trend_down_reversal"
    case intradayHighRetest = "intraday_high_retest"
    case intradayLowRetest = "intraday_low_retest"
    case intradayBreakout = "intraday_breakout"
    case intradayWeakPullback = "intraday_weak_pullback"

    var id: String { rawValue }

    var isTrendOrHighLow: Bool {
        switch self {
        case .marketTrendUpReversal, .marketTrendDownReversal, .intradayHighRetest, .intradayLowRetest:
            return true
        case .intradayBreakout, .intradayWeakPullback:
            return false
        }
    }

    static func resolve(_ raw: String?) -> NotificationKind? {
        guard let raw else { return nil }
        return NotificationKind(rawValue: raw)
    }
}

struct AppNotification: Equatable, Identifiable, Codable {
    var id: String
    var userId: String? = nil
    var notificationType: String? = nil
    var title: String
    var body: String
    var sentAt: Int64
    var delivered: Bool? = nil
    var opened: Bool? = nil
    var imageURL: String? = nil
    var data: [String: String]? = nil

    var sentDate: Date {
        Date(timeIntervalSince1970: TimeInterval(sentAt) / 1000)
    }

    var ownerUserId: String? {
        let direct = userId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct, !direct.isEmpty { return direct }
        let nested = data?["userId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nested, !nested.isEmpty { return nested }
        return nil
    }
}

struct ParsedNotification: Equatable {
    var body: String
    var count: Int
    var longSymbols: [String]
    var prioritySymbols: [String]
    var rawType: String?
    var shortSymbols: [String]
    var symbols: [String]
    var kind: NotificationKind?
}

enum NotificationDestination: Equatable {
    case symbol(String)
    case screenerCatalog(symbols: [String])
    case notifications
}

enum NotificationJSON {
    static func readString(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let value = value as? Int {
            return String(value)
        }
        if let value = value as? Int64 {
            return String(value)
        }
        if let value = value as? Double, value.isFinite {
            if value == value.rounded(), let exact = Int64(exactly: value.rounded()) {
                return String(exact)
            }
            return String(value)
        }
        return nil
    }

    static func readBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let text = readString(value)?.lowercased() {
            if text == "true" { return true }
            if text == "false" { return false }
        }
        return nil
    }

    static func readNumber(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let value = number.doubleValue
            return value.isFinite ? value : nil
        }
        if let text = readString(value), let parsed = Double(text), parsed.isFinite {
            return parsed
        }
        return nil
    }

    static func readRecord(_ value: Any?) -> [String: String]? {
        guard let object = value as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, entry) in object {
            if let text = readString(entry) {
                result[key] = text
            }
        }
        return result.isEmpty ? nil : result
    }

    static func normalizeTimestamp(_ value: Any?) -> Int64? {
        guard let numeric = readNumber(value), numeric > 0 else { return nil }
        if numeric < 1_000_000_000_000 {
            return Int64((numeric * 1000).rounded())
        }
        return Int64(numeric.rounded())
    }
}

enum NotificationHistory {
    static func normalize(_ value: Any, index: Int = 0, now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> AppNotification? {
        guard let source = value as? [String: Any] else { return nil }
        let title = NotificationJSON.readString(source["title"])
            ?? NotificationJSON.readString(source["notificationTitle"])
            ?? ""
        let body = NotificationJSON.readString(source["body"])
            ?? NotificationJSON.readString(source["notificationBody"])
            ?? ""
        let sentAt = NotificationJSON.normalizeTimestamp(source["sentAt"])
            ?? NotificationJSON.normalizeTimestamp(source["createdAt"])
            ?? NotificationJSON.normalizeTimestamp(source["updatedAt"])
            ?? now
        let id = NotificationJSON.readString(source["id"])
            ?? NotificationJSON.readString(source["_id"])
            ?? NotificationJSON.readString(source["messageId"])
            ?? [String(sentAt), title, body, String(index)].joined(separator: ":")
        return AppNotification(
            id: id,
            userId: NotificationJSON.readString(source["userId"]),
            notificationType: NotificationJSON.readString(source["notificationType"])
                ?? NotificationJSON.readString(source["type"]),
            title: title,
            body: body,
            sentAt: sentAt,
            delivered: NotificationJSON.readBool(source["delivered"]),
            opened: NotificationJSON.readBool(source["opened"]),
            imageURL: NotificationJSON.readString(source["imageUrl"])
                ?? NotificationJSON.readString(source["image"])
                ?? NotificationJSON.readString(source["thumbnailUrl"]),
            data: NotificationJSON.readRecord(source["data"])
                ?? NotificationJSON.readRecord(source["payload"])
                ?? NotificationJSON.readRecord(source["metadata"])
        )
    }

    static func decodeList(from data: Data) -> [AppNotification] {
        let payload: Any
        do {
            payload = try JSONSerialization.jsonObject(with: data)
        } catch {
            return []
        }
        return decodeList(payload)
    }

    static func decodeList(_ payload: Any) -> [AppNotification] {
        let candidates: [Any]
        if let list = payload as? [Any] {
            candidates = list
        } else if let object = payload as? [String: Any] {
            if let list = object["data"] as? [Any] {
                candidates = list
            } else if let list = object["notifications"] as? [Any] {
                candidates = list
            } else if let list = object["items"] as? [Any] {
                candidates = list
            } else {
                candidates = []
            }
        } else {
            candidates = []
        }
        return sort(
            candidates.enumerated().compactMap { NotificationHistory.normalize($0.element, index: $0.offset) }
        )
    }

    static func mapRemote(
        userInfo: [AnyHashable: Any],
        title: String?,
        body: String?,
        messageID: String?,
        sentTime: Int64? = nil,
        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> AppNotification {
        let data = stringMap(userInfo)
        let resolvedTitle = trimmed(title) ?? ""
        let resolvedBody = trimmed(body) ?? ""
        let sentAt = sentTime
            ?? NotificationJSON.normalizeTimestamp(data["sentAt"])
            ?? now
        let id = trimmed(messageID)
            ?? NotificationJSON.readString(userInfo["gcm.message_id"])
            ?? NotificationJSON.readString(userInfo["google.message_id"])
            ?? [String(sentAt), resolvedTitle, resolvedBody, "0"].joined(separator: ":")
        return AppNotification(
            id: id,
            userId: data["userId"],
            notificationType: data["notificationType"] ?? data["type"],
            title: resolvedTitle,
            body: resolvedBody,
            sentAt: sentAt,
            delivered: true,
            opened: false,
            imageURL: data["imageUrl"],
            data: data.isEmpty ? nil : data
        )
    }

    static func sort(_ notifications: [AppNotification]) -> [AppNotification] {
        var unique: [String: AppNotification] = [:]
        unique.reserveCapacity(notifications.count)
        for item in notifications where !item.id.isEmpty {
            unique[item.id] = item
        }
        return unique.values.sorted { $0.sentAt > $1.sentAt }
    }

    private static func stringMap(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        if let nested = userInfo["data"] {
            if let record = NotificationJSON.readRecord(nested) {
                result.merge(record) { _, new in new }
            } else if let nestedInfo = nested as? [AnyHashable: Any] {
                result.merge(stringMap(nestedInfo)) { _, new in new }
            }
        }
        for (key, value) in userInfo {
            guard let name = key as? String, name != "aps", name != "data" else { continue }
            if let text = NotificationJSON.readString(value) {
                result[name] = text
            }
        }
        if let aps = userInfo["aps"] as? [AnyHashable: Any],
           let alert = aps["alert"] as? [AnyHashable: Any]
        {
            if result["title"] == nil, let title = NotificationJSON.readString(alert["title"]) {
                result["title"] = title
            }
            if result["body"] == nil, let body = NotificationJSON.readString(alert["body"]) {
                result["body"] = body
            }
        }
        return result
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum NotificationParser {
    private static let symbolPattern = try! NSRegularExpression(pattern: #"\b([A-Z][A-Z0-9.-]*)\b"#)
    private static let symbolListKeys = [
        "symbols",
        "symbol_list",
        "symbolList",
        "tickers",
        "ticker_list",
        "tickerList",
        "matched_symbols",
        "matchedSymbols",
        "stocks",
        "items",
    ]

    static func parse(_ notification: AppNotification) -> ParsedNotification {
        let data = notification.data ?? [:]
        let rawType = trimmed(data["type"])
            ?? trimmed(data["notificationType"])
            ?? trimmed(notification.notificationType)
        return ParsedNotification(
            body: notification.body.trimmingCharacters(in: .whitespacesAndNewlines),
            count: Int(trimmed(data["count"]) ?? "0") ?? 0,
            longSymbols: extractSymbols(from: data["longSymbols"] ?? ""),
            prioritySymbols: extractSymbols(from: data["prioritySymbols"] ?? ""),
            rawType: rawType,
            shortSymbols: extractSymbols(from: data["shortSymbols"] ?? ""),
            symbols: unique(extractSymbols(from: data)),
            kind: NotificationKind.resolve(rawType)
        )
    }

    static func destination(for notification: AppNotification) -> NotificationDestination {
        let parsed = parse(notification)
        let screen = trimmed(notification.data?["screen"])
        if let kind = parsed.kind, kind.isTrendOrHighLow, screen == "Markets" {
            return .screenerCatalog(symbols: parsed.symbols)
        }
        if parsed.symbols.count == 1 {
            return .symbol(parsed.symbols[0])
        }
        return .notifications
    }

    static func titleKey(for parsed: ParsedNotification) -> String? {
        switch parsed.kind {
        case .marketTrendUpReversal:
            return "notifications.marketTrendUpReversalTitle"
        case .marketTrendDownReversal:
            return "notifications.marketTrendDownReversalTitle"
        case .intradayHighRetest:
            return "notifications.intradayHighRetestTitle"
        case .intradayLowRetest:
            return "notifications.intradayLowRetestTitle"
        default:
            return nil
        }
    }

    static func displayTitle(for notification: AppNotification) -> String {
        let parsed = parse(notification)
        if let key = titleKey(for: parsed) {
            return L10n.string(key)
        }
        let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.Notifications.toastTitle : title
    }

    static func filter(_ notifications: [AppNotification], type: NotificationKind?) -> [AppNotification] {
        guard let type else { return notifications }
        return notifications.filter { parse($0).kind == type }
    }

    static func filter(_ notifications: [AppNotification], symbols raw: String) -> [AppNotification] {
        let wanted = Set(
            unique(
                raw.split(whereSeparator: { $0.isWhitespace || $0 == "," })
                    .compactMap { normalizeSymbol(String($0)) }
            )
        )
        guard !wanted.isEmpty else { return notifications }
        return notifications.filter { notification in
            let parsed = parse(notification)
            let symbols = parsed.symbols + parsed.longSymbols + parsed.shortSymbols + parsed.prioritySymbols
            return symbols.contains { wanted.contains($0) }
        }
    }

    static func extractSymbols(from data: [String: String]) -> [String] {
        for key in symbolListKeys {
            guard let value = trimmed(data[key]) else { continue }
            let symbols = extractSymbols(from: value)
            if !symbols.isEmpty { return symbols }
        }
        if let symbol = normalizeSymbol(data["symbol"]) {
            return [symbol]
        }
        return []
    }

    static func extractSymbols(from value: String) -> [String] {
        unique(
            parseCandidates(value).compactMap(normalizeSymbol)
        )
    }

    static func normalizeSymbol(_ value: String?) -> String? {
        guard let raw = trimmed(value)?.uppercased() else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = symbolPattern.firstMatch(in: raw, range: range),
              let symbolRange = Range(match.range(at: 1), in: raw)
        else { return nil }
        return String(raw[symbolRange])
    }

    private static func parseCandidates(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            if let data = trimmed.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any]
            {
                return parsed.compactMap { $0 as? String }
            }
        }
        return trimmed.split(whereSeparator: { ",\n;|".contains($0) }).map(String.init)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum NotificationVolume {
    private static let keys = ["volume", "vol", "minVolume", "avgVolume", "volumeThreshold"]

    static func passes(_ notification: AppNotification, threshold: Int) -> Bool {
        guard threshold > 0 else { return true }
        guard let volume = volume(in: notification) else { return true }
        return volume + 0.000_000_1 >= Double(threshold)
    }

    static func volume(in notification: AppNotification) -> Double? {
        guard let data = notification.data else { return nil }
        for key in keys {
            if let value = NotificationJSON.readNumber(data[key]) {
                return value
            }
        }
        return nil
    }

    static func filter(_ notifications: [AppNotification], threshold: Int) -> [AppNotification] {
        notifications.filter { passes($0, threshold: threshold) }
    }
}
