import Foundation

enum ScreenerKind: String, CaseIterable, Identifiable {
    case yahoo
    case momentum
    case atr
    case priceSlope
    case stair
    case rsiAdx
    case volume
    case ibkr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yahoo: return L10n.Market.yahoo
        case .momentum: return L10n.Market.momentum
        case .atr: return L10n.Market.atr
        case .priceSlope: return L10n.Market.priceSlope
        case .stair: return L10n.Market.stair
        case .rsiAdx: return L10n.Market.rsiAdx
        case .volume: return L10n.Market.volume
        case .ibkr: return L10n.Market.ibkr
        }
    }

    var showsFilters: Bool {
        switch self {
        case .momentum, .atr, .priceSlope, .stair, .rsiAdx, .volume, .ibkr: return true
        default: return false
        }
    }

    var usesImplicitTradingDate: Bool {
        switch self {
        case .momentum, .atr, .stair: return true
        default: return false
        }
    }
}

enum ScreenerDirection: String, CaseIterable, Identifiable {
    case up
    case down

    var id: String { rawValue }

    var title: String {
        switch self {
        case .up: return L10n.Market.up
        case .down: return L10n.Market.down
        }
    }
}

enum ScreenerTimeFrame: String, CaseIterable, Identifiable {
    case one = "1Min"
    case three = "3Min"
    case five = "5Min"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one: return L10n.Chart.oneMinute
        case .three: return L10n.Chart.threeMinutes
        case .five: return L10n.Chart.fiveMinutes
        }
    }
}

enum ScreenerMinVolume: String, CaseIterable, Identifiable {
    case oneMillion = "1M"
    case twoMillion = "2M"
    case fiveMillion = "5M"
    case tenMillion = "10M"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum ScreenerMinPrice: String, CaseIterable, Identifiable {
    case four = "4"
    case five = "5"
    case six = "6"
    case eight = "8"
    case ten = "10"
    case twenty = "20"

    var id: String { rawValue }
    var title: String { rawValue }

    static let standard: [ScreenerMinPrice] = [.four, .six, .eight, .ten]
    static let atr: [ScreenerMinPrice] = [.six, .ten, .twenty]
    static let ibkr: [ScreenerMinPrice] = [.five, .ten, .twenty]
}

enum ScreenerBarCount: String, CaseIterable, Identifiable {
    case zero = "0"
    case five = "5"
    case ten = "10"
    case twenty = "20"
    case thirty = "30"

    var id: String { rawValue }
    var title: String { rawValue }

    static let atr: [ScreenerBarCount] = [.five, .ten, .twenty, .thirty]
    static let stair: [ScreenerBarCount] = [.zero, .five, .ten, .twenty, .thirty]
}

enum ScreenerSpanMinutes: String, CaseIterable, Identifiable {
    case fifteen = "15"
    case thirty = "30"
    case sixty = "60"
    case ninety = "90"
    case oneTwenty = "120"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum ScreenerRSIRange: String, CaseIterable, Identifiable {
    case lt40
    case from40to50 = "40to50"
    case from50to60 = "50to60"
    case from60to70 = "60to70"
    case gt70

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lt40: return "<=40"
        case .from40to50: return "40-50"
        case .from50to60: return "50-60"
        case .from60to70: return "60-70"
        case .gt70: return ">=70"
        }
    }

    var low: String {
        switch self {
        case .lt40: return ""
        case .from40to50: return "40"
        case .from50to60: return "50"
        case .from60to70: return "60"
        case .gt70: return "70"
        }
    }

    var high: String {
        switch self {
        case .lt40: return "40"
        case .from40to50: return "50"
        case .from50to60: return "60"
        case .from60to70: return "70"
        case .gt70: return ""
        }
    }
}

enum ScreenerADXRange: String, CaseIterable, Identifiable {
    case lt20
    case from20to30 = "20to30"
    case from30to40 = "30to40"
    case from40to50 = "40to50"
    case gt50

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lt20: return "<=20"
        case .from20to30: return "20-30"
        case .from30to40: return "30-40"
        case .from40to50: return "40-50"
        case .gt50: return ">=50"
        }
    }

    var low: String {
        switch self {
        case .lt20: return ""
        case .from20to30: return "20"
        case .from30to40: return "30"
        case .from40to50: return "40"
        case .gt50: return "50"
        }
    }

    var high: String {
        switch self {
        case .lt20: return "20"
        case .from20to30: return "30"
        case .from30to40: return "40"
        case .from40to50: return "50"
        case .gt50: return ""
        }
    }
}

