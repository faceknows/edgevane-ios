import Foundation

enum SecondChartAssembler {
    static func model(bars1s: [Bar], interval: SecondInterval, style: ChartStyle) -> ChartModel {
        ChartModel(
            bars: BarAggregator.aggregate(bars1s, seconds: interval.seconds),
            style: style,
            overlays: [],
            priceLines: [],
            markers: [],
            followLatest: true,
            showVolume: false
        )
    }
}
