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
    var usesCalendarDays: Bool

    static let empty = ChartModel(
        bars: [],
        style: .candle,
        overlays: [],
        priceLines: [],
        markers: [],
        followLatest: false,
        showVolume: false,
        usesCalendarDays: false
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

/// Highest, lowest, and last close in the visible logical range (partially visible bars count).
enum ChartVisibleExtremes {
    struct Labels: Equatable {
        var highIndex: Int
        var high: Double
        var lowIndex: Int
        var low: Double
        var lastIndex: Int
        var last: Double
    }

    static func labels(
        in bars: [Bar],
        from: Double?,
        to: Double?,
        style: ChartStyle
    ) -> Labels? {
        guard !bars.isEmpty, let from, let to else { return nil }
        let start = max(0, Int(floor(from)))
        let end = min(bars.count - 1, Int(ceil(to)))
        guard start <= end else { return nil }
        var highIndex = start
        var lowIndex = start
        var high = extremeValue(bars[start], style: style, high: true)
        var low = extremeValue(bars[start], style: style, high: false)
        if start < end {
            for index in (start + 1)...end {
                let bar = bars[index]
                let nextHigh = extremeValue(bar, style: style, high: true)
                let nextLow = extremeValue(bar, style: style, high: false)
                if nextHigh > high {
                    high = nextHigh
                    highIndex = index
                }
                if nextLow < low {
                    low = nextLow
                    lowIndex = index
                }
            }
        }
        return Labels(
            highIndex: highIndex,
            high: high,
            lowIndex: lowIndex,
            low: low,
            lastIndex: end,
            last: bars[end].close
        )
    }

    static func fractionDigits(in bars: [Bar]) -> Int {
        var smallest = Double.infinity
        for bar in bars {
            if bar.open.isFinite { smallest = min(smallest, abs(bar.open)) }
            if bar.high.isFinite { smallest = min(smallest, abs(bar.high)) }
            if bar.low.isFinite { smallest = min(smallest, abs(bar.low)) }
            if bar.close.isFinite { smallest = min(smallest, abs(bar.close)) }
        }
        guard smallest.isFinite else { return 2 }
        return OrderSizing.priceFractionDigits(for: smallest)
    }

    static let lastLineEndInset = 2.0

    static func lastLineEndX(plotRight: Double, canvasWidth: Double) -> Double {
        max(plotRight, canvasWidth - lastLineEndInset)
    }

    static func priceText(_ value: Double, precision: Int) -> String {
        guard value.isFinite else { return "" }
        let digits = min(8, max(0, precision))
        return String(format: "%.\(digits)f", value)
    }

    static func extremeCaption(price: String, onLeftHalf: Bool) -> String {
        onLeftHalf ? "--\(price)" : "\(price)--"
    }

    static func isOnLeftHalf(index: Int, from: Double, to: Double) -> Bool {
        Double(index) < (from + to) / 2
    }

    private static func extremeValue(_ bar: Bar, style: ChartStyle, high: Bool) -> Double {
        switch style {
        case .candle:
            return high ? bar.high : bar.low
        case .line:
            return bar.close
        }
    }
}

/// First paint and double-tap both fit every loaded bar into the current plot.
enum ChartViewportReset {
    static func shouldFitOnFirstLayout(didFit: Bool, hasBars: Bool, hasSize: Bool) -> Bool {
        !didFit && hasBars && hasSize
    }

    /// `subscribeSizeChange` only reports later resizes; seed from the view's current bounds.
    static func hasUsablePlotSize(width: CGFloat, height: CGFloat) -> Bool {
        width > 0 && height > 0
    }
}

enum ChartLibraryOptions {
    /// LightweightCharts iOS stores each formatter closure under a unique name and never removes it.
    static func attachFormatters(alreadyInstalled: Bool) -> Bool {
        !alreadyInstalled
    }
}

/// Details stacks several `ChartSurface`s. Vertical pans belong to the page; the chart keeps left/right and pinch.
enum ChartTouchScrolling {
    static let verticalTouchDrag = false
    static let horizontalTouchDrag = true
    static let lockDistance: Double = 8

    static func hasLockedDirection(translationX: Double, translationY: Double) -> Bool {
        hypot(translationX, translationY) >= lockDistance
    }

    /// Horizontal wins only when X is strictly larger; ties and vertical go to the page.
    static func chartOwnsPan(translationX: Double, translationY: Double) -> Bool {
        abs(translationX) > abs(translationY)
    }
}

/// Overlay volume in a bottom strip of `ChartSurface.height`. Callers pass `volumeHeight` to size that strip; otherwise a default fraction of the total height is used.
enum ChartVolumeLayout {
    static let priceTop: Double = 0.06
    static let priceBottomWithoutVolume: Double = 0.08
    static let volumeBottom: Double = 0.02
    static let gap: Double = 0.06
    static let defaultVolumeFraction: Double = 0.22
    private static let maxVolumeFraction: Double = 0.5

    static func defaultVolumeHeight(in totalHeight: CGFloat) -> CGFloat {
        max(0, totalHeight) * CGFloat(defaultVolumeFraction)
    }

    static func priceMargins(volumeHeight: CGFloat?, totalHeight: CGFloat) -> (top: Double, bottom: Double) {
        guard let volumeHeight else {
            return (priceTop, priceBottomWithoutVolume)
        }
        return (priceTop, volumeFraction(volumeHeight, totalHeight: totalHeight) + gap + volumeBottom)
    }

    static func volumeMargins(volumeHeight: CGFloat, totalHeight: CGFloat) -> (top: Double, bottom: Double) {
        (1 - volumeFraction(volumeHeight, totalHeight: totalHeight) - volumeBottom, volumeBottom)
    }

    private static func volumeFraction(_ volumeHeight: CGFloat, totalHeight: CGFloat) -> Double {
        min(maxVolumeFraction, max(0, Double(volumeHeight / max(totalHeight, 1))))
    }
}
