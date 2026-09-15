import SwiftUI

enum SparklineGeometry {
    static func domain(values: [Double], overlay: [Double] = []) -> (low: Double, high: Double)? {
        let finite = (values + overlay).filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return nil }
        return (low, high)
    }

    static func points(values: [Double], in size: CGSize, inset: CGFloat = 2) -> [CGPoint] {
        guard let domain = domain(values: values) else { return [] }
        return points(values: values, in: size, inset: inset, low: domain.low, high: domain.high)
    }

    static func points(
        values: [Double],
        in size: CGSize,
        inset: CGFloat = 2,
        low: Double,
        high: Double
    ) -> [CGPoint] {
        let finite = values.filter { $0.isFinite }
        guard size.width > 0, size.height > 0, !finite.isEmpty else { return [] }
        let minX = inset
        let maxX = max(minX, size.width - inset)
        let minY = inset
        let maxY = max(minY, size.height - inset)
        guard maxX > minX, maxY > minY else { return [] }
        let span = high - low
        return finite.enumerated().map { index, value in
            let x: CGFloat
            if finite.count == 1 {
                x = (minX + maxX) / 2
            } else {
                x = minX + (maxX - minX) * CGFloat(index) / CGFloat(finite.count - 1)
            }
            let y: CGFloat
            if span == 0 {
                y = (minY + maxY) / 2
            } else {
                let t = (value - low) / span
                y = maxY - CGFloat(t) * (maxY - minY)
            }
            return CGPoint(x: x, y: y)
        }
    }

    static func delta(values: [Double], baseline: Double? = nil) -> Double? {
        let finite = values.filter { $0.isFinite }
        guard let last = finite.last else { return nil }
        if let baseline, baseline.isFinite {
            return last - baseline
        }
        guard let first = finite.first else { return nil }
        return last - first
    }

    static func chartXDomain(count: Int) -> ClosedRange<Double> {
        count <= 1 ? -1...1 : 0...Double(count - 1)
    }

    static func barDomain(bars: [Bar], overlay: [Double] = []) -> (low: Double, high: Double)? {
        var prices: [Double] = []
        for bar in bars {
            if bar.high.isFinite { prices.append(bar.high) }
            if bar.low.isFinite { prices.append(bar.low) }
        }
        prices.append(contentsOf: overlay.filter(\.isFinite))
        guard let low = prices.min(), let high = prices.max() else { return nil }
        return (low, high)
    }

    static func y(_ value: Double, low: Double, high: Double, in size: CGSize, inset: CGFloat = 2) -> CGFloat {
        y(value, low: low, high: high, in: plotRect(in: size, inset: inset))
    }

    static func y(_ value: Double, low: Double, high: Double, in plot: CGRect) -> CGFloat {
        let span = high - low
        if span == 0 { return plot.midY }
        let t = (value - low) / span
        return plot.maxY - CGFloat(t) * plot.height
    }

    static func lineX(index: Int, count: Int, in plot: CGRect) -> CGFloat {
        guard count > 0 else { return plot.midX }
        if count == 1 { return plot.midX }
        return plot.minX + plot.width * CGFloat(index) / CGFloat(count - 1)
    }

    static func candleX(index: Int, count: Int, in size: CGSize, inset: CGFloat = 2) -> CGFloat {
        candleX(index: index, count: count, in: plotRect(in: size, inset: inset))
    }

    static func candleX(index: Int, count: Int, in plot: CGRect) -> CGFloat {
        guard count > 0, plot.width > 0 else { return plot.midX }
        if count == 1 { return plot.midX }
        let slot = plot.width / CGFloat(count)
        return plot.minX + slot * (CGFloat(index) + 0.5)
    }

    static func candleBodyWidth(count: Int, in size: CGSize, inset: CGFloat = 2) -> CGFloat {
        candleBodyWidth(count: count, in: plotRect(in: size, inset: inset))
    }

    static func candleBodyWidth(count: Int, in plot: CGRect) -> CGFloat {
        guard count > 0, plot.width > 0 else { return 1 }
        let slot = plot.width / CGFloat(count)
        return max(1, slot * 0.6)
    }

    private static func plotRect(in size: CGSize, inset: CGFloat) -> CGRect {
        CGRect(
            x: inset,
            y: inset,
            width: max(0, size.width - inset * 2),
            height: max(0, size.height - inset * 2)
        )
    }
}

