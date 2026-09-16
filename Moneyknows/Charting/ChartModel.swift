import Foundation
import UIKit

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
    var barDuration: TimeInterval { TimeInterval(minutes * 60) }

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
    var showVolume: Bool
    var usesCalendarDays: Bool
    /// Symbol + session + date. Empty only in tests that feed bars directly.
    var seriesID: String = ""

    static let empty = ChartModel(
        bars: [],
        style: .candle,
        overlays: [],
        priceLines: [],
        markers: [],
        showVolume: false,
        usesCalendarDays: false
    )
}

enum ChartSeriesIdentity {
    static func id(symbol: String, session: String, date: String = "") -> String {
        let code = SymbolCode.normalize(symbol)
        guard !code.isEmpty else { return "" }
        if date.isEmpty { return "\(code)|\(session)" }
        return "\(code)|\(session)|\(date)"
    }
}

enum ChartEvent {
    case picked(Bar)
    case pickedMarker(id: String)
    case reachedOldest
    case loadFailed
    case visibleTimeRange(ChartVisibleTimeRange)
}

/// Wall-clock window currently shown on a minute chart. 1/3/5 aggregation
/// must keep this window; logical bar indices are not comparable across intervals.
struct ChartVisibleTimeRange: Equatable {
    var from: Date
    var to: Date

    static let syncTolerance: TimeInterval = 1

    func isApproximatelyEqual(
        to other: ChartVisibleTimeRange,
        tolerance: TimeInterval = syncTolerance
    ) -> Bool {
        abs(from.timeIntervalSince(other.from)) < tolerance
            && abs(to.timeIntervalSince(other.to)) < tolerance
    }
}

enum ChartVisibleTimeRangeSync {
    static let restoreSettleInterval: TimeInterval = 0.2

    static func intersects(_ range: ChartVisibleTimeRange, bars: [Bar]) -> Bool {
        guard let first = bars.first?.time, let last = bars.last?.time else { return false }
        return range.from <= last && range.to >= first
    }

    /// Re-apply the same wall-clock window after 1/3/5 aggregation: logical
    /// indices from the previous interval would squeeze the new bars.
    static func shouldRestore(
        current: ChartVisibleTimeRange?,
        target: ChartVisibleTimeRange,
        dataChanged: Bool
    ) -> Bool {
        if dataChanged { return true }
        if let current, current.isApproximatelyEqual(to: target) { return false }
        return true
    }

    static func shouldPublish(applied: ChartVisibleTimeRange?, observed: ChartVisibleTimeRange) -> Bool {
        if let applied, applied.isApproximatelyEqual(to: observed) { return false }
        return true
    }

    /// Visible-time notifies first but clips empty future to the last bar. Publish
    /// from logical-range after clamp, mapped back through bar times.
    static let visibleTimeNotifiesBeforeLogicalRange = true

    static let shouldPublishLibraryVisibleTime = false

    /// Inverse of `logicalIndex`: indices past `lastIndex` keep `duration` so empty
    /// future survives, unlike the library visible-time callback.
    static func time(
        atLogical index: Double,
        in bars: [Bar],
        duration: TimeInterval
    ) -> Date? {
        guard duration > 0, let first = bars.first?.time else { return nil }
        if index <= 0 {
            return first.addingTimeInterval(index * duration)
        }
        let lastIdx = bars.count - 1
        if index >= Double(lastIdx) {
            return bars[lastIdx].time.addingTimeInterval((index - Double(lastIdx)) * duration)
        }
        let lo = Int(floor(index))
        let hi = lo + 1
        let span = bars[hi].time.timeIntervalSince(bars[lo].time)
        return bars[lo].time.addingTimeInterval(span * (index - Double(lo)))
    }

    static func visibleTimeRange(
        from: Double,
        to: Double,
        in bars: [Bar],
        duration: TimeInterval
    ) -> ChartVisibleTimeRange? {
        guard let fromTime = time(atLogical: from, in: bars, duration: duration),
              let toTime = time(atLogical: to, in: bars, duration: duration),
              fromTime <= toTime
        else { return nil }
        return ChartVisibleTimeRange(from: fromTime, to: toTime)
    }

