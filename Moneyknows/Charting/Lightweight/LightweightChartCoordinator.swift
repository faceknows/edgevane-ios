import UIKit
import WebKit
import LightweightCharts

struct LightweightChartSnapshot: Equatable {
    var model: ChartModel
    var colors: ChartColors
}

final class LightweightChartCoordinator: NSObject, LightweightChartsDelegate, ChartDelegate, TimeScaleDelegate {
    var chart: LightweightCharts?
    var onEvent: (ChartEvent) -> Void
    var pending: LightweightChartSnapshot?
    private var applied: LightweightChartSnapshot?
    private var isLoaded = false
    private var mainSeries: (style: ChartStyle, series: SeriesObject)?
    private var overlaySeries: [String: LineSeries] = [:]
    private var volumeSeries: HistogramSeries?
    private var libraryPriceLines: [PriceLine] = []
    private var appliedBars: [Bar] = []
    private var appliedMarkers: [ChartMarker] = []
    private var didFitContent = false
    private var paging = ChartTimeScalePaging.State()
    private var oldestBarTime: Date?
    private var timeScaleAPI: TimeScaleApi?

    init(onEvent: @escaping (ChartEvent) -> Void) {
        self.onEvent = onEvent
    }

    func lightweightChartsDidLoad(_ lightweightCharts: LightweightCharts) {
        Self.installHoveredObjectIdBridge(on: lightweightCharts)
        isLoaded = true
        lightweightCharts.subscribeCrosshairMove()
        lightweightCharts.subscribeClick()
        let scale = lightweightCharts.timeScale()
        scale.delegate = self
        scale.subscribeVisibleLogicalRangeChange()
        timeScaleAPI = scale
        if let pending {
            apply(pending, on: lightweightCharts)
        }
    }

    func lightweightCharts(_ lightweightCharts: LightweightCharts, didFailLoadWithError error: Error) {
        AppLog.chart.error("lightweight charts failed to load")
        onEvent(.loadFailed)
    }

    func applyIfNeeded(_ model: ChartModel, colors: ChartColors, on chart: LightweightCharts) {
        let snapshot = LightweightChartSnapshot(model: model, colors: colors)
        pending = snapshot
        guard isLoaded, applied != snapshot else { return }
        apply(snapshot, on: chart)
    }

    func didClick(onChart chart: ChartApi, parameters: MouseEventParams) {
        if let marker = marker(matching: parameters) {
            onEvent(.pickedMarker(id: marker.id))
            return
        }
        if let bar = bar(matching: parameters) {
            onEvent(.picked(bar))
        }
    }

    func didCrosshairMove(onChart chart: ChartApi, parameters: MouseEventParams) {
        if let bar = bar(matching: parameters) {
            onEvent(.picked(bar))
        }
    }

    func didVisibleTimeRangeChange(onTimeScale timeScale: TimeScaleApi, parameters: TimeRange?) {}

    func didVisibleLogicalRangeChange(onTimeScale timeScale: TimeScaleApi, parameters: LogicalRange?) {
        if ChartTimeScalePaging.handleLogicalRange(
            from: parameters?.from,
            hasBars: !appliedBars.isEmpty,
            state: &paging
        ) {
            onEvent(.reachedOldest)
        }
    }

    func didReceiveTimeScaleSizeChangeWithParameters(onTimeScale timeScale: TimeScaleApi, parameters: Rectangle?) {}

    func chartOptions(_ colors: ChartColors) -> ChartOptions {
        ChartOptions(
            layout: LayoutOptions(
                background: .solid(color: chartColor(colors.background)),
                textColor: chartColor(colors.text)
            ),
            timeScale: TimeScaleOptions(
                timeVisible: true,
                secondsVisible: false
            )
        )
    }

    private func apply(_ snapshot: LightweightChartSnapshot, on chart: LightweightCharts) {
        let model = snapshot.model
        let colors = snapshot.colors
        applied = snapshot
        chart.applyOptions(options: chartOptions(colors))
        let oldest = model.bars.first?.time
        if oldest != oldestBarTime {
            paging.reachedOldest = false
            oldestBarTime = oldest
        }
        if model.bars.isEmpty {
            clear(on: chart)
            appliedBars = []
            appliedMarkers = []
            didFitContent = false
            ChartTimeScalePaging.reset(&paging)
            return
        }
        rebuildMainIfNeeded(model.style, colors: colors, on: chart)
        guard let main = mainSeries else { return }
        applyMainOptions(colors)
        let markers = ChartHitTesting.sorted(model.markers)
        appliedMarkers = markers
        let libraryMarkers = markers.enumerated().map { index, marker in
            Self.marker(marker, colors: colors, libraryID: ChartHitTesting.libraryID(index: index))
        }
        switch model.style {
        case .candle:
            if let series = main.series as? CandlestickSeries {
                series.setData(data: model.bars.map(Self.candlestickData))
                applyPriceLines(model.priceLines, colors: colors, on: series)
                series.setMarkers(data: libraryMarkers)
            }
        case .line:
            if let series = main.series as? LineSeries {
                series.setData(data: model.bars.map(Self.lineData))
                applyPriceLines(model.priceLines, colors: colors, on: series)
                series.setMarkers(data: libraryMarkers)
            }
        }
        syncOverlays(model.overlays, colors: colors, on: chart)
        syncVolume(model, colors: colors, on: chart)
        appliedBars = model.bars
        if !didFitContent {
            ChartTimeScalePaging.beginIgnoringFitContent(&paging)
            chart.timeScale().fitContent()
            didFitContent = true
        }
        if model.followLatest {
            chart.timeScale().scrollToRealTime()
        }
    }