enum SparklinePlot: Equatable {
    case line(values: [Double], times: [Date] = [], overlay: [Double] = [], timeKind: SparklineTimeKind = .minute)
    case candles(bars: [Bar], vwap: [Double] = [], timeKind: SparklineTimeKind = .minute)

    var isEmpty: Bool {
        switch self {
        case .line(let values, _, _, _):
            return values.filter(\.isFinite).isEmpty
        case .candles(let bars, _, _):
            return bars.isEmpty
        }
    }

    /// Overlay / VWAP is kept only when it matches the drawable series 1:1.
    func aligned() -> SparklinePlot {
        switch self {
        case .line(let values, let times, let overlay, let timeKind):
            let series = Self.alignedLine(values: values, overlay: overlay, times: times)
            return .line(values: series.values, times: series.times, overlay: series.overlay, timeKind: timeKind)
        case .candles(let bars, let vwap, let timeKind):
            return .candles(bars: bars, vwap: Self.alignedOverlay(overlay: vwap, count: bars.count), timeKind: timeKind)
        }
    }

    private static func alignedLine(
        values: [Double],
        overlay: [Double],
        times: [Date]
    ) -> (values: [Double], overlay: [Double], times: [Date]) {
        let keepTimes = times.count == values.count
        let keepOverlay = overlay.count == values.count
        var closes: [Double] = []
        var extra: [Double] = []
        var keptTimes: [Date] = []
        var overlayOK = keepOverlay
        closes.reserveCapacity(values.count)
        extra.reserveCapacity(values.count)
        keptTimes.reserveCapacity(values.count)
        for (index, close) in values.enumerated() {
            guard close.isFinite else { continue }
            closes.append(close)
            if keepTimes {
                keptTimes.append(times[index])
            }
            if overlayOK {
                let value = overlay[index]
                if value.isFinite {
                    extra.append(value)
                } else {
                    overlayOK = false
                }
            }
        }
        return (
            closes,
            overlayOK && extra.count == closes.count ? extra : [],
            keepTimes && keptTimes.count == closes.count ? keptTimes : []
        )
    }

    private static func alignedOverlay(overlay: [Double], count: Int) -> [Double] {
        guard overlay.count == count else { return [] }
        var extra: [Double] = []
        extra.reserveCapacity(count)
        for value in overlay {
            guard value.isFinite else { return [] }
            extra.append(value)
        }
        return extra
    }
}

enum SparklineEmptyPolicy {
    /// `emptyText == nil` keeps the pane blank (Trade Tab). A non-empty string is the scanner empty copy.
    static func showsPrompt(
        isLoading: Bool,
        errorText: String?,
        isEmpty: Bool,
        emptyText: String?
    ) -> Bool {
        guard let emptyText, !emptyText.isEmpty else { return false }
        return !isLoading && (errorText ?? "").isEmpty && isEmpty
    }
}

