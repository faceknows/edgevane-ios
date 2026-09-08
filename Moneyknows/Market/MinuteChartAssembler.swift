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
        followLatest: Bool = false,
        showVolume: Bool = false
    ) -> ChartModel {
        let bars = BarAggregator.aggregate(bars1m, minutes: interval.minutes)
        var overlays: [OverlayLine] = []
        if showVWAP, !bars1m.isEmpty {
            overlays.append(OverlayLine(
                id: "vwap",
                points: VWAP.series(from: bars1m),
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
            followLatest: followLatest,
            showVolume: showVolume
        )
    }

    static func extendedHours(bars1m: [Bar], markers: [ChartMarker] = [], showVolume: Bool = true) -> ChartModel {
        model(
            bars1m: bars1m,
            interval: .five,
            style: .candle,
            showVWAP: false,
            previousClose: nil,
            sessionOpen: nil,
            markers: markers,
            followLatest: false,
            showVolume: showVolume
        )
    }

    /// Lightweight Charts only draws a marker when `time` matches a bar.
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
