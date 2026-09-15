import UIKit
import WebKit
import LightweightCharts

struct LightweightChartSnapshot: Equatable {
    var model: ChartModel
    var colors: ChartColors
    var volumeHeight: CGFloat?
    var chartHeight: CGFloat
    var visibleTimeRange: ChartVisibleTimeRange?
    var publishesVisibleTimeRange: Bool
    var allowsTimeScaleInteraction: Bool
    var barDuration: TimeInterval?

    func hasSameDrawnData(as other: LightweightChartSnapshot) -> Bool {
        model == other.model
            && colors == other.colors
            && volumeHeight == other.volumeHeight
            && chartHeight == other.chartHeight
            && allowsTimeScaleInteraction == other.allowsTimeScaleInteraction
    }
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
    private var markerSeries: [String: LineSeries] = [:]
    private var volumeSeries: HistogramSeries?
    private var libraryPriceLines: [PriceLine] = []
    private var appliedBars: [Bar] = []
    private var appliedMarkers: [ChartMarker] = []
    private var appliedPricePrecision = 2
    private var didFitContent = false
    private var hasTimeScaleSize = false
    private var paging = ChartTimeScalePaging.State()
    private var oldestBarTime: Date?
    private var timeScaleAPI: TimeScaleApi?
    private var didInstallFormatters = false
    private var appliedTimeRange: ChartVisibleTimeRange?
    private var suppressTimeRangeUntil: Date?
    private var customMaxLogicalTo: Double?
    private var isClampingLogicalRange = false

    init(onEvent: @escaping (ChartEvent) -> Void) {
        self.onEvent = onEvent
    }