struct SparklineView: View {
    var plot: SparklinePlot
    var color: Color
    var overlayColor: Color = .blue
    var upColor: Color = .green
    var downColor: Color = .red
    var isLoading = false
    var errorText: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        ZStack {
            if isLoading, plot.isEmpty {
                ProgressView()
                    .scaleEffect(0.75)
            } else if !plot.isEmpty {
                canvas
                    .opacity(errorText == nil ? 1 : 0.28)
                    .accessibilityHidden(true)
            }
            if let errorText {
                SparklineFailure(text: errorText, retry: retry)
            }
        }
        .accessibilityHidden(errorText == nil)
    }

    private var canvas: some View {
        Canvas { context, size in
            guard let prepared = SparklineChrome.prepare(plot),
                  let layout = SparklineChrome.layout(for: prepared, in: size) else { return }
            if prepared.usesCandles {
                drawCandles(prepared.bars, vwap: prepared.overlay, layout: layout, in: &context)
            } else {
                drawLine(prepared.values, color: color, layout: layout, in: &context)
                if !prepared.overlay.isEmpty {
                    drawLine(prepared.overlay, color: overlayColor, layout: layout, in: &context)
                }
            }
            drawLastLine(layout, in: &context)
            drawMarks(layout, in: &context)
            drawAxes(layout, in: &context, size: size)
        }
    }

    private var axisColor: Color { .secondary }
    private var markColor: Color { Color(uiColor: .label) }
    private var lastColor: Color { .accentColor }

    private func drawLine(
        _ values: [Double],
        color: Color,
        layout: SparklineChrome.Layout,
        in context: inout GraphicsContext
    ) {
        let points = values.enumerated().compactMap { index, value -> CGPoint? in
            guard value.isFinite else { return nil }
            return CGPoint(
                x: SparklineGeometry.lineX(index: index, count: values.count, in: layout.plot),
                y: y(value, layout: layout)
            )
        }
        guard let first = points.first else { return }
        if points.count == 1 {
            let dot = Path(ellipseIn: CGRect(x: first.x - 1.5, y: first.y - 1.5, width: 3, height: 3))
            context.fill(dot, with: .color(color))
            return
        }
        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() {
            line.addLine(to: point)
        }
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    private func drawCandles(
        _ bars: [Bar],
        vwap: [Double],
        layout: SparklineChrome.Layout,
        in context: inout GraphicsContext
    ) {
        let count = bars.count
        let bodyWidth = SparklineGeometry.candleBodyWidth(count: count, in: layout.plot)
        for (index, bar) in bars.enumerated() {
            let x = SparklineGeometry.candleX(index: index, count: count, in: layout.plot)
            let color = bar.close >= bar.open ? upColor : downColor
            let high = y(bar.high, layout: layout)
            let low = y(bar.low, layout: layout)
            var wick = Path()
            wick.move(to: CGPoint(x: x, y: high))
            wick.addLine(to: CGPoint(x: x, y: low))
            context.stroke(wick, with: .color(color), lineWidth: 1)

            let open = y(bar.open, layout: layout)
            let close = y(bar.close, layout: layout)
            let body = CGRect(
                x: x - bodyWidth / 2,
                y: min(open, close),
                width: bodyWidth,
                height: max(1, abs(close - open))
            )
            context.fill(Path(body), with: .color(color))
        }
        guard vwap.count == count else { return }
        let points = vwap.enumerated().map { index, value in
            CGPoint(
                x: SparklineGeometry.candleX(index: index, count: count, in: layout.plot),
                y: y(value, layout: layout)
            )
        }
        guard let first = points.first else { return }
        if points.count == 1 {
            let dot = Path(ellipseIn: CGRect(x: first.x - 1.5, y: first.y - 1.5, width: 3, height: 3))
            context.fill(dot, with: .color(overlayColor))
            return
        }
        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() {
            line.addLine(to: point)
        }
        context.stroke(line, with: .color(overlayColor), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    private func drawLastLine(_ layout: SparklineChrome.Layout, in context: inout GraphicsContext) {
        guard let last = layout.last, layout.lastEndX - last.x > 1 else { return }
        var dash = Path()
        dash.move(to: CGPoint(x: last.x, y: last.y))
        dash.addLine(to: CGPoint(x: layout.lastEndX, y: last.y))
        context.stroke(dash, with: .color(lastColor), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func drawAxes(
        _ layout: SparklineChrome.Layout,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        if let caption = layout.vwapCaption {
            context.draw(
                Text(caption)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(overlayColor),
                at: CGPoint(x: layout.plot.minX, y: layout.plot.minY - 2),
                anchor: .bottomLeading
            )
        }
        for tick in layout.xTicks {
            context.draw(
                axisLabel(tick.text),
                at: CGPoint(x: tick.position, y: layout.plot.maxY + 4),
                anchor: xAnchor(x: tick.position, plot: layout.plot)
            )
        }
        for tick in layout.yTicks {
            context.draw(
                axisLabel(tick.text),
                at: CGPoint(x: size.width - 2, y: tick.position),
                anchor: .trailing
            )
        }
        if let last = layout.last {
            context.draw(
                lastLabel(last.text),
                at: CGPoint(x: size.width - 2, y: last.y),
                anchor: .trailing
            )
        }
    }

    private func drawMarks(_ layout: SparklineChrome.Layout, in context: inout GraphicsContext) {
        if let high = layout.high {
            context.draw(
                markLabel(high.text),
                at: high.point,
                anchor: high.onLeftHalf ? .leading : .trailing
            )
        }
        if let low = layout.low {
            context.draw(
                markLabel(low.text),
                at: low.point,
                anchor: low.onLeftHalf ? .leading : .trailing
            )
        }
    }

    private func y(_ value: Double, layout: SparklineChrome.Layout) -> CGFloat {
        SparklineGeometry.y(value, low: layout.domainLow, high: layout.domainHigh, in: layout.plot)
    }

    private func axisLabel(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundColor(axisColor)
    }

    private func lastLabel(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(lastColor)
    }

    private func markLabel(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundColor(markColor)
    }

    private func xAnchor(x: CGFloat, plot: CGRect) -> UnitPoint {
        let t = (x - plot.minX) / max(plot.width, 1)
        if t < 0.15 { return .topLeading }
        if t > 0.85 { return .topTrailing }
        return .top
    }
}

struct SparklinePane: View {
    var title: String
    var plot: SparklinePlot
    var overlayColor: Color? = nil
    var baseline: Double?
    var chartHeight: CGFloat = 120
    var isLoading: Bool
    var errorText: String? = nil
    var retry: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    /// Scanner passes copy; Trade Tab omits it so a successful empty fetch stays blank.
    var emptyText: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            if showsEmptyPrompt, let emptyText {
                SparklineFailure(text: emptyText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ZStack {
                    Group {
                        if let onOpen {
                            Button(action: onOpen) {
                                sparkline
                                    .opacity(errorText == nil ? 1 : 0.28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHidden(true)
                        } else {
                            sparkline
                        }
                    }
                    if onOpen != nil, let errorText, !isLoading {
                        SparklineFailure(text: errorText, retry: retry)
                    }
                }
                .frame(height: chartHeight)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var showsEmptyPrompt: Bool {
        SparklineEmptyPolicy.showsPrompt(
            isLoading: isLoading,
            errorText: errorText,
            isEmpty: plot.isEmpty,
            emptyText: emptyText
        )
    }

    private var sparkline: some View {
        SparklineView(
            plot: plot,
            color: strokeColor,
            overlayColor: overlayColor ?? ChartPalette.color(.vwap, scheme: colorScheme),
            upColor: ChartPalette.color(.up, scheme: colorScheme),
            downColor: ChartPalette.color(.down, scheme: colorScheme),
            isLoading: isLoading,
            errorText: onOpen == nil ? errorText : nil,
            retry: onOpen == nil ? retry : nil
        )
    }

    private var strokeColor: Color {
        switch plot {
        case .line(let values, _, _, _):
            return MarketFormat.changeColor(SparklineGeometry.delta(values: values, baseline: baseline))
        case .candles:
            return MarketFormat.changeColor(nil)
        }
    }
}

struct SparklineFailure: View {
    var text: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            if let retry {
                Button(L10n.Common.retry, action: retry)
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 4)
    }
}

extension SparklinePlot {
    static func watchMinutes(bars1m: [Bar]) -> SparklinePlot {
        let line = SubscriptionSparklineAssembler.minuteLine(bars1m: bars1m, includeVWAP: true)
        return .line(values: line.values, times: line.times, overlay: line.vwap, timeKind: .minute)
    }
}

struct WatchSparklinePair: View {
    var symbol: String
    var minutePlot: SparklinePlot
    var previousClose: Double?
    var isMinuteLoading: Bool
    var minuteError: String? = nil
    var retryMinutes: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            SparklinePane(
                title: "",
                plot: minutePlot,
                baseline: previousClose,
                isLoading: isMinuteLoading,
                errorText: minuteError,
                retry: retryMinutes,
                onOpen: onOpen
            )
            if let onOpen {
                Button(action: onOpen) {
                    WatchSecondPane(symbol: symbol)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            } else {
                WatchSecondPane(symbol: symbol)
            }
        }
    }
}

struct WatchSecondPane: View {
    @EnvironmentObject private var seconds: SecondBarStore
    var symbol: String

    var body: some View {
        let line = SubscriptionSparklineAssembler.secondLine(
            bars1s: seconds.bars(for: symbol),
            now: Date()
        )
        return SparklinePane(
            title: "",
            plot: .line(values: line.values, times: line.times, timeKind: .second),
            baseline: line.values.first,
            isLoading: false
        )
    }
}

struct SecondBarExpiryPump: View {
    @EnvironmentObject private var seconds: SecondBarStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                await seconds.startExpiring()
            }
    }
}
