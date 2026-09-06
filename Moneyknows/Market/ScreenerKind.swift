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
        self == .priceSlope
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
            query.timeFrame = "5Min"
        case .atr:
            query.timeFrame = "1Min"
            query.barCount = "10"
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
}
