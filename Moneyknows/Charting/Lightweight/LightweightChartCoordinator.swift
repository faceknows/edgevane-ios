import UIKit
import WebKit
import LightweightCharts

struct LightweightChartSnapshot: Equatable {
    var model: ChartModel
    var colors: ChartColors
    var volumeHeight: CGFloat?
    var chartHeight: CGFloat
}

final class LightweightChartCoordinator: NSObject, LightweightChartsDelegate, ChartDelegate, TimeScaleDelegate {
    var chart: LightweightCharts?
    var onEvent: (ChartEvent) -> Void
    var pending: LightweightChartSnapshot?
    let pageScrollPassthrough = ChartPageScrollPassthrough()
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
    private var didInstallFormatters = false

    init(onEvent: @escaping (ChartEvent) -> Void) {
        self.onEvent = onEvent
    }

    func lightweightChartsDidLoad(_ lightweightCharts: LightweightCharts) {
        Self.installHoveredObjectIdBridge(on: lightweightCharts)
        Self.installVerticalPageScrollBridge(on: lightweightCharts)
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
        AppLog.chart.error("lightweight charts failed to load \(error.localizedDescription, privacy: .public)")
        onEvent(.loadFailed)
    }

    func applyIfNeeded(
        _ model: ChartModel,
        colors: ChartColors,
        volumeHeight: CGFloat?,
        chartHeight: CGFloat,
        on chart: LightweightCharts
    ) {
        let snapshot = LightweightChartSnapshot(
            model: model,
            colors: colors,
            volumeHeight: volumeHeight,
            chartHeight: chartHeight
        )
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
            timeScale.applyOptions(options: TimeScaleOptions(fixLeftEdge: true))
        }
    }

    func didReceiveTimeScaleSizeChangeWithParameters(onTimeScale timeScale: TimeScaleApi, parameters: Rectangle?) {}

    func bootstrapOptions(_ colors: ChartColors) -> ChartOptions {
        chartOptions(colors, includeFormatters: false, lockLeftEdge: false)
    }

    private func chartOptions(
        _ colors: ChartColors,
        includeFormatters: Bool,
        lockLeftEdge: Bool,
        volumeHeight: CGFloat? = nil,
        chartHeight: CGFloat = 0,
        timeVisible: Bool = true
    ) -> ChartOptions {
        let grid = chartColor(colors.grid)
        let price = ChartVolumeLayout.priceMargins(volumeHeight: volumeHeight, totalHeight: chartHeight)
        return ChartOptions(
            layout: LayoutOptions(
                background: .solid(color: chartColor(colors.background)),
                textColor: chartColor(colors.text)
            ),
            rightPriceScale: PriceScaleOptions(
                scaleMargins: PriceScaleMargins(top: price.top, bottom: price.bottom),
                borderColor: grid
            ),
            timeScale: TimeScaleOptions(
                fixLeftEdge: lockLeftEdge,
                borderColor: grid,
                timeVisible: timeVisible,
                secondsVisible: false,
                tickMarkFormatter: includeFormatters ? .closure(Self.easternTickMark) : nil
            ),
            grid: GridOptions(
                verticalLines: GridLineOptions(color: grid),
                horizontalLines: GridLineOptions(color: grid)
            ),
            localization: includeFormatters
                ? LocalizationOptions(timeFormatter: .closure(Self.easternCrosshairTime))
                : nil,
            handleScroll: .options(HandleScrollOptions.Options(
                mouseWheel: true,
                pressedMouseMove: true,
                horzTouchDrag: ChartTouchScrolling.horizontalTouchDrag,
                vertTouchDrag: ChartTouchScrolling.verticalTouchDrag
            )),
            handleScale: .options(HandleScaleOptions(
                pinch: true,
                axisPressedMouseMove: .options(AxisPressedMouseMoveOptions(time: true, price: false))
            ))
        )
    }

    private func apply(_ snapshot: LightweightChartSnapshot, on chart: LightweightCharts) {
        let model = snapshot.model
        let colors = snapshot.colors
        applied = snapshot
        let oldest = model.bars.first?.time
        if oldest != oldestBarTime {
            paging.reachedOldest = false
            oldestBarTime = oldest
        }
        let attachFormatters = ChartLibraryOptions.attachFormatters(alreadyInstalled: didInstallFormatters)
        chart.applyOptions(options: chartOptions(
            colors,
            includeFormatters: attachFormatters,
            lockLeftEdge: ChartTimeScalePaging.locksLeftEdge(paging),
            volumeHeight: snapshot.volumeHeight,
            chartHeight: snapshot.chartHeight,
            timeVisible: !model.usesCalendarDays
        ))
        if attachFormatters {
            didInstallFormatters = true
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
                series.setData(data: model.bars.map { Self.candlestickData($0, usesCalendarDays: model.usesCalendarDays) })
                applyPriceLines(model.priceLines, colors: colors, on: series)
                series.setMarkers(data: libraryMarkers)
            }
        case .line:
            if let series = main.series as? LineSeries {
                series.setData(data: model.bars.map { Self.lineData($0, usesCalendarDays: model.usesCalendarDays) })
                applyPriceLines(model.priceLines, colors: colors, on: series)
                series.setMarkers(data: libraryMarkers)
            }
        }
        syncOverlays(model.overlays, colors: colors, on: chart)
        syncVolume(model, colors: colors, on: chart)
        applyVolumeLayout(volumeHeight: snapshot.volumeHeight, chartHeight: snapshot.chartHeight)
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
                LineData(time: Self.libraryTime($0.time, usesCalendarDays: applied?.model.usesCalendarDays ?? false), value: $0.value)
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
        let options = volumeOptions(colors)
        let series = volumeSeries ?? chart.addHistogramSeries(options: options)
        if volumeSeries != nil {
            series.applyOptions(options: options)
        }
        volumeSeries = series
        series.setData(data: model.bars.map { bar in
            HistogramData(
                time: Self.libraryTime(bar.time, usesCalendarDays: model.usesCalendarDays),
                value: bar.volume,
                color: volumeBarColor(bar, colors: colors)
            )
        })
    }

    private func applyVolumeLayout(volumeHeight: CGFloat?, chartHeight: CGFloat) {
        let price = ChartVolumeLayout.priceMargins(volumeHeight: volumeHeight, totalHeight: chartHeight)
        applyPriceScale(
            PriceScaleOptions(scaleMargins: PriceScaleMargins(top: price.top, bottom: price.bottom)),
            to: mainSeries?.series
        )
        guard let volumeHeight, let volumeSeries else { return }
        let volume = ChartVolumeLayout.volumeMargins(volumeHeight: volumeHeight, totalHeight: chartHeight)
        volumeSeries.priceScale().applyOptions(options: PriceScaleOptions(
            scaleMargins: PriceScaleMargins(top: volume.top, bottom: volume.bottom),
            borderVisible: false
        ))
    }

    private func applyPriceScale(_ options: PriceScaleOptions, to series: SeriesObject?) {
        if let candle = series as? CandlestickSeries {
            candle.priceScale().applyOptions(options: options)
        } else if let line = series as? LineSeries {
            line.priceScale().applyOptions(options: options)
        }
    }

    private func volumeOptions(_ colors: ChartColors) -> HistogramSeriesOptions {
        HistogramSeriesOptions(
            lastValueVisible: false,
            priceScaleId: "volume",
            priceLineVisible: false,
            priceFormat: .builtIn(BuiltInPriceFormat(type: .volume, precision: nil, minMove: 1)),
            color: chartColor(colors.volume)
        )
    }

    private func volumeBarColor(_ bar: Bar, colors: ChartColors) -> ChartColor {
        chartColor(bar.close >= bar.open ? colors.up : colors.down)
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
        Self.date(from: time)
    }

    private static func date(from time: EventTime?) -> Date? {
        guard let time else { return nil }
        let parsed = parsedTime(time)
        if let utc = parsed.utc {
            return utc
        }
        if let day = parsed.calendarDay {
            return ChartEasternTime.date(calendarDay: day)
        }
        return nil
    }

    private static func parsedTime(_ time: EventTime) -> (utc: Date?, calendarDay: ChartEasternTime.CalendarDay?) {
        switch time {
        case let .utc(timestamp):
            return (Date(timeIntervalSince1970: timestamp), nil)
        case let .businessDay(day):
            return (nil, ChartEasternTime.CalendarDay(year: day.year, month: day.month, day: day.day))
        case let .businessDayString(raw):
            let parsed = ChartEasternTime.parse(raw)
            return (parsed.instant, parsed.calendarDay)
        }
    }

    private static func easternTickMark(_ params: TickMarkFormatterParameters) -> String {
        let parsed = parsedTime(params.time)
        return ChartEasternTime.tickLabel(
            utc: parsed.utc,
            calendarDay: parsed.calendarDay,
            kind: tickKind(params.tickMarkType)
        )
    }

    private static func easternCrosshairTime(_ time: EventTime) -> String {
        let parsed = parsedTime(time)
        return ChartEasternTime.crosshairLabel(utc: parsed.utc, calendarDay: parsed.calendarDay)
    }

    private static func tickKind(_ type: TickMarkType) -> ChartEasternTime.TickKind {
        switch type {
        case .year:
            return .year
        case .month:
            return .month
        case .dayOfMonth:
            return .dayOfMonth
        case .time:
            return .time
        case .timeWithSeconds:
            return .timeWithSeconds
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

    /// Native WKWebView bounce would fight the enclosing page scroll.
    private static func installVerticalPageScrollBridge(on chart: LightweightCharts) {
        guard let webView = webView(in: chart) else { return }
        webView.scrollView.bounces = false
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

    private static func candlestickData(_ bar: Bar, usesCalendarDays: Bool) -> CandlestickData {
        CandlestickData(
            time: libraryTime(bar.time, usesCalendarDays: usesCalendarDays),
            open: bar.open,
            high: bar.high,
            low: bar.low,
            close: bar.close
        )
    }

    private static func lineData(_ bar: Bar, usesCalendarDays: Bool) -> LineData {
        LineData(time: libraryTime(bar.time, usesCalendarDays: usesCalendarDays), value: bar.close)
    }

    static func libraryTime(_ date: Date, usesCalendarDays: Bool) -> Time {
        if usesCalendarDays, let day = ChartEasternTime.calendarDay(for: date) {
            return .businessDay(BusinessDay(year: day.year, month: day.month, day: day.day))
        }
        return .utc(timestamp: date.timeIntervalSince1970)
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
            time: Self.libraryTime(marker.time, usesCalendarDays: false),
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