enum ScreenerDIGap: String, CaseIterable, Identifiable {
    case ten = "10"
    case twenty = "20"
    case thirty = "30"
    case forty = "40"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum ScreenerIBKRType: String, CaseIterable, Identifiable {
    case mostActive = "MOST_ACTIVE"
    case hotByVolume = "HOT_BY_VOLUME"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostActive: return L10n.Market.mostActive
        case .hotByVolume: return L10n.Market.hotVolume
        }
    }
}

enum ScreenerMinMarketCap: String, CaseIterable, Identifiable {
    case fiveHundredMillion = "500000000"
    case oneBillion = "1000000000"
    case twoBillion = "2000000000"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHundredMillion: return "500M"
        case .oneBillion: return "1B"
        case .twoBillion: return "2B"
        }
    }
}

struct ScreenerQuery: Equatable {
    var market = "us"
    var date: String
    var scrIds = "most_actives"
    var count = "50"
    var direction = "up"
    var timeFrame = "5Min"
    var minVolume = "1M"
    var minPrice = "6"
    var barCount = "10"
    var spanMinutes = "30"
    var endTime = ""
    var time = ""
    var rsiRange = ScreenerRSIRange.from50to60.rawValue
    var adxRange = ScreenerADXRange.from20to30.rawValue
    var diGap = ScreenerDIGap.twenty.rawValue
    var returnCount = "50"
    var ibkrType = ScreenerIBKRType.mostActive.rawValue
    var ibkrMarketCap = ScreenerMinMarketCap.oneBillion.rawValue

    var ibkrFilters: String {
        var parts: [String] = []
        if !minPrice.isEmpty {
            parts.append("priceAbove=\(minPrice)")
        }
        if !ibkrMarketCap.isEmpty {
            parts.append("marketCapAbove=\(ibkrMarketCap)")
        }
        return parts.joined(separator: ",")
    }

    static func defaults(for kind: ScreenerKind, now: Date = Date()) -> ScreenerQuery {
        var query = ScreenerQuery(date: MarketClock.usDateString(from: now))
        switch kind {
        case .yahoo:
            break
        case .momentum:
            query.date = MarketClock.lastTradingDate(from: now)
            query.direction = ScreenerDirection.up.rawValue
            query.timeFrame = ScreenerTimeFrame.five.rawValue
        case .atr:
            query.date = MarketClock.lastTradingDate(from: now)
            query.timeFrame = ScreenerTimeFrame.one.rawValue
            query.barCount = ScreenerBarCount.ten.rawValue
            query.minPrice = ScreenerMinPrice.six.rawValue
        case .stair:
            query.date = MarketClock.lastTradingDate(from: now)
            query.timeFrame = ScreenerTimeFrame.one.rawValue
            query.barCount = ScreenerBarCount.zero.rawValue
            query.minVolume = ScreenerMinVolume.fiveMillion.rawValue
        case .priceSlope:
            query.spanMinutes = ScreenerSpanMinutes.thirty.rawValue
            query.minPrice = ScreenerMinPrice.six.rawValue
            query.endTime = ""
        case .rsiAdx:
            query.timeFrame = ScreenerTimeFrame.one.rawValue
            query.rsiRange = ScreenerRSIRange.from50to60.rawValue
            query.adxRange = ScreenerADXRange.from20to30.rawValue
            query.diGap = ScreenerDIGap.twenty.rawValue
            query.direction = ScreenerDirection.up.rawValue
        case .volume:
            query.minVolume = ScreenerMinVolume.fiveMillion.rawValue
            query.returnCount = "50"
        case .ibkr:
            query.minPrice = ScreenerMinPrice.ten.rawValue
            query.ibkrType = ScreenerIBKRType.mostActive.rawValue
            query.ibkrMarketCap = ScreenerMinMarketCap.oneBillion.rawValue
        }
        return query
    }

    mutating func pinHiddenSession(for kind: ScreenerKind, now: Date = Date()) {
        switch kind {
        case .momentum, .atr, .stair:
            date = MarketClock.lastTradingDate(from: now)
        case .priceSlope:
            date = MarketClock.usDateString(from: now)
            endTime = ""
        default:
            break
        }
    }
}
