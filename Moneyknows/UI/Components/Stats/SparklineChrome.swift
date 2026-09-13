import CoreGraphics
import Foundation

enum SparklineTimeKind: Equatable {
    case minute
    case second

    var tickKind: ChartEasternTime.TickKind {
        switch self {
        case .minute: return .time
        case .second: return .timeWithSeconds
        }
    }
}

struct SparklinePrepared: Equatable {
    var usesCandles: Bool
    var values: [Double]
    var times: [Date]
    var overlay: [Double]
    var bars: [Bar]
    var timeKind: SparklineTimeKind
    var domainLow: Double
    var domainHigh: Double
    var precision: Int
    var extremes: ChartVisibleExtremes.Labels?
    var vwapCaption: String?
}

enum SparklineChrome {
    static let topInset: CGFloat = 14
    static let leadingInset: CGFloat = 6
    static let trailingInset: CGFloat = 50
    static let bottomInset: CGFloat = 16
    static let xTickCount = 6
    static let yTickCount = 4
    static let xLabelGap: CGFloat = 8
    static let minuteLabelWidth: CGFloat = 36
    static let secondLabelWidth: CGFloat = 52

    struct Tick: Equatable {
        var position: CGFloat
        var text: String
    }

    struct Mark: Equatable {
        var point: CGPoint
        var text: String
        var onLeftHalf: Bool
    }

    struct Last: Equatable {
        var x: CGFloat
        var y: CGFloat
        var text: String
    }

    struct Layout: Equatable {
        var plot: CGRect
        var domainLow: Double
        var domainHigh: Double
        var xTicks: [Tick]
        var yTicks: [Tick]
        var high: Mark?
        var low: Mark?
        var last: Last?
        var lastEndX: CGFloat
        var vwapCaption: String?
    }

