import Charts
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
        let minY = inset
        let maxY = max(minY, size.height - inset)
        let span = high - low
        if span == 0 { return (minY + maxY) / 2 }
        let t = (value - low) / span
        return maxY - CGFloat(t) * (maxY - minY)
    }

    static func candleX(index: Int, count: Int, in size: CGSize, inset: CGFloat = 2) -> CGFloat {
        let minX = inset
        let maxX = max(minX, size.width - inset)
        guard count > 0, maxX > minX else { return (minX + maxX) / 2 }
        if count == 1 { return (minX + maxX) / 2 }
        let slot = (maxX - minX) / CGFloat(count)
        return minX + slot * (CGFloat(index) + 0.5)
    }

    static func candleBodyWidth(count: Int, in size: CGSize, inset: CGFloat = 2) -> CGFloat {
        let minX = inset
        let maxX = max(minX, size.width - inset)
        guard count > 0, maxX > minX else { return 1 }
        let slot = (maxX - minX) / CGFloat(count)
        return max(1, slot * 0.6)
    }
}

enum SparklinePlot: Equatable {
    case line(values: [Double], overlay: [Double] = [])
    case candles(bars: [Bar], vwap: [Double] = [])

    var isEmpty: Bool {
        switch self {
        case .line(let values, _):
            return values.filter(\.isFinite).isEmpty
        case .candles(let bars, _):
            return bars.isEmpty
        }
    }

    /// Overlay / VWAP is kept only when it matches the drawable series 1:1.
    func aligned() -> SparklinePlot {
        switch self {
        case .line(let values, let overlay):
            let series = Self.alignedLine(values: values, overlay: overlay)
            return .line(values: series.values, overlay: series.overlay)
        case .candles(let bars, let vwap):
            return .candles(bars: bars, vwap: Self.alignedOverlay(overlay: vwap, count: bars.count))
        }
    }

    private static func alignedLine(values: [Double], overlay: [Double]) -> (values: [Double], overlay: [Double]) {
        let closes = values.filter(\.isFinite)
        guard overlay.count == values.count else {
            return (closes, [])
        }
        var extra: [Double] = []
        extra.reserveCapacity(closes.count)
        for (close, value) in zip(values, overlay) {
            guard close.isFinite else { continue }
            guard value.isFinite else { return (closes, []) }
            extra.append(value)
        }
        return extra.count == closes.count ? (closes, extra) : (closes, [])
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
                drawn
                    .opacity(errorText == nil ? 1 : 0.28)
                    .accessibilityHidden(true)
            }
            if let errorText {
                SparklineFailure(text: errorText, retry: retry)
            }
        }
        .accessibilityHidden(errorText == nil)
    }

    @ViewBuilder
    private var drawn: some View {
        switch plot.aligned() {
        case .line(let values, let overlay):
            plotted(values, overlay: overlay)
        case .candles(let bars, let vwap):
            candles(bars: bars, vwap: vwap)
        }
    }

    @ViewBuilder
    private func plotted(_ values: [Double], overlay: [Double]) -> some View {
        if #available(iOS 16.0, *) {
            chart(values, overlay: overlay)
        } else {
            canvas(values, overlay: overlay)
        }
    }

    @available(iOS 16.0, *)
    private func chart(_ values: [Double], overlay: [Double]) -> some View {
        let closes = values.enumerated().map { SparklineSample(id: "c-\($0.offset)", index: $0.offset, value: $0.element) }
        let overlays = overlay.enumerated().compactMap { index, value -> SparklineSample? in
            guard value.isFinite else { return nil }
            return SparklineSample(id: "v-\(index)", index: index, value: value)
        }
        let domain = SparklineGeometry.domain(values: values, overlay: overlay)
        let low = domain?.low ?? 0
        let high = domain?.high ?? 0
        let pad = high == low ? max(abs(high) * 0.001, 0.01) : 0
        return Chart {
            if values.count == 1 {
                ForEach(closes) { sample in
                    PointMark(
                        x: .value("i", Double(sample.index)),
                        y: .value("v", sample.value)
                    )
                    .foregroundStyle(color)
                    .symbolSize(9)
                }
                ForEach(overlays) { sample in
                    PointMark(
                        x: .value("i", Double(sample.index)),
                        y: .value("v", sample.value)
                    )
                    .foregroundStyle(overlayColor)
                    .symbolSize(9)
                }
            } else {
                ForEach(closes) { sample in
                    LineMark(
                        x: .value("i", Double(sample.index)),
                        y: .value("v", sample.value)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    .interpolationMethod(.linear)
                }
                ForEach(overlays) { sample in
                    LineMark(
                        x: .value("i", Double(sample.index)),
                        y: .value("v", sample.value)
                    )
                    .foregroundStyle(overlayColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, lineJoin: .round))
                    .interpolationMethod(.linear)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: SparklineGeometry.chartXDomain(count: values.count))
        .chartYScale(domain: (low - pad)...(high + pad))
    }

    private func canvas(_ values: [Double], overlay: [Double]) -> some View {
        Canvas { context, size in
            let domain = SparklineGeometry.domain(values: values, overlay: overlay)
            let low = domain?.low ?? 0
            let high = domain?.high ?? 0
            draw(values: values, color: color, low: low, high: high, in: &context, size: size)
            if !overlay.isEmpty {
                draw(values: overlay, color: overlayColor, low: low, high: high, in: &context, size: size)
            }
        }
    }

    private func draw(
        values: [Double],
        color: Color,
        low: Double,
        high: Double,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let points = SparklineGeometry.points(values: values, in: size, low: low, high: high)
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

    private func candles(bars: [Bar], vwap: [Double]) -> some View {
        Canvas { context, size in
            guard let domain = SparklineGeometry.barDomain(bars: bars, overlay: vwap) else { return }
            let count = bars.count
            let bodyWidth = SparklineGeometry.candleBodyWidth(count: count, in: size)
            for (index, bar) in bars.enumerated() {
                let x = SparklineGeometry.candleX(index: index, count: count, in: size)
                let color = bar.close >= bar.open ? upColor : downColor
                let high = SparklineGeometry.y(bar.high, low: domain.low, high: domain.high, in: size)
                let low = SparklineGeometry.y(bar.low, low: domain.low, high: domain.high, in: size)
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: high))
                wick.addLine(to: CGPoint(x: x, y: low))
                context.stroke(wick, with: .color(color), lineWidth: 1)

                let open = SparklineGeometry.y(bar.open, low: domain.low, high: domain.high, in: size)
                let close = SparklineGeometry.y(bar.close, low: domain.low, high: domain.high, in: size)
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
                    x: SparklineGeometry.candleX(index: index, count: count, in: size),
                    y: SparklineGeometry.y(value, low: domain.low, high: domain.high, in: size)
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
    }
}

struct SparklinePane: View {
    var title: String
    var plot: SparklinePlot
    var overlayColor: Color? = nil
    var baseline: Double?
    var chartHeight: CGFloat = 72
    var isLoading: Bool
    var errorText: String? = nil
    var retry: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    /// Scanner passes copy; Trade Tab omits it so a successful empty fetch stays blank.
    var emptyText: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        case .line(let values, _):
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

private struct SparklineSample: Identifiable {
    var id: String
    var index: Int
    var value: Double
}