    /// Logical from/to on `bars` for the same wall-clock window. `barDuration` is
    /// the current 1/3/5 period, not inferred from bar gaps. `to` may extend past
    /// the last bar so a shorter series keeps the same end as the source.
    static func logicalRange(
        for range: ChartVisibleTimeRange,
        in bars: [Bar],
        barDuration: TimeInterval
    ) -> (from: Double, to: Double)? {
        guard barDuration > 0, !bars.isEmpty, intersects(range, bars: bars) else { return nil }
        let from = logicalIndex(of: range.from, in: bars, duration: barDuration)
        let to = logicalIndex(of: range.to, in: bars, duration: barDuration)
        guard from <= to else { return nil }
        return (from, to)
    }

    /// Exclusive `to` past `lastIndex` is empty future. The library's zero-offset
    /// right edge is `barCount - 1`, not `barCount`.
    static func extendsPastLastBar(to: Double, barCount: Int) -> Bool {
        barCount > 0 && to > lastIndex(barCount: barCount) + 0.01
    }

    static func lastIndex(barCount: Int) -> Double {
        Double(max(barCount - 1, 0))
    }

    /// Library offset is `to - lastIndex`, not `to - barCount`.
    static func rightOffset(to: Double, lastIndex: Double) -> Double {
        max(0, to - lastIndex)
    }

    static func customMaxLogicalTo(to: Double, barCount: Int) -> Double? {
        extendsPastLastBar(to: to, barCount: barCount) ? to : nil
    }

    /// Slide the window back so `to` does not pass the restored bound. `nil` if already inside.
    static func clampedLogicalRange(
        from: Double,
        to: Double,
        maxTo: Double
    ) -> (from: Double, to: Double)? {
        guard to > maxTo + 0.01 else { return nil }
        return (from - (to - maxTo), maxTo)
    }

    static func logicalIndex(of time: Date, in bars: [Bar], duration: TimeInterval) -> Double {
        guard let first = bars.first?.time else { return 0 }
        if time <= first {
            return duration > 0 ? time.timeIntervalSince(first) / duration : 0
        }
        for index in 1..<bars.count {
            let barTime = bars[index].time
            if time <= barTime {
                let span = barTime.timeIntervalSince(bars[index - 1].time)
                if span <= 0 { return Double(index) }
                let fraction = time.timeIntervalSince(bars[index - 1].time) / span
                return Double(index - 1) + min(1, max(0, fraction))
            }
        }
        guard let last = bars.last?.time, duration > 0 else { return Double(max(bars.count - 1, 0)) }
        return Double(bars.count - 1) + time.timeIntervalSince(last) / duration
    }
}

enum ChartTimeScalePaging {
    struct State: Equatable {
        var reachedOldest = false
        var ignoringFitContent = false
        var fitContentFrom: Double?
    }

    /// User-driven source charts pin the right edge with the library lock. Followers
    /// stay unlocked. A restored window past the last bar cannot use `fixRightEdge`
    /// (v4 clamps `rightOffset` to 0); keep the lock off and clamp `to` ourselves.
    static func fixesRightEdge(
        allowsTimeScaleInteraction: Bool,
        hasCustomRightBound: Bool = false,
        restoringSyncedRange: Bool = false
    ) -> Bool {
        allowsTimeScaleInteraction && !hasCustomRightBound && !restoringSyncedRange
    }

