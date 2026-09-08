import SwiftUI
import LightweightCharts

struct LightweightChartView: UIViewRepresentable {
    var model: ChartModel
    var colors: ChartColors
    var volumeHeight: CGFloat?
    var chartHeight: CGFloat
    var onEvent: (ChartEvent) -> Void

    func makeCoordinator() -> LightweightChartCoordinator {
        LightweightChartCoordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> LightweightCharts {
        let chart = LightweightCharts(options: context.coordinator.bootstrapOptions(colors))
        chart.loadDelegate = context.coordinator
        chart.delegate = context.coordinator
        context.coordinator.chart = chart
        context.coordinator.onEvent = onEvent
        context.coordinator.pending = LightweightChartSnapshot(
            model: model,
            colors: colors,
            volumeHeight: volumeHeight,
            chartHeight: chartHeight
        )
        return chart
    }

    func updateUIView(_ uiView: LightweightCharts, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.applyIfNeeded(
            model,
            colors: colors,
            volumeHeight: volumeHeight,
            chartHeight: chartHeight,
            on: uiView
        )
    }
}
