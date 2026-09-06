import Foundation

struct Bar: Equatable {
    var time: Date
    var open: Double
    var high: Double
    var low: Double
    var close: Double
    var volume: Double
}

enum ChartStyle: String, Equatable, CaseIterable {
    case candle
    case line
}

enum MinuteInterval: Int, CaseIterable, Identifiable {
    case one = 1
    case three = 3
    case five = 5

    var id: Int { rawValue }
    var minutes: Int { rawValue }

    var chromeTitle: String {
        switch self {
        case .one: return L10n.Chart.oneMinute
        case .three: return L10n.Chart.threeMinutes
        case .five: return L10n.Chart.fiveMinutes
        }
    }
}

enum SecondInterval: Int, CaseIterable, Identifiable {
    case one = 1
    case five = 5
    case ten = 10
    case thirty = 30

    var id: Int { rawValue }
    var seconds: Int { rawValue }

    var chromeTitle: String {
        switch self {
        case .one: return L10n.Chart.oneSecond
        case .five: return L10n.Chart.fiveSeconds
        case .ten: return L10n.Chart.tenSeconds
        case .thirty: return L10n.Chart.thirtySeconds
        }
    }
}

struct OverlayLine: Equatable, Identifiable {
    var id: String
    var points: [OverlayPoint]
    var colorToken: ChartColorToken
    var width: Double
}

struct OverlayPoint: Equatable {
    var time: Date
    var value: Double
}

enum ChartColorToken: String, Equatable {
    case up
    case down
    case vwap
    case prevClose
    case sessionOpen
    case buy
    case sell
    case other
}

enum ChartMarkerKind: String, Equatable {
    case buy
    case sell
    case other
}

enum ChartMarkerPosition: String, Equatable {
    case aboveBar
    case belowBar
    case auto
}

struct ChartMarker: Equatable, Identifiable {
    var id: String
    var time: Date
    var price: Double
    var kind: ChartMarkerKind
    var title: String?
    var position: ChartMarkerPosition
}

struct ChartRGBA: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

struct ChartColors: Equatable {
    var background: ChartRGBA
    var text: ChartRGBA
    var up: ChartRGBA
    var down: ChartRGBA
    var vwap: ChartRGBA
    var prevClose: ChartRGBA
    var sessionOpen: ChartRGBA
    var buy: ChartRGBA
    var sell: ChartRGBA
    var other: ChartRGBA
    var volume: ChartRGBA
    var grid: ChartRGBA

    func rgba(for token: ChartColorToken) -> ChartRGBA {
        switch token {
        case .up: return up
        case .down: return down
        case .vwap: return vwap
        case .prevClose: return prevClose
        case .sessionOpen: return sessionOpen
        case .buy: return buy
        case .sell: return sell
        case .other: return other
        }
    }
}

struct ChartModel: Equatable {
    struct PriceLine: Equatable, Identifiable {
        var id: String
        var price: Double
        var title: String
        var dashed: Bool
        var colorToken: ChartColorToken
    }

    var bars: [Bar]
    var style: ChartStyle
    var overlays: [OverlayLine]
    var priceLines: [PriceLine]
    var markers: [ChartMarker]
    var followLatest: Bool
    var showVolume: Bool

    static let empty = ChartModel(
        bars: [],
        style: .candle,
        overlays: [],
        priceLines: [],
        markers: [],
        followLatest: false,
        showVolume: false
    )
}

enum ChartEvent {
    case picked(Bar)
    case pickedMarker(id: String)
    case reachedOldest
    case loadFailed
}

enum ChartTimeScalePaging {
    struct State: Equatable {
        var reachedOldest = false
        var ignoringFitContent = false
        var fitContentFrom: Double?
    }

    static func beginIgnoringFitContent(_ state: inout State) {
        state.ignoringFitContent = true
    }

    static func reset(_ state: inout State) {
        state = State()
    }

    /// Lock the leftmost bar only after a real `.reachedOldest`. Doing it earlier
    /// (`fixLeftEdge` from the first paint) stops logical `from` from decreasing,
    /// so history paging never fires.
    static func locksLeftEdge(_ state: State) -> Bool {
        state.reachedOldest
    }

    /// `fitContent()` pads about half a bar, so the first logical `from` is often negative.
    /// Swallow that callback; only emit after the user pans further left.
    static func handleLogicalRange(from: Double?, hasBars: Bool, state: inout State) -> Bool {
        guard hasBars, let from else { return false }
        if state.ignoringFitContent {
            if from < 0 {
                state.ignoringFitContent = false
                state.fitContentFrom = from
            }
            return false
        }
        guard from < 0, !state.reachedOldest else { return false }
        if let baseline = state.fitContentFrom, from >= baseline {
            return false
        }
        state.reachedOldest = true
        return true
    }
}

enum ChartLibraryOptions {
    /// LightweightCharts iOS stores each formatter closure under a unique name and never removes it.
    static func attachFormatters(alreadyInstalled: Bool) -> Bool {
        !alreadyInstalled
    }
}