    static func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: leadingInset,
            y: topInset,
            width: max(0, size.width - leadingInset - trailingInset),
            height: max(0, size.height - topInset - bottomInset)
        )
    }

    static func prepare(_ plot: SparklinePlot) -> SparklinePrepared? {
        let aligned = plot.aligned()
        guard !aligned.isEmpty else { return nil }
        switch aligned {
        case .line(let values, let times, let overlay, let timeKind):
            guard let domain = SparklineGeometry.domain(values: values, overlay: overlay) else { return nil }
            let precision = fractionDigits(values: values, overlay: overlay)
            return SparklinePrepared(
                usesCandles: false,
                values: values,
                times: times,
                overlay: overlay,
                bars: [],
                timeKind: timeKind,
                domainLow: domain.low,
                domainHigh: domain.high,
                precision: precision,
                extremes: lineExtremes(values: values),
                vwapCaption: nil
            )
        case .candles(let bars, let vwap, let timeKind):
            guard let domain = SparklineGeometry.barDomain(bars: bars, overlay: vwap) else { return nil }
            let precision = ChartVisibleExtremes.fractionDigits(in: bars)
            return SparklinePrepared(
                usesCandles: true,
                values: [],
                times: bars.map(\.time),
                overlay: vwap,
                bars: bars,
                timeKind: timeKind,
                domainLow: domain.low,
                domainHigh: domain.high,
                precision: precision,
                extremes: visibleExtremes(bars, style: .candle),
                vwapCaption: vwapCaption(vwap: vwap, precision: precision)
            )
        }
    }

    static func layout(for plot: SparklinePlot, in size: CGSize) -> Layout? {
        guard let prepared = prepare(plot) else { return nil }
        return layout(for: prepared, in: size)
    }

    static func layout(for prepared: SparklinePrepared, in size: CGSize) -> Layout? {
        guard size.width > 0, size.height > 0 else { return nil }
        let plotArea = plotRect(in: size)
        guard plotArea.width > 0, plotArea.height > 0 else { return nil }
        let count = prepared.usesCandles ? prepared.bars.count : prepared.values.count
        guard count > 0 else { return nil }
        func x(for index: Int) -> CGFloat {
            prepared.usesCandles
                ? SparklineGeometry.candleX(index: index, count: count, in: plotArea)
                : SparklineGeometry.lineX(index: index, count: count, in: plotArea)
        }
        func priceY(_ price: Double) -> CGFloat {
            SparklineGeometry.y(price, low: prepared.domainLow, high: prepared.domainHigh, in: plotArea)
        }
        let xAxis = xTicks(
            times: prepared.times,
            kind: prepared.timeKind.tickKind,
            plotWidth: plotArea.width
        ).map { tick in
            Tick(position: x(for: tick.index), text: tick.text)
        }
        let yAxis = yTickPrices(low: prepared.domainLow, high: prepared.domainHigh).map { price in
            Tick(position: priceY(price), text: ChartVisibleExtremes.priceText(price, precision: prepared.precision))
        }
        var high: Mark?
        var low: Mark?
        if let labels = prepared.extremes {
            high = mark(
                index: labels.highIndex,
                price: labels.high,
                digits: prepared.precision,
                plot: plotArea,
                x: x(for:),
                y: priceY
            )
            if labels.highIndex != labels.lowIndex || labels.high != labels.low {
                low = mark(
                    index: labels.lowIndex,
                    price: labels.low,
                    digits: prepared.precision,
                    plot: plotArea,
                    x: x(for:),
                    y: priceY
                )
            }
        }
        let last = prepared.extremes.map {
            Last(
                x: x(for: $0.lastIndex),
                y: priceY($0.last),
                text: ChartVisibleExtremes.priceText($0.last, precision: prepared.precision)
            )
        }
        return Layout(
            plot: plotArea,
            domainLow: prepared.domainLow,
            domainHigh: prepared.domainHigh,
            xTicks: xAxis,
            yTicks: yAxis,
            high: high,
            low: low,
            last: last,
            lastEndX: CGFloat(ChartVisibleExtremes.lastLineEndX(
                plotRight: Double(plotArea.maxX),
                canvasWidth: Double(size.width)
            )),
            vwapCaption: prepared.vwapCaption
        )
    }

    static func xTickCapacity(plotWidth: CGFloat, kind: ChartEasternTime.TickKind) -> Int {
        let labelWidth = kind == .timeWithSeconds ? secondLabelWidth : minuteLabelWidth
        guard plotWidth > 0 else { return 1 }
        return max(1, min(xTickCount, Int((plotWidth + xLabelGap) / (labelWidth + xLabelGap))))
    }

    static func xTickIndices(count: Int, capacity: Int = xTickCount) -> [Int] {
        guard count > 0 else { return [] }
        let ticks = min(xTickCount, count, max(1, capacity))
        if ticks == 1 { return [count - 1] }
        var indices: [Int] = []
        for step in 0..<ticks {
            let index = Int((Double(step) * Double(count - 1) / Double(ticks - 1)).rounded())
            if indices.last != index {
                indices.append(index)
            }
        }
        return indices
    }

    static func xTicks(
        times: [Date],
        kind: ChartEasternTime.TickKind,
        plotWidth: CGFloat? = nil
    ) -> [(index: Int, text: String)] {
        guard !times.isEmpty else { return [] }
        let capacity = plotWidth.map { xTickCapacity(plotWidth: $0, kind: kind) } ?? xTickCount
        let indices = xTickIndices(count: times.count, capacity: capacity)
        var ticks: [(index: Int, text: String)] = []
        for (offset, index) in indices.enumerated() {
            let text = ChartEasternTime.tickLabel(utc: times[index], calendarDay: nil, kind: kind)
            guard !text.isEmpty else { continue }
            let isEnd = offset == 0 || offset + 1 == indices.count
            if !isEnd, ticks.contains(where: { $0.text == text }) { continue }
            ticks.append((index, text))
        }
        return ticks
    }

    static func yTickPrices(low: Double, high: Double) -> [Double] {
        guard low.isFinite, high.isFinite else { return [] }
        if abs(high - low) <= .ulpOfOne { return [high] }
        let steps = yTickCount - 1
        return (0..<yTickCount).map { index in
            high - (high - low) * Double(index) / Double(steps)
        }
    }

    static func extremeCaption(price: String, onLeftHalf: Bool) -> String {
        ChartVisibleExtremes.extremeCaption(price: price, onLeftHalf: onLeftHalf)
    }

    private static func mark(
        index: Int,
        price: Double,
        digits: Int,
        plot: CGRect,
        x: (Int) -> CGFloat,
        y: (Double) -> CGFloat
    ) -> Mark {
        let point = CGPoint(x: x(index), y: y(price))
        let onLeftHalf = point.x < plot.midX
        return Mark(
            point: point,
            text: extremeCaption(
                price: ChartVisibleExtremes.priceText(price, precision: digits),
                onLeftHalf: onLeftHalf
            ),
            onLeftHalf: onLeftHalf
        )
    }

    private static func lineExtremes(values: [Double]) -> ChartVisibleExtremes.Labels? {
        guard let first = values.first else { return nil }
        var highIndex = 0
        var lowIndex = 0
        var high = first
        var low = first
        for index in values.indices.dropFirst() {
            let value = values[index]
            if value > high {
                high = value
                highIndex = index
            }
            if value < low {
                low = value
                lowIndex = index
            }
        }
        return ChartVisibleExtremes.Labels(
            highIndex: highIndex,
            high: high,
            lowIndex: lowIndex,
            low: low,
            lastIndex: values.count - 1,
            last: values[values.count - 1]
        )
    }

    private static func fractionDigits(values: [Double], overlay: [Double]) -> Int {
        var smallest = Double.infinity
        for value in values {
            guard value.isFinite else { continue }
            smallest = min(smallest, abs(value))
        }
        for value in overlay {
            guard value.isFinite else { continue }
            smallest = min(smallest, abs(value))
        }
        guard smallest.isFinite else { return 2 }
        return OrderSizing.priceFractionDigits(for: smallest)
    }

    private static func vwapCaption(vwap: [Double], precision: Int) -> String? {
        guard let value = vwap.last, value.isFinite else { return nil }
        return "\(L10n.Chart.vwap):\(ChartVisibleExtremes.priceText(value, precision: precision))"
    }

    private static func visibleExtremes(_ bars: [Bar], style: ChartStyle) -> ChartVisibleExtremes.Labels? {
        guard !bars.isEmpty else { return nil }
        return ChartVisibleExtremes.labels(
            in: bars,
            from: 0,
            to: Double(bars.count - 1),
            style: style
        )
    }
}