    /// Lightweight Charts 4.0: `fixRightEdge` forces `rightOffset` to 0.
    static func libraryRightOffset(fixRightEdge: Bool, rightOffset: Double) -> Double {
        fixRightEdge ? min(rightOffset, 0) : rightOffset
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

    /// Incremental bars keep the current window. Fit again on first paint, when
    /// `seriesID` changes, or when `next` is not a continuation of `previous`.
    static func shouldRefitAfterDataChange(
        didFit: Bool,
        previous: [Bar],
        next: [Bar],
        previousSeriesID: String = "",
        nextSeriesID: String = ""
    ) -> Bool {
        guard !next.isEmpty else { return false }
        if previous.isEmpty { return true }
        guard didFit else { return true }
        if seriesReplaced(previousSeriesID: previousSeriesID, nextSeriesID: nextSeriesID) {
            return true
        }
        return !isIncrementalDataChange(previous: previous, next: next)
    }

    static func seriesReplaced(previousSeriesID: String, nextSeriesID: String) -> Bool {
        !previousSeriesID.isEmpty && !nextSeriesID.isEmpty && previousSeriesID != nextSeriesID
    }

    /// Same timestamps with at most the last two bars edited still count as live updates.
    /// A single forming bar is the live tail; symbol switches use `seriesID`.
    private static let maxInPlaceBarEdits = 2

    static func isIncrementalDataChange(previous: [Bar], next: [Bar]) -> Bool {
        let previousTimes = previous.map(\.time)
        let nextTimes = next.map(\.time)
        if previousTimes == nextTimes {
            return lockedPrefixMatches(previous, next)
        }
        if next.count > previous.count {
            if Array(nextTimes.prefix(previous.count)) == previousTimes {
                return lockedPrefixMatches(previous, Array(next.prefix(previous.count)))
            }
            if Array(nextTimes.suffix(previous.count)) == previousTimes {
                return lockedPrefixMatches(previous, Array(next.suffix(previous.count)))
            }
        }
        if next.count < previous.count {
            if Array(previousTimes.prefix(next.count)) == nextTimes {
                return lockedPrefixMatches(Array(previous.prefix(next.count)), next)
            }
            if Array(previousTimes.suffix(next.count)) == nextTimes {
                return lockedPrefixMatches(Array(previous.suffix(next.count)), next)
            }
        }
        guard let shift = ChartLiveViewport.indexShift(from: previous, to: next) else {
            return false
        }
        return alignedOverlapMatches(previous: previous, next: next, shift: Int(shift.rounded()))
    }

    /// Shared bars must be the same series. Last two may change in place (live last bar).
    /// One forming bar is the live tail; a one-bar symbol switch is `seriesID`.
    private static func lockedCount(_ barCount: Int) -> Int {
        guard barCount > 1 else { return 0 }
        return max(1, barCount - maxInPlaceBarEdits)
    }

    private static func lockedPrefixMatches(_ previous: [Bar], _ next: [Bar]) -> Bool {
        let locked = lockedCount(previous.count)
        if locked == 0 { return true }
        return zip(previous.prefix(locked), next.prefix(locked)).allSatisfy { $0 == $1 }
    }

    private static func alignedOverlapMatches(previous: [Bar], next: [Bar], shift: Int) -> Bool {
        let previousStart = max(0, -shift)
        let nextStart = max(0, shift)
        let count = min(previous.count - previousStart, next.count - nextStart)
        guard count > 0 else { return false }
        let locked = lockedCount(count)
        for index in 0..<count {
            let previousBar = previous[previousStart + index]
            let nextBar = next[nextStart + index]
            if previousBar.time != nextBar.time { return false }
            if index < locked, previousBar != nextBar { return false }
        }
        return true
    }

    /// `subscribeSizeChange` only reports later resizes; seed from the view's current bounds.
    static func hasUsablePlotSize(width: CGFloat, height: CGFloat) -> Bool {
        width > 0 && height > 0
    }
}

/// Crosshair readout follows the live bar; a new `seriesID` drops it even when times overlap.
enum ChartPickedSelection {
    static func updated(picked: Bar?, previousSeriesID: String, next: ChartModel) -> Bar? {
        guard let picked else { return nil }
        if ChartViewportReset.seriesReplaced(
            previousSeriesID: previousSeriesID,
            nextSeriesID: next.seriesID
        ) {
            return nil
        }
        return next.bars.first { $0.time == picked.time }
    }
}

/// Keep the user's zoom/pan when bars append, update, or drop from a ring buffer.
enum ChartLiveViewport {
    /// Last bar is at least partly visible. A restored window that already extends
    /// several bars into empty future is not "following live."
    static func shouldFollowNewBar(
        to: Double,
        barCount: Int,
        hasCustomRightBound: Bool
    ) -> Bool {
        guard !hasCustomRightBound, barCount > 0 else { return false }
        let last = ChartVisibleTimeRangeSync.lastIndex(barCount: barCount)
        return to >= last - 0.01 && to < last + 1
    }

    /// Followers must remap the source wall-clock window when their bars change.
    /// `restoreLinkedTimeRangeIfNeeded` returns true even when it does not setRange.
    static func shouldForceLinkedRestore(
        isFollower: Bool,
        timesChanged: Bool,
        durationChanged: Bool,
        seriesReplaced: Bool
    ) -> Bool {
        durationChanged || seriesReplaced || (isFollower && timesChanged)
    }

