import SwiftUI
import UIKit
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
        context.coordinator.pageScrollPassthrough.install(on: chart)
        return chart
    }

    func updateUIView(_ uiView: LightweightCharts, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.pageScrollPassthrough.install(on: uiView)
        context.coordinator.applyIfNeeded(
            model,
            colors: colors,
            volumeHeight: volumeHeight,
            chartHeight: chartHeight,
            on: uiView
        )
    }
}

/// Vertical pans cancel the WebView and go to the page. Horizontal pans stay on the chart.
final class ChartPageScrollPassthrough: NSObject, UIGestureRecognizerDelegate {
    private let chartPan = ChartDirectionLockGesture(ownsPan: { ChartTouchScrolling.chartOwnsPan(translationX: $0, translationY: $1) })
    private let pagePan = ChartDirectionLockGesture(ownsPan: { !ChartTouchScrolling.chartOwnsPan(translationX: $0, translationY: $1) })
    private let windowHook = ChartWindowHookView()
    private weak var installedOn: UIView?
    private weak var boundScroll: UIScrollView?

    override init() {
        super.init()
        chartPan.cancelsTouchesInView = false
        chartPan.delegate = self
        pagePan.cancelsTouchesInView = true
        pagePan.delegate = self
        windowHook.isUserInteractionEnabled = false
    }

    func install(on view: UIView) {
        if installedOn !== view {
            installedOn?.removeGestureRecognizer(chartPan)
            installedOn?.removeGestureRecognizer(pagePan)
            windowHook.removeFromSuperview()
            view.addGestureRecognizer(chartPan)
            view.addGestureRecognizer(pagePan)
            view.insertSubview(windowHook, at: 0)
            installedOn = view
        }
        windowHook.onMovedToWindow = { [weak self, weak view] in
            guard let self, let view else { return }
            self.bindEnclosingScrollView(from: view)
        }
        bindEnclosingScrollView(from: view)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === pagePan
            && other is UIPanGestureRecognizer
            && other.view is UIScrollView
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === chartPan
            && other is UIPanGestureRecognizer
            && other.view is UIScrollView
    }

    private func bindEnclosingScrollView(from view: UIView) {
        var ancestor: UIView? = view.superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                if boundScroll !== scroll {
                    scroll.panGestureRecognizer.require(toFail: chartPan)
                    boundScroll = scroll
                }
                return
            }
            ancestor = current.superview
        }
    }
}

private final class ChartWindowHookView: UIView {
    var onMovedToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMovedToWindow?()
    }
}

private final class ChartDirectionLockGesture: UIGestureRecognizer {
    private let ownsPan: (Double, Double) -> Bool
    private var origin: CGPoint = .zero

    init(ownsPan: @escaping (Double, Double) -> Bool) {
        self.ownsPan = ownsPan
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if numberOfTouches > 1 {
            return
        }
        guard touches.count == 1, let touch = touches.first else {
            state = .failed
            return
        }
        origin = touch.location(in: view)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if numberOfTouches > 1 {
            return
        }
        if state == .began || state == .changed {
            state = .changed
            return
        }
        guard state == .possible, let touch = touches.first else { return }
        let point = touch.location(in: view)
        let dx = Double(point.x - origin.x)
        let dy = Double(point.y - origin.y)
        guard ChartTouchScrolling.hasLockedDirection(translationX: dx, translationY: dy) else { return }
        state = ownsPan(dx, dy) ? .began : .failed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if numberOfTouches > 0 { return }
        if state == .began || state == .changed {
            state = .ended
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        origin = .zero
    }
}