    func lightweightChartsDidLoad(_ lightweightCharts: LightweightCharts) {
        Self.installHoveredObjectIdBridge(on: lightweightCharts)
        Self.installFillCaretBridge(on: lightweightCharts)
        Self.installVisibleChromeBridge(on: lightweightCharts)
        Self.installVerticalPageScrollBridge(on: lightweightCharts)
        isLoaded = true
        lightweightCharts.subscribeCrosshairMove()
        lightweightCharts.subscribeClick()
        let scale = lightweightCharts.timeScale()
        scale.delegate = self
        scale.subscribeVisibleLogicalRangeChange()
        scale.subscribeVisibleTimeRangeChange()
        scale.subscribeSizeChange()
        timeScaleAPI = scale
        notePlotSize(width: lightweightCharts.bounds.width, height: lightweightCharts.bounds.height)
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
        visibleTimeRange: ChartVisibleTimeRange?,
        publishesVisibleTimeRange: Bool,
        allowsTimeScaleInteraction: Bool,
        barDuration: TimeInterval?,
        on chart: LightweightCharts
    ) {
        let snapshot = LightweightChartSnapshot(
            model: model,
            colors: colors,
            volumeHeight: volumeHeight,
            chartHeight: chartHeight,
            visibleTimeRange: visibleTimeRange,
            publishesVisibleTimeRange: publishesVisibleTimeRange,
            allowsTimeScaleInteraction: allowsTimeScaleInteraction,
            barDuration: barDuration
        )
        pending = snapshot
        guard isLoaded else { return }
        if !hasTimeScaleSize {
            notePlotSize(width: chart.bounds.width, height: chart.bounds.height)
        }
        guard applied != snapshot else { return }
        if let applied, applied.hasSameDrawnData(as: snapshot) {
            let durationChanged = applied.barDuration != snapshot.barDuration
            self.applied = snapshot
            applyViewport(dataChanged: durationChanged)
            requestVisibleExtremes()
            return
        }
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

    func didVisibleTimeRangeChange(onTimeScale _: TimeScaleApi, parameters _: TimeRange?) {
        // Library visible-time clips empty future to the last bar. Publish after
        // logical-range clamp via `publishVisibleTimeIfNeeded`.
    }

    func didVisibleLogicalRangeChange(onTimeScale timeScale: TimeScaleApi, parameters: LogicalRange?) {
        if clampLogicalRangeIfNeeded(on: timeScale, parameters: parameters) {
            return
        }
        applyVisibleExtremes(range: parameters)
        publishVisibleTimeIfNeeded(from: parameters)
        if ChartTimeScalePaging.handleLogicalRange(
            from: parameters?.from,
            hasBars: !appliedBars.isEmpty,
            state: &paging
        ) {
            onEvent(.reachedOldest)
            applyTimeScaleEdges(on: timeScale)
        }
    }

    func didReceiveTimeScaleSizeChangeWithParameters(onTimeScale timeScale: TimeScaleApi, parameters: Rectangle?) {
        guard let parameters else { return }
        notePlotSize(width: CGFloat(parameters.width), height: CGFloat(parameters.height))
        requestVisibleExtremes()
    }

    func resetViewport() {
        guard applied?.allowsTimeScaleInteraction != false else { return }
        guard let chart, !appliedBars.isEmpty else { return }
        appliedTimeRange = nil
        customMaxLogicalTo = nil
        applyTimeScaleEdges(on: chart.timeScale())
        fitAllContent(on: chart)
    }

    func bootstrapOptions(_ colors: ChartColors) -> ChartOptions {
        chartOptions(colors, includeFormatters: false, lockLeftEdge: false)
    }

    private func chartOptions(
        _ colors: ChartColors,
        includeFormatters: Bool,
        lockLeftEdge: Bool,
        volumeHeight: CGFloat? = nil,
        chartHeight: CGFloat = 0,
        timeVisible: Bool = true,
        allowsTimeScaleInteraction: Bool = true
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
                fixRightEdge: ChartTimeScalePaging.fixesRightEdge(
                    allowsTimeScaleInteraction: allowsTimeScaleInteraction,
                    hasCustomRightBound: customMaxLogicalTo != nil
                ),
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
                mouseWheel: allowsTimeScaleInteraction,
                pressedMouseMove: allowsTimeScaleInteraction,
                horzTouchDrag: ChartTouchScrolling.horzTouchDrag(
                    allowsTimeScaleInteraction: allowsTimeScaleInteraction
                ),
                vertTouchDrag: ChartTouchScrolling.verticalTouchDrag
            )),
            handleScale: .options(HandleScaleOptions(
                mouseWheel: allowsTimeScaleInteraction,
                pinch: ChartTouchScrolling.pinch(allowsTimeScaleInteraction: allowsTimeScaleInteraction),
                axisPressedMouseMove: .options(AxisPressedMouseMoveOptions(
                    time: allowsTimeScaleInteraction,
                    price: false
                )),
                axisDoubleClickReset: .options(AxisDoubleClickOptions(
                    time: allowsTimeScaleInteraction,
                    price: false
                ))
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
            timeVisible: !model.usesCalendarDays,
            allowsTimeScaleInteraction: snapshot.allowsTimeScaleInteraction
        ))
        if attachFormatters {
            didInstallFormatters = true
        }
        if model.bars.isEmpty {
            clear(on: chart)
            rememberBars([])
            didFitContent = false
            appliedTimeRange = nil
            customMaxLogicalTo = nil
            ChartTimeScalePaging.reset(&paging)
            return
        }
        rememberBars(model.bars)
        rebuildMainIfNeeded(model.style, colors: colors, on: chart)
        guard let main = mainSeries else { return }
        applyMainOptions(colors)
        let markers = ChartHitTesting.sorted(model.markers)
        appliedMarkers = markers
        switch model.style {
        case .candle:
            if let series = main.series as? CandlestickSeries {
                series.setData(data: model.bars.map { Self.candlestickData($0, usesCalendarDays: model.usesCalendarDays) })
                applyPriceLines(model.priceLines, colors: colors, on: series)
            }
        case .line:
            if let series = main.series as? LineSeries {
                series.setData(data: model.bars.map { Self.lineData($0, usesCalendarDays: model.usesCalendarDays) })
                applyPriceLines(model.priceLines, colors: colors, on: series)
            }
        }
        syncOverlays(model.overlays, colors: colors, on: chart)
        syncVolume(model, colors: colors, on: chart)
        syncFillDots(markers, colors: colors, usesCalendarDays: model.usesCalendarDays, on: chart)
        applyVolumeLayout(volumeHeight: snapshot.volumeHeight, chartHeight: snapshot.chartHeight)
        capturePlotSizeIfNeeded(from: chart)
        applyViewport(dataChanged: true)
        if model.followLatest {
            chart.timeScale().scrollToRealTime()
        }
        requestVisibleExtremes()
    }

    private func capturePlotSizeIfNeeded(from chart: LightweightCharts) {
        guard !hasTimeScaleSize else { return }
        notePlotSize(width: chart.bounds.width, height: chart.bounds.height)
    }

    private func notePlotSize(width: CGFloat, height: CGFloat) {
        let apply = { [weak self] in
            guard let self else { return }
            guard ChartViewportReset.hasUsablePlotSize(width: width, height: height) else { return }
            self.hasTimeScaleSize = true
            self.applyViewport(dataChanged: false)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func applyViewport(dataChanged: Bool) {
        if restoreLinkedTimeRangeIfNeeded(force: dataChanged) { return }
        customMaxLogicalTo = nil
        if dataChanged {
            didFitContent = false
            appliedTimeRange = nil
        } else if let range = applied?.visibleTimeRange,
                  !ChartVisibleTimeRangeSync.intersects(range, bars: appliedBars) {
            didFitContent = false
            appliedTimeRange = nil
        }
        fitAllContentIfNeeded()
    }

    private func restoreLinkedTimeRangeIfNeeded(force: Bool) -> Bool {
        guard let chart, hasTimeScaleSize, !appliedBars.isEmpty else { return false }
        guard let range = applied?.visibleTimeRange,
              let duration = applied?.barDuration,
              let logical = ChartVisibleTimeRangeSync.logicalRange(
                for: range,
                in: appliedBars,
                barDuration: duration
              )
        else { return false }
        if ChartVisibleTimeRangeSync.shouldRestore(
            current: appliedTimeRange,
            target: range,
            dataChanged: force
        ) {
            suppressTimeRangeUntil = Date().addingTimeInterval(ChartVisibleTimeRangeSync.restoreSettleInterval)
            let scale = chart.timeScale()
            customMaxLogicalTo = ChartVisibleTimeRangeSync.customMaxLogicalTo(
                to: logical.to,
                barCount: appliedBars.count
            )
            applyTimeScaleEdges(on: scale, restoringSyncedRange: true)
            scale.setVisibleLogicalRange(
                range: LogicalRange(from: logical.from, to: logical.to)
            )
            applyTimeScaleEdges(on: scale)
            appliedTimeRange = range
        }
        didFitContent = true
        return true
    }

    private func applyTimeScaleEdges(
        on timeScale: TimeScaleApi,
        restoringSyncedRange: Bool = false
    ) {
        timeScale.applyOptions(options: TimeScaleOptions(
            fixLeftEdge: ChartTimeScalePaging.locksLeftEdge(paging),
            fixRightEdge: ChartTimeScalePaging.fixesRightEdge(
                allowsTimeScaleInteraction: applied?.allowsTimeScaleInteraction ?? true,
                hasCustomRightBound: customMaxLogicalTo != nil,
                restoringSyncedRange: restoringSyncedRange
            )
        ))
    }

    private func clampLogicalRangeIfNeeded(
        on timeScale: TimeScaleApi,
        parameters: LogicalRange?
    ) -> Bool {
        guard !isClampingLogicalRange else { return false }
        guard applied?.allowsTimeScaleInteraction == true else { return false }
        guard let maxTo = customMaxLogicalTo,
              let from = parameters?.from,
              let to = parameters?.to,
              let clamped = ChartVisibleTimeRangeSync.clampedLogicalRange(
                from: from,
                to: to,
                maxTo: maxTo
              )
        else { return false }
        isClampingLogicalRange = true
        let clampedRange = LogicalRange(from: clamped.from, to: clamped.to)
        timeScale.setVisibleLogicalRange(range: clampedRange)
        isClampingLogicalRange = false
        applyVisibleExtremes(range: clampedRange)
        publishVisibleTimeIfNeeded(from: clampedRange)
        return true
    }

    private func publishVisibleTimeIfNeeded(from parameters: LogicalRange?) {
        if let until = suppressTimeRangeUntil, Date() < until {
            return
        }
        suppressTimeRangeUntil = nil
        guard applied?.publishesVisibleTimeRange == true else { return }
        guard let from = parameters?.from, let to = parameters?.to,
              let duration = applied?.barDuration,
              let range = ChartVisibleTimeRangeSync.visibleTimeRange(
                from: from,
                to: to,
                in: appliedBars,
                duration: duration
              )
        else { return }
        guard ChartVisibleTimeRangeSync.shouldPublish(applied: appliedTimeRange, observed: range) else {
            return
        }
        appliedTimeRange = range
        onEvent(.visibleTimeRange(range))
    }

    private func fitAllContentIfNeeded() {
        guard let chart else { return }
        guard ChartViewportReset.shouldFitOnFirstLayout(
            didFit: didFitContent,
            hasBars: !appliedBars.isEmpty,
            hasSize: hasTimeScaleSize
        ) else { return }
        fitAllContent(on: chart)
    }

    private func fitAllContent(on chart: LightweightCharts) {
        ChartTimeScalePaging.beginIgnoringFitContent(&paging)
        applyPriceScale(PriceScaleOptions(autoScale: true), to: mainSeries?.series)
        volumeSeries?.priceScale().applyOptions(options: PriceScaleOptions(autoScale: true))
        chart.timeScale().fitContent()
        didFitContent = true
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
            mainSeries = (style, chart.addLineSeries(options: lineOptions(colors.up, isMain: true)))
        }
        rememberMainSeriesJS()
    }

    private func applyMainOptions(_ colors: ChartColors) {
        switch mainSeries?.style {
        case .candle:
            (mainSeries?.series as? CandlestickSeries)?.applyOptions(options: candlestickOptions(colors))
        case .line:
            (mainSeries?.series as? LineSeries)?.applyOptions(options: lineOptions(colors.up, isMain: true))
        case .none:
            break
        }
    }

    private func candlestickOptions(_ colors: ChartColors) -> CandlestickSeriesOptions {
        CandlestickSeriesOptions(
            lastValueVisible: false,
            priceLineVisible: false,
            priceFormat: seriesPriceFormat(),
            upColor: chartColor(colors.up),
            downColor: chartColor(colors.down),
            borderVisible: false,
            wickUpColor: chartColor(colors.up),
            wickDownColor: chartColor(colors.down)
        )
    }

    private func lineOptions(_ color: ChartRGBA, width: Double = 1, isMain: Bool = false) -> LineSeriesOptions {
        LineSeriesOptions(
            lastValueVisible: false,
            priceLineVisible: false,
            priceFormat: isMain ? seriesPriceFormat() : nil,
            color: chartColor(color),
            lineWidth: lineWidth(width)
        )
    }

    private func seriesPriceFormat() -> PriceFormat {
        .builtIn(BuiltInPriceFormat(
            type: .price,
            precision: Double(appliedPricePrecision),
            minMove: pow(10, -Double(appliedPricePrecision))
        ))
    }

    private func rememberBars(_ bars: [Bar]) {
        appliedBars = bars
        appliedPricePrecision = ChartVisibleExtremes.fractionDigits(in: bars)
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

    private func syncFillDots(
        _ markers: [ChartMarker],
        colors: ChartColors,
        usesCalendarDays: Bool,
        on chart: LightweightCharts
    ) {
        let ids = Set(markers.map(\.id))
        for (id, series) in markerSeries where !ids.contains(id) {
            chart.removeSeries(seriesApi: series)
            markerSeries[id] = nil
        }
        let options = fillDotSeriesOptions()
        for (index, marker) in markers.enumerated() {
            let series: LineSeries
            if let existing = markerSeries[marker.id] {
                series = existing
                series.applyOptions(options: options)
            } else {
                series = chart.addLineSeries(options: options)
                markerSeries[marker.id] = series
            }
            let time = Self.libraryTime(marker.time, usesCalendarDays: usesCalendarDays)
            series.setData(data: [LineData(time: time, value: marker.price)])
            series.setMarkers(data: [
                Self.marker(marker, colors: colors, libraryID: ChartHitTesting.libraryID(index: index), usesCalendarDays: usesCalendarDays)
            ])
        }
    }

    private func fillDotSeriesOptions() -> LineSeriesOptions {
        LineSeriesOptions(
            lastValueVisible: false,
            priceLineVisible: false,
            color: chartColor(ChartRGBA(red: 0, green: 0, blue: 0, alpha: 0)),
            lineWidth: .one,
            crosshairMarkerVisible: false,
            lastPriceAnimation: .disabled
        )
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

    private func requestVisibleExtremes() {
        timeScaleAPI?.getVisibleLogicalRange { [weak self] range in
            self?.applyVisibleExtremes(range: range)
        }
    }

    private func applyVisibleExtremes(range: LogicalRange?) {
        let labels = ChartVisibleExtremes.labels(
            in: appliedBars,
            from: range?.from,
            to: range?.to,
            style: mainSeries?.style ?? .candle
        )
        drawVisibleChrome(labels, range: range)
    }

    private func rememberMainSeriesJS() {
        evaluate("""
        if (typeof seriesArray !== 'undefined' && seriesArray.length) {
          window.__mkMainSeries = seriesArray[seriesArray.length - 1].series;
        }
        """)
    }

    private func drawVisibleChrome(_ labels: ChartVisibleExtremes.Labels?, range: LogicalRange?) {
        guard let labels,
              let colors = applied?.colors,
              appliedBars.indices.contains(labels.highIndex),
              appliedBars.indices.contains(labels.lowIndex),
              appliedBars.indices.contains(labels.lastIndex)
        else {
            evaluate("if (window.__mkDrawVisibleChrome) window.__mkDrawVisibleChrome(null);")
            return
        }
        let usesCalendarDays = applied?.model.usesCalendarDays ?? false
        let from = range?.from ?? Double(labels.highIndex)
        let to = range?.to ?? Double(labels.lastIndex)
        let precision = appliedPricePrecision
        let highLeft = ChartVisibleExtremes.isOnLeftHalf(index: labels.highIndex, from: from, to: to)
        let lowLeft = ChartVisibleExtremes.isOnLeftHalf(index: labels.lowIndex, from: from, to: to)
        let highText = ChartVisibleExtremes.extremeCaption(
            price: ChartVisibleExtremes.priceText(labels.high, precision: precision),
            onLeftHalf: highLeft
        )
        let showLow = labels.highIndex != labels.lowIndex || labels.high != labels.low
        let lowText = ChartVisibleExtremes.extremeCaption(
            price: ChartVisibleExtremes.priceText(labels.low, precision: precision),
            onLeftHalf: lowLeft
        )
        let lastText = ChartVisibleExtremes.priceText(labels.last, precision: precision)
        let lastT = Self.jsTime(Self.libraryTime(appliedBars[labels.lastIndex].time, usesCalendarDays: usesCalendarDays))
        let highT = Self.jsTime(Self.libraryTime(appliedBars[labels.highIndex].time, usesCalendarDays: usesCalendarDays))
        let lowT = Self.jsTime(Self.libraryTime(appliedBars[labels.lowIndex].time, usesCalendarDays: usesCalendarDays))
        let lowJSON = showLow
            ? "{\"t\":\(lowT),\"p\":\(labels.low),\"text\":\(Self.jsString(lowText)),\"left\":\(lowLeft ? "true" : "false")}"
            : "null"
        evaluate("""
        if (window.__mkDrawVisibleChrome) window.__mkDrawVisibleChrome({
          last:{t:\(lastT),p:\(labels.last),text:\(Self.jsString(lastText))},
          high:{t:\(highT),p:\(labels.high),text:\(Self.jsString(highText)),left:\(highLeft ? "true" : "false")},
          low:\(lowJSON),
          line:\(Self.jsString(Self.cssColor(colors.buy))),
          text:\(Self.jsString(Self.cssColor(colors.text))),
          background:\(Self.jsString(Self.cssColor(colors.background)))
        });
        """)
    }

    private func evaluate(_ script: String) {
        guard let chart else { return }
        Self.webView(in: chart)?.evaluateJavaScript(script, completionHandler: nil)
    }

    private static func jsTime(_ time: Time) -> String {
        switch time {
        case let .utc(timestamp):
            return String(timestamp)
        case let .businessDay(day):
            return "{\"year\":\(day.year),\"month\":\(day.month),\"day\":\(day.day)}"
        case let .string(raw):
            return jsString(raw)
        }
    }

    private static func jsString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func cssColor(_ rgba: ChartRGBA) -> String {
        let red = Int((rgba.red * 255).rounded())
        let green = Int((rgba.green * 255).rounded())
        let blue = Int((rgba.blue * 255).rounded())
        return "rgba(\(red),\(green),\(blue),\(rgba.alpha))"
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
        for series in markerSeries.values {
            chart.removeSeries(seriesApi: series)
        }
        markerSeries = [:]
        if let series = volumeSeries {
            chart.removeSeries(seriesApi: series)
            volumeSeries = nil
        }
        libraryPriceLines = []
        appliedMarkers = []
        evaluate("if (window.__mkDrawVisibleChrome) window.__mkDrawVisibleChrome(null);")
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

    /// Native WKWebView scrolling would nest inside the page `ScrollView` and swallow later vertical pans.
    /// The plot still pans from JavaScript touch handlers, not the web view's `UIScrollView`.
    func refreshWebViewScrollBridge(on chart: LightweightCharts) {
        Self.installVerticalPageScrollBridge(on: chart)
    }

    private static func installVerticalPageScrollBridge(on chart: LightweightCharts) {
        guard let webView = webView(in: chart) else { return }
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.panGestureRecognizer.isEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.bouncesZoom = false
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.canCancelContentTouches = false
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        disableDoubleTapZoom(on: webView)
        disableDoubleTapZoom(on: webView.scrollView)
    }

    private static func disableDoubleTapZoom(on view: UIView) {
        for recognizer in view.gestureRecognizers ?? [] {
            if let tap = recognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 {
                tap.isEnabled = false
            }
        }
    }

    /// Library `arrowUp` / `arrowDown` are filled arrows. Stroke thin ∧ / ∨ instead.
    private static func installFillCaretBridge(on chart: LightweightCharts) {
        guard let webView = webView(in: chart) else { return }
        webView.evaluateJavaScript(#"""
        (function() {
          if (window.__mkFillCaretBridge) { return; }
          window.__mkFillCaretBridge = true;
          var orig = CanvasRenderingContext2D.prototype.fillText;
          CanvasRenderingContext2D.prototype.fillText = function(text, x, y, maxWidth) {
            if (text === '∧' || text === '∨') {
              var width = this.measureText(text).width;
              var fontSize = 11;
              var match = /(\d+(?:\.\d+)?)px/.exec(this.font);
              if (match) { fontSize = parseFloat(match[1]); }
              var cx = x + width / 2;
              var cy = y - 0.6 * fontSize - 3;
              var arm = Math.max(4, fontSize * 0.45);
              this.save();
              this.strokeStyle = this.fillStyle;
              this.lineWidth = 1.25;
              this.lineCap = 'round';
              this.lineJoin = 'round';
              this.beginPath();
              if (text === '∧') {
                this.moveTo(cx - arm, cy + arm * 0.55);
                this.lineTo(cx, cy - arm * 0.55);
                this.lineTo(cx + arm, cy + arm * 0.55);
              } else {
                this.moveTo(cx - arm, cy - arm * 0.55);
                this.lineTo(cx, cy + arm * 0.55);
                this.lineTo(cx + arm, cy - arm * 0.55);
              }
              this.stroke();
              this.restore();
              return;
            }
            if (arguments.length < 4) { return orig.call(this, text, x, y); }
            return orig.call(this, text, x, y, maxWidth);
          };
        })();
        """#, completionHandler: nil)
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

    /// High/low and last-price chrome sit above the plot. Last close is a dashed stub,
    /// then the axis label is painted on top so the dash does not run through the digits.
    private static func installVisibleChromeBridge(on chart: LightweightCharts) {
        guard let webView = webView(in: chart) else { return }
        webView.evaluateJavaScript(#"""
        (function() {
          if (window.__mkVisibleChromeBridge) { return; }
          window.__mkVisibleChromeBridge = true;
          var overlay = document.createElement('canvas');
          overlay.style.position = 'absolute';
          overlay.style.left = '0';
          overlay.style.top = '0';
          overlay.style.width = '100%';
          overlay.style.height = '100%';
          overlay.style.pointerEvents = 'none';
          overlay.style.zIndex = '8';
          document.body.appendChild(overlay);
          window.__mkLastChromePayload = null;
          function mkChart() {
            for (var key in window) {
              if (typeof key !== 'string' || key.indexOf('chart') !== 0) { continue; }
              var value = window[key];
              if (value && typeof value.timeScale === 'function') { return value; }
            }
            return null;
          }
          function lastLineEndX(plotRight, canvasWidth) {
            return Math.max(plotRight, canvasWidth - \(ChartVisibleExtremes.lastLineEndInset));
          }
          function paint() {
            var payload = window.__mkLastChromePayload;
            var ratio = window.devicePixelRatio || 1;
            var width = overlay.clientWidth || document.body.clientWidth || 0;
            var height = overlay.clientHeight || document.body.clientHeight || 0;
            overlay.width = Math.max(1, Math.round(width * ratio));
            overlay.height = Math.max(1, Math.round(height * ratio));
            overlay.style.width = width + 'px';
            overlay.style.height = height + 'px';
            var ctx = overlay.getContext('2d');
            if (!ctx) { return; }
            ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
            ctx.clearRect(0, 0, width, height);
            if (!payload) { return; }
            var chart = mkChart();
            var series = window.__mkMainSeries;
            if (!chart || !series) { return; }
            var timeScale = chart.timeScale();
            function xOf(time) { return timeScale.timeToCoordinate(time); }
            function yOf(price) { return series.priceToCoordinate(price); }
            function drawMark(mark) {
              if (!mark) { return; }
              var x = xOf(mark.t);
              var y = yOf(mark.p);
              if (x == null || y == null) { return; }
              ctx.fillStyle = payload.text;
              ctx.font = '9px ui-monospace, Menlo, monospace';
              ctx.textBaseline = 'middle';
              ctx.textAlign = mark.left ? 'left' : 'right';
              ctx.fillText(mark.text, x, y);
            }
            var lastX = xOf(payload.last.t);
            var lastY = yOf(payload.last.p);
            var endX = lastLineEndX(timeScale.width(), width);
            if (lastX != null && lastY != null && endX - lastX > 1) {
              ctx.save();
              ctx.strokeStyle = payload.line;
              ctx.lineWidth = 1;
              ctx.setLineDash([4, 4]);
              ctx.beginPath();
              ctx.moveTo(lastX, lastY);
              ctx.lineTo(endX, lastY);
              ctx.stroke();
              ctx.restore();
            }
            drawMark(payload.high);
            drawMark(payload.low);
            if (lastX != null && lastY != null && payload.last.text) {
              ctx.font = '600 9px ui-monospace, Menlo, monospace';
              ctx.textAlign = 'right';
              ctx.textBaseline = 'middle';
              var label = payload.last.text;
              var metrics = ctx.measureText(label);
              var pad = 2;
              ctx.fillStyle = payload.background || 'rgba(0,0,0,0)';
              ctx.fillRect(endX - metrics.width - pad, lastY - 7, metrics.width + pad * 2, 14);
              ctx.fillStyle = payload.line;
              ctx.fillText(label, endX, lastY);
            }
          }
          window.__mkDrawVisibleChrome = function(payload) {
            window.__mkLastChromePayload = payload;
            paint();
          };
          window.addEventListener('resize', paint);
          var tries = 0;
          (function subscribe() {
            var chart = mkChart();
            if (chart && chart.timeScale) {
              chart.timeScale().subscribeVisibleLogicalRangeChange(paint);
              return;
            }
            if (tries++ < 20) { setTimeout(subscribe, 50); }
          })();
        })();
        """#, completionHandler: nil)
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

    private static func marker(
        _ marker: ChartMarker,
        colors: ChartColors,
        libraryID: String,
        usesCalendarDays: Bool
    ) -> SeriesMarker {
        let token: ChartColorToken = marker.kind == .buy ? .buy : (marker.kind == .sell ? .sell : .other)
        let glyph = Self.fillGlyph(marker.kind)
        return SeriesMarker(
            time: Self.libraryTime(marker.time, usesCalendarDays: usesCalendarDays),
            position: .inBar,
            shape: .circle,
            color: ChartColor(UIColor(
                red: CGFloat(colors.rgba(for: token).red),
                green: CGFloat(colors.rgba(for: token).green),
                blue: CGFloat(colors.rgba(for: token).blue),
                alpha: CGFloat(colors.rgba(for: token).alpha)
            )),
            id: libraryID,
            text: glyph,
            size: glyph == nil ? 1 : 0
        )
    }

    private static func fillGlyph(_ kind: ChartMarkerKind) -> String? {
        switch kind {
        case .buy: return "∨"
        case .sell: return "∧"
        case .other: return nil
        }
    }
}