    private func rebuildMainIfNeeded(_ style: ChartStyle, colors: ChartColors, on chart: LightweightCharts) {
        if mainSeries?.style == style { return }
        if let current = mainSeries {
            removeSeries(current.series, on: chart)
            mainSeries = nil
            libraryPriceLines = []
        }
        switch style {
        case .candle:
            mainSeries = (style, chart.addCandlestickSeries(options: candlestickOptions(colors)))
        case .line:
            mainSeries = (style, chart.addLineSeries(options: lineOptions(colors.up)))
        }
    }

    private func applyMainOptions(_ colors: ChartColors) {
        switch mainSeries?.style {
        case .candle:
            (mainSeries?.series as? CandlestickSeries)?.applyOptions(options: candlestickOptions(colors))
        case .line:
            (mainSeries?.series as? LineSeries)?.applyOptions(options: lineOptions(colors.up))
        case .none:
            break
        }
    }

    private func candlestickOptions(_ colors: ChartColors) -> CandlestickSeriesOptions {
        CandlestickSeriesOptions(
            lastValueVisible: false,
            priceLineVisible: false,
            upColor: chartColor(colors.up),
            downColor: chartColor(colors.down),
            borderVisible: false,
            wickUpColor: chartColor(colors.up),
            wickDownColor: chartColor(colors.down)
        )
    }

    private func lineOptions(_ color: ChartRGBA, width: Double = 1) -> LineSeriesOptions {
        LineSeriesOptions(
            lastValueVisible: false,
            priceLineVisible: false,
            color: chartColor(color),
            lineWidth: lineWidth(width)
        )
    }

    private func syncOverlays(_ overlays: [OverlayLine], colors: ChartColors, on chart: LightweightCharts) {
        let ids = Set(overlays.map(\.id))
        for (id, series) in overlaySeries where !ids.contains(id) {
            chart.removeSeries(seriesApi: series)
            overlaySeries[id] = nil
        }
        for overlay in overlays {
            let color = colors.rgba(for: overlay.colorToken)
            let series: LineSeries
            if let existing = overlaySeries[overlay.id] {
                series = existing
                series.applyOptions(options: lineOptions(color, width: overlay.width))
            } else {
                series = chart.addLineSeries(options: lineOptions(color, width: overlay.width))
                overlaySeries[overlay.id] = series
            }
            series.setData(data: overlay.points.map {
                LineData(time: .utc(timestamp: $0.time.timeIntervalSince1970), value: $0.value)
            })
        }
    }

    private func syncVolume(_ model: ChartModel, colors: ChartColors, on chart: LightweightCharts) {
        guard model.showVolume else {
            if let series = volumeSeries {
                chart.removeSeries(seriesApi: series)
                volumeSeries = nil
            }
            return
        }
        let series = volumeSeries ?? chart.addHistogramSeries(options: HistogramSeriesOptions(
            lastValueVisible: false,
            priceScaleId: "volume",
            priceLineVisible: false,
            color: chartColor(colors.volume)
        ))
        if volumeSeries == nil {
            chart.priceScale(priceScaleId: "volume").applyOptions(options: PriceScaleOptions(
                scaleMargins: PriceScaleMargins(top: 0.8, bottom: 0),
                visible: false
            ))
        } else {
            series.applyOptions(options: HistogramSeriesOptions(
                lastValueVisible: false,
                priceScaleId: "volume",
                priceLineVisible: false,
                color: chartColor(colors.volume)
            ))
        }
        volumeSeries = series
        series.setData(data: model.bars.map { bar in
            HistogramData(
                time: .utc(timestamp: bar.time.timeIntervalSince1970),
                value: bar.volume,
                color: chartColor(bar.close >= bar.open ? colors.up : colors.down)
            )
        })
    }

    private func applyPriceLines<Series: SeriesApi>(_ lines: [ChartModel.PriceLine], colors: ChartColors, on series: Series) {
        for line in libraryPriceLines {
            series.removePriceLine(line: line)
        }
        libraryPriceLines = lines.map { line in
            series.createPriceLine(options: PriceLineOptions(
                id: line.id,
                price: line.price,
                color: chartColor(colors.rgba(for: line.colorToken)),
                lineWidth: .one,
                lineStyle: line.dashed ? .dashed : .solid,
                axisLabelVisible: true,
                title: line.title
            ))
        }
    }

