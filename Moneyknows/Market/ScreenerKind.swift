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
        case .momentum, .atr, .priceSlope: return true
        default: return false
        }
    }

    var usesImplicitTradingDate: Bool {
        switch self {
        case .momentum, .atr: return true
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
    case six = "6"
    case eight = "8"
    case ten = "10"
    case twenty = "20"

    var id: String { rawValue }
    var title: String { rawValue }

    static let standard: [ScreenerMinPrice] = [.four, .six, .eight, .ten]
    static let atr: [ScreenerMinPrice] = [.six, .ten, .twenty]
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
    var rsiLow = "50"
    var rsiHigh = "60"
    var adxLow = "20"
    var adxHigh = "30"
    var diGap = "20"
    var returnCount = "100"
    var ibkrType = "MOST_ACTIVE"
    var ibkrFilters = "priceAbove=10,marketCapAbove=1000000000"

    static func defaults(for kind: ScreenerKind, now: Date = Date()) -> ScreenerQuery {
        var query = ScreenerQuery(date: MarketClock.usDateString(from: now))
        switch kind {
        case .yahoo:
            break
        case .momentum:
            query.date = MarketClock.lastTradingDate(from: now)
            query.direction = ScreenerDirection.up.rawValue
            query.timeFrame = ScreenerTimeFrame.five.rawValue
            query.minVolume = ScreenerMinVolume.oneMillion.rawValue
        case .atr:
            query.date = MarketClock.lastTradingDate(from: now)
            query.timeFrame = ScreenerTimeFrame.one.rawValue
            query.barCount = ScreenerBarCount.ten.rawValue
            query.minPrice = ScreenerMinPrice.six.rawValue
            query.minVolume = ScreenerMinVolume.oneMillion.rawValue
        case .stair:
            query.timeFrame = "1Min"
            query.barCount = "0"
        case .priceSlope:
            query.spanMinutes = "30"
            query.minPrice = "6"
        case .rsiAdx:
            query.timeFrame = "1Min"
        case .volume:
            break
        case .ibkr:
            break
        }
        return query
    }

    mutating func pinImplicitTradingDate(for kind: ScreenerKind, now: Date = Date()) {
        guard kind.usesImplicitTradingDate else { return }
        date = MarketClock.lastTradingDate(from: now)
    }
}
