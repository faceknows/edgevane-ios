import Charts
import SwiftUI

enum SparklineGeometry {
    static func points(values: [Double], in size: CGSize, inset: CGFloat = 2) -> [CGPoint] {
        let finite = values.filter { $0.isFinite }
        guard size.width > 0, size.height > 0, !finite.isEmpty else { return [] }
        let minX = inset
        let maxX = max(minX, size.width - inset)
        let minY = inset
        let maxY = max(minY, size.height - inset)
        guard maxX > minX, maxY > minY else { return [] }
        let low = finite.min() ?? 0
        let high = finite.max() ?? 0
        let span = high - low
        return finite.enumerated().map { index, value in
            let x: CGFloat
            if finite.count == 1 {
                x = (minX + maxX) / 2
            } else {
                x = minX + (maxX - minX) * CGFloat(index) / CGFloat(finite.count - 1)
            }
            let y: CGFloat
            if span == 0 {
                y = (minY + maxY) / 2
            } else {
                let t = (value - low) / span
                y = maxY - CGFloat(t) * (maxY - minY)
            }
            return CGPoint(x: x, y: y)
        }
    }

    static func delta(values: [Double], baseline: Double? = nil) -> Double? {
        let finite = values.filter { $0.isFinite }
        guard let last = finite.last else { return nil }
        if let baseline, baseline.isFinite {
            return last - baseline
        }
        guard let first = finite.first else { return nil }
        return last - first
    }

    static func chartXDomain(count: Int) -> ClosedRange<Double> {
        count <= 1 ? -1...1 : 0...Double(count - 1)
    }
}

struct SparklineView: View {
    var values: [Double]
    var color: Color
    var isLoading = false
    var errorText: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        let finite = values.filter(\.isFinite)
        return ZStack {
            if isLoading, finite.isEmpty {
                ProgressView()
                    .scaleEffect(0.75)
            } else if !finite.isEmpty {
                plotted(finite)
                    .opacity(errorText == nil ? 1 : 0.28)
                    .accessibilityHidden(true)
            }
            if let errorText {
                SparklineFailure(text: errorText, retry: retry)
            }
        }
        .accessibilityHidden(errorText == nil)
    }

    @ViewBuilder
    private func plotted(_ values: [Double]) -> some View {
        if #available(iOS 16.0, *) {
            chart(values)
        } else {
            canvas(values)
        }
    }

    @available(iOS 16.0, *)
    private func chart(_ values: [Double]) -> some View {
        let samples = values.enumerated().map { SparklineSample(id: $0.offset, value: $0.element) }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let pad = high == low ? max(abs(high) * 0.001, 0.01) : 0
        return Chart(samples) { sample in
            if values.count == 1 {
                PointMark(
                    x: .value("i", Double(sample.id)),
                    y: .value("v", sample.value)
                )
                .foregroundStyle(color)
                .symbolSize(9)
            } else {
                LineMark(
                    x: .value("i", Double(sample.id)),
                    y: .value("v", sample.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .interpolationMethod(.linear)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: SparklineGeometry.chartXDomain(count: values.count))
        .chartYScale(domain: (low - pad)...(high + pad))
    }

    private func canvas(_ values: [Double]) -> some View {
        Canvas { context, size in
            draw(values: values, color: color, in: &context, size: size)
        }
    }

    private func draw(values: [Double], color: Color, in context: inout GraphicsContext, size: CGSize) {
        let points = SparklineGeometry.points(values: values, in: size)
        guard let first = points.first else { return }
        if points.count == 1 {
            let dot = Path(ellipseIn: CGRect(x: first.x - 1.5, y: first.y - 1.5, width: 3, height: 3))
            context.fill(dot, with: .color(color))
            return
        }
        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() {
            line.addLine(to: point)
        }
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }
}

struct SparklineFailure: View {
    var text: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            if let retry {
                Button(L10n.Common.retry, action: retry)
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct SparklineSample: Identifiable {
    var id: Int
    var value: Double
}
