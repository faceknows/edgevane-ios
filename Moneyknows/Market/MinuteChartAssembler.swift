import Foundation

enum MinuteChartAssembler {
    static func model(
        bars1m: [Bar],
        interval: MinuteInterval,
        style: ChartStyle,
        showVWAP: Bool,
        previousClose: Double?,
        sessionOpen: Double?,
        markers: [ChartMarker] = [],
        showVolume: Bool = false,
        seriesID: String = ""
    ) -> ChartModel {
        let bars = BarAggregator.aggregate(bars1m, minutes: interval.minutes)
        var overlays: [OverlayLine] = []
        if showVWAP, !bars.isEmpty {
            overlays.append(OverlayLine(
                id: "vwap",
                points: VWAP.series(from: bars),
                colorToken: .vwap,
                width: 1
            ))
        }
        var priceLines: [ChartModel.PriceLine] = []
        if let previousClose, previousClose.isFinite {
            priceLines.append(ChartModel.PriceLine(
                id: "prevClose",
                price: previousClose,
                title: L10n.Chart.prevClose,
                dashed: true,
                colorToken: .prevClose
            ))
        }
        if let sessionOpen, sessionOpen.isFinite {
            priceLines.append(ChartModel.PriceLine(
                id: "sessionOpen",
                price: sessionOpen,
                title: L10n.Chart.sessionOpen,
                dashed: true,
                colorToken: .sessionOpen
            ))
        }
        return ChartModel(
            bars: bars,
            style: style,
            overlays: overlays,
            priceLines: priceLines,
            markers: aligned(markers, to: bars, duration: TimeInterval(interval.minutes * 60)),
            showVolume: showVolume,
            usesCalendarDays: false,
            seriesID: seriesID
        )
    }

    static func extendedHours(
        bars1m: [Bar],
        markers: [ChartMarker] = [],
        showVolume: Bool = true,
        seriesID: String = ""
    ) -> ChartModel {
        model(
            bars1m: bars1m,
            interval: .five,
            style: .candle,
            showVWAP: false,
            previousClose: nil,
            sessionOpen: nil,
            markers: markers,
            showVolume: showVolume,
            seriesID: seriesID
        )
    }

    /// Snap marker time onto a bar so the fill sits on that candle; keep the fill price.
    private static func aligned(_ markers: [ChartMarker], to bars: [Bar], duration: TimeInterval) -> [ChartMarker] {
        guard !bars.isEmpty else { return [] }
        return markers.compactMap { marker in
            guard let bar = ChartHitTesting.containingBar(in: bars, at: marker.time, duration: duration) else {
                return nil
            }
            var next = marker
            next.time = bar.time
            return next
        }
    }
}

enum DailyChartAssembler {
    static func model(bars: [Bar], style: ChartStyle, showVolume: Bool, seriesID: String = "") -> ChartModel {
        ChartModel(
            bars: bars,
            style: style,
            overlays: [],
            priceLines: [],
            markers: [],
            showVolume: showVolume,
            usesCalendarDays: true,
            seriesID: seriesID
        )
    }
}