    static func timesChanged(previous: [Bar], next: [Bar]) -> Bool {
        previous.map(\.time) != next.map(\.time)
    }

    /// How many indices `previous[0]` moved in `next`. Negative when the ring dropped oldest bars.
    static func indexShift(from previous: [Bar], to next: [Bar]) -> Double? {
        guard let previousFirst = previous.first?.time else { return nil }
        if let index = next.firstIndex(where: { $0.time == previousFirst }) {
            return Double(index)
        }
        guard let nextFirst = next.first?.time,
              let index = previous.firstIndex(where: { $0.time == nextFirst })
        else { return nil }
        return Double(-index)
    }

    static func logicalRangeAfterDataChange(
        from: Double,
        to: Double,
        previous: [Bar],
        next: [Bar],
        previousDuration: TimeInterval?,
        nextDuration: TimeInterval?,
        hasCustomRightBound: Bool
    ) -> (from: Double, to: Double)? {
        guard !previous.isEmpty, !next.isEmpty else { return nil }
        let durationChanged = previousDuration != nextDuration
            && (previousDuration ?? 0) > 0
            && (nextDuration ?? 0) > 0
        if durationChanged,
           let previousDuration,
           let nextDuration,
           let window = ChartVisibleTimeRangeSync.visibleTimeRange(
            from: from,
            to: to,
            in: previous,
            duration: previousDuration
           ),
           var logical = ChartVisibleTimeRangeSync.logicalRange(
            for: window,
            in: next,
            barDuration: nextDuration
           ) {
            if shouldFollowNewBar(to: to, barCount: previous.count, hasCustomRightBound: hasCustomRightBound) {
                let last = ChartVisibleTimeRangeSync.lastIndex(barCount: next.count)
                if logical.to < last - 0.01 {
                    let width = logical.to - logical.from
                    logical = (last - width, last)
                }
            }
            return logical
        }
        if shouldFollowNewBar(to: to, barCount: previous.count, hasCustomRightBound: hasCustomRightBound) {
            let width = to - from
            guard width > 0 else { return nil }
            let oldLast = ChartVisibleTimeRangeSync.lastIndex(barCount: previous.count)
            let newLast = ChartVisibleTimeRangeSync.lastIndex(barCount: next.count)
            let newTo = newLast + (to - oldLast)
            return (newTo - width, newTo)
        }
        if let shift = indexShift(from: previous, to: next) {
            return (from + shift, to + shift)
        }
        return nil
    }
}

enum ChartLibraryOptions {
    /// LightweightCharts iOS stores each formatter closure under a unique name and never removes it.
    static func attachFormatters(alreadyInstalled: Bool) -> Bool {
        !alreadyInstalled
    }
}

/// Details stacks several `ChartSurface`s. Vertical pans belong to the page; the chart keeps left/right and pinch
/// unless time-scale interaction is off (NASDAQ follower).
enum ChartTouchScrolling {
    static let verticalTouchDrag = false
    static let horizontalTouchDrag = true
    static let lockDistance: Double = 8

    static func hasLockedDirection(translationX: Double, translationY: Double) -> Bool {
        hypot(translationX, translationY) >= lockDistance
    }

    static func horzTouchDrag(allowsTimeScaleInteraction: Bool) -> Bool {
        allowsTimeScaleInteraction && horizontalTouchDrag
    }

    static func pinch(allowsTimeScaleInteraction: Bool) -> Bool {
        allowsTimeScaleInteraction
    }

    /// Horizontal wins only when X is strictly larger; ties and vertical go to the page.
    static func chartOwnsPan(
        translationX: Double,
        translationY: Double,
        allowsTimeScaleInteraction: Bool = true
    ) -> Bool {
        allowsTimeScaleInteraction && abs(translationX) > abs(translationY)
    }

    /// Only the enclosing page scroll. WKWebView's own pan is also a `UIScrollView` pan and must not join.
    static func isPageScrollPan(
        _ other: UIGestureRecognizer,
        enclosingScroll: UIScrollView?
    ) -> Bool {
        guard let enclosingScroll else { return false }
        return other === enclosingScroll.panGestureRecognizer
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
