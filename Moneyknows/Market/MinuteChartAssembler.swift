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
            markers: markers,
            followLatest: followLatest,
            showVolume: showVolume
        )
    }
}