    private func clear(on chart: LightweightCharts) {
        if let current = mainSeries {
            removeSeries(current.series, on: chart)
            mainSeries = nil
        }
        for series in overlaySeries.values {
            chart.removeSeries(seriesApi: series)
        }
        overlaySeries = [:]
        if let series = volumeSeries {
            chart.removeSeries(seriesApi: series)
            volumeSeries = nil
        }
        libraryPriceLines = []
        appliedMarkers = []
    }

    private func removeSeries(_ series: SeriesObject, on chart: LightweightCharts) {
        if let candle = series as? CandlestickSeries {
            chart.removeSeries(seriesApi: candle)
        } else if let line = series as? LineSeries {
            chart.removeSeries(seriesApi: line)
        }
    }

    private func bar(matching parameters: MouseEventParams) -> Bar? {
        guard let time = date(from: parameters.time) else { return nil }
        return ChartHitTesting.pickedBar(in: appliedBars, at: time)
    }

    private func marker(matching parameters: MouseEventParams) -> ChartMarker? {
        ChartHitTesting.pickedMarker(
            in: appliedMarkers,
            hoveredId: parameters.hoveredObjectId.map(String.init)
        )
    }

    private func date(from time: EventTime?) -> Date? {
        switch time {
        case let .utc(timestamp):
            return Date(timeIntervalSince1970: timestamp)
        case let .businessDayString(raw):
            return ISO8601DateFormatter().date(from: raw)
        case .businessDay, .none:
            return nil
        }
    }

    private func lineWidth(_ width: Double) -> LineWidth {
        if width >= 4 { return .four }
        if width >= 3 { return .three }
        if width >= 2 { return .two }
        return .one
    }

    private func chartColor(_ rgba: ChartRGBA) -> ChartColor {
        ChartColor(UIColor(
            red: CGFloat(rgba.red),
            green: CGFloat(rgba.green),
            blue: CGFloat(rgba.blue),
            alpha: CGFloat(rgba.alpha)
        ))
    }

    /// LC iOS 4 decodes `hoveredObjectId` as `Int`. Marker / price-line ids are JSON strings,
    /// so a click would fail to decode and `didClick` would never run. Coerce numeric ids
    /// (our marker namespace) and drop non-numeric ones before the message is posted.
    private static func installHoveredObjectIdBridge(on chart: LightweightCharts) {
        guard let webView = webView(in: chart) else { return }
        webView.evaluateJavaScript("""
        (function() {
          if (window.__mkHoveredObjectIdBridge) { return; }
          window.__mkHoveredObjectIdBridge = true;
          var stringify = JSON.stringify;
          JSON.stringify = function(value, replacer, space) {
            if (value && typeof value === 'object' && !Array.isArray(value) && value.hoveredObjectId != null) {
              var payload = Object.assign({}, value);
              var numeric = Number(payload.hoveredObjectId);
              if (isFinite(numeric) && String(numeric) === String(payload.hoveredObjectId).trim()) {
                payload.hoveredObjectId = numeric;
              } else {
                delete payload.hoveredObjectId;
              }
              return stringify.call(this, payload, replacer, space);
            }
            return stringify.apply(this, arguments);
          };
        })();
        """, completionHandler: nil)
    }

    private static func webView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for child in view.subviews {
            if let webView = webView(in: child) { return webView }
        }
        return nil
    }

    private static func candlestickData(_ bar: Bar) -> CandlestickData {
        CandlestickData(
            time: .utc(timestamp: bar.time.timeIntervalSince1970),
            open: bar.open,
            high: bar.high,
            low: bar.low,
            close: bar.close
        )
    }

    private static func lineData(_ bar: Bar) -> LineData {
        LineData(time: .utc(timestamp: bar.time.timeIntervalSince1970), value: bar.close)
    }

    private static func marker(_ marker: ChartMarker, colors: ChartColors, libraryID: String) -> SeriesMarker {
        let position: SeriesMarkerPosition
        switch marker.position {
        case .aboveBar:
            position = .aboveBar
        case .belowBar:
            position = .belowBar
        case .auto:
            position = marker.kind == .buy ? .belowBar : .aboveBar
        }
        let shape: SeriesMarkerShape = marker.kind == .buy ? .arrowUp : (marker.kind == .sell ? .arrowDown : .circle)
        let token: ChartColorToken = marker.kind == .buy ? .buy : (marker.kind == .sell ? .sell : .other)
        return SeriesMarker(
            time: .utc(timestamp: marker.time.timeIntervalSince1970),
            position: position,
            shape: shape,
            color: ChartColor(UIColor(
                red: CGFloat(colors.rgba(for: token).red),
                green: CGFloat(colors.rgba(for: token).green),
                blue: CGFloat(colors.rgba(for: token).blue),
                alpha: CGFloat(colors.rgba(for: token).alpha)
            )),
            id: libraryID,
            text: marker.title ?? String(format: "%.2f", marker.price)
        )
    }
}
