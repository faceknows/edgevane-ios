import Foundation

enum SecondChartAssembler {
    static func model(
        bars1s: [Bar],
        interval: SecondInterval,
        style: ChartStyle,
        showVolume: Bool = true,
        seriesID: String = ""
    ) -> ChartModel {
        ChartModel(
            bars: BarAggregator.aggregate(bars1s, seconds: interval.seconds),
            style: style,
            overlays: [],
            priceLines: [],
            markers: [],
            showVolume: showVolume,
            usesCalendarDays: false,
            seriesID: seriesID
        )
    }
}
