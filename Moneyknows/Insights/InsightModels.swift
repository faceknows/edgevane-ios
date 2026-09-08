import Foundation

enum AILanguage {
    static func code(
        locale: AppLocale?,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch locale {
        case .zh:
            return "zh"
        case .en:
            return "en"
        case nil:
            let first = preferredLanguages.first?.lowercased() ?? ""
            return first.hasPrefix("zh") ? "zh" : "en"
        }
    }
}

enum MarketSentimentKind: String, Equatable {
    case bullish
    case bearish
    case neutral
    case mixed
}

struct MarketSentimentSource: Equatable {
    var title: String?
    var url: String
}

struct MarketSentimentScenario: Equatable {
    var label: String
    var probability: String
    var evidence: [String]
    var confirmationAfterOpen: [String]
    var invalidation: [String]
}

enum MarketSentiment: Equatable {
    case available(Available)
    case unavailable(Unavailable)

    struct Available: Equatable {
        var market: String
        var date: String
        var language: String
        var provider: String?
        var model: String?
        var sentiment: MarketSentimentKind
        var summary: String
        var confidence: String?
        var scenarios: [MarketSentimentScenario]
        var keyDrivers: [String]
        var intradayBias: String?
        var keyLevels: [String]
        var bestTradingStyle: String?
        var stayOutConditions: [String]
        var risks: [String]
        var sources: [MarketSentimentSource]
    }

    struct Unavailable: Equatable {
        var market: String
        var date: String
        var language: String
        var message: String
        var allowedRefetchWindow: String
        var currentTimeET: String
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

struct EconomicCalendarTopEvent: Equatable {
    var title: String
    var time: String?
    var reason: String?
}

struct EconomicCalendarEvent: Equatable, Identifiable {
    var title: String
    var date: String
    var time: String?
    var country: String?
    var currency: String?
    var impact: String?
    var actual: String?
    var forecast: String?
    var previous: String?
    var description: String?
    var mainMarketAffected: String?
    var expectedMarketImpact: String?
    var choppinessRisk: String?
    var traderNote: String?
    var source: String?

    var id: String {
        [date, time ?? "", title].joined(separator: "|")
    }
}

struct EconomicCalendar: Equatable {
    var market: String
    var date: String
    var language: String
    var provider: String?
    var model: String?
    var dayRisk: String?
    var volatilityWindows: [String]
    var biasChangingEvents: [String]
    var cleanerMarketPhase: String?
    var cautionNotes: [String]
    var topEvents: [EconomicCalendarTopEvent]
    var events: [EconomicCalendarEvent]

    var highImpactCount: Int {
        events.filter { $0.impact?.caseInsensitiveCompare("High") == .orderedSame }.count
    }

    var sortedEvents: [EconomicCalendarEvent] {
        events.sorted { left, right in
            let impact = Self.impactRank(left.impact) - Self.impactRank(right.impact)
            if impact != 0 { return impact < 0 }
            return Self.timeRank(left.time) < Self.timeRank(right.time)
        }
    }

    private static func impactRank(_ impact: String?) -> Int {
        switch impact?.lowercased() {
        case "high": return 0
        case "medium": return 1
        case "low": return 2
        default: return 3
        }
    }

    private static func timeRank(_ time: String?) -> Int {
        guard let time, let match = time.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) else {
            return Int.max
        }
        let parts = String(time[match]).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return Int.max
        }
        return hour * 60 + minute
    }
}
