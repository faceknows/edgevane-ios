import SwiftUI
import LightweightCharts

struct LightweightChartView: UIViewRepresentable {
    var model: ChartModel
    var colors: ChartColors
    var onEvent: (ChartEvent) -> Void

    func makeCoordinator() -> LightweightChartCoordinator {
        LightweightChartCoordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> LightweightCharts {
        let chart = LightweightCharts(options: context.coordinator.chartOptions(colors))
        chart.loadDelegate = context.coordinator
        chart.delegate = context.coordinator
        context.coordinator.chart = chart
        context.coordinator.onEvent = onEvent
        context.coordinator.pending = LightweightChartSnapshot(model: model, colors: colors)
        return chart
    }

    func updateUIView(_ uiView: LightweightCharts, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.applyIfNeeded(model, colors: colors, on: uiView)
    }
}
