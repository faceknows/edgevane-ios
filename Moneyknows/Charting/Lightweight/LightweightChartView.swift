import SwiftUI
import UIKit
import LightweightCharts

struct LightweightChartView: UIViewRepresentable {
    var model: ChartModel
    var colors: ChartColors
    var volumeHeight: CGFloat?
    var chartHeight: CGFloat
    var visibleTimeRange: ChartVisibleTimeRange?
    var publishesVisibleTimeRange: Bool
    var allowsTimeScaleInteraction: Bool
    var barDuration: TimeInterval?
    var onEvent: (ChartEvent) -> Void

    func makeCoordinator() -> LightweightChartCoordinator {
        let coordinator = LightweightChartCoordinator(onEvent: onEvent)
        coordinator.pageScrollPassthrough.onDoubleTap = { [weak coordinator] in
            coordinator?.resetViewport()
        }
        return coordinator
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
            chartHeight: chartHeight,
            visibleTimeRange: visibleTimeRange,
            publishesVisibleTimeRange: publishesVisibleTimeRange,
            allowsTimeScaleInteraction: allowsTimeScaleInteraction,
            barDuration: barDuration
        )
        context.coordinator.pageScrollPassthrough.allowsTimeScaleInteraction = allowsTimeScaleInteraction
        context.coordinator.pageScrollPassthrough.install(on: chart)
        context.coordinator.refreshWebViewScrollBridge(on: chart)
        return chart
    }

    func updateUIView(_ uiView: LightweightCharts, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.pageScrollPassthrough.allowsTimeScaleInteraction = allowsTimeScaleInteraction
        context.coordinator.pageScrollPassthrough.install(on: uiView)
        context.coordinator.refreshWebViewScrollBridge(on: uiView)
        context.coordinator.applyIfNeeded(
            model,
            colors: colors,
            volumeHeight: volumeHeight,
            chartHeight: chartHeight,
            visibleTimeRange: visibleTimeRange,
            publishesVisibleTimeRange: publishesVisibleTimeRange,
            allowsTimeScaleInteraction: allowsTimeScaleInteraction,
            barDuration: barDuration,
            on: uiView
        )
    }
}

/// Vertical pans cancel the WebView and go to the page. Horizontal pans stay on the chart
/// when time-scale interaction is on; otherwise they do not move the plot.
final class ChartPageScrollPassthrough: NSObject, UIGestureRecognizerDelegate {
    var onDoubleTap: (() -> Void)?
    var allowsTimeScaleInteraction = true {
        didSet { resetTap.isEnabled = allowsTimeScaleInteraction }
    }
    private let chartPan = ChartDirectionLockGesture(ownsPan: { _, _ in false })
    private let pagePan = ChartDirectionLockGesture(ownsPan: { _, _ in true })
    private let resetTap = UITapGestureRecognizer()
    private let windowHook = ChartWindowHookView()
    private weak var installedOn: UIView?
    private weak var boundScroll: UIScrollView?

    override init() {
        super.init()
        chartPan.ownsPan = { [weak self] x, y in
            ChartTouchScrolling.chartOwnsPan(
                translationX: x,
                translationY: y,
                allowsTimeScaleInteraction: self?.allowsTimeScaleInteraction ?? true
            )
        }
        pagePan.ownsPan = { [weak self] x, y in
            !ChartTouchScrolling.chartOwnsPan(
                translationX: x,
                translationY: y,
                allowsTimeScaleInteraction: self?.allowsTimeScaleInteraction ?? true
            )
        }
        chartPan.cancelsTouchesInView = false
        chartPan.delegate = self
        chartPan.addTarget(self, action: #selector(handleChartPan))
        pagePan.cancelsTouchesInView = true
        pagePan.delaysTouchesBegan = true
        pagePan.delegate = self
        resetTap.numberOfTapsRequired = 2
        resetTap.cancelsTouchesInView = true
        resetTap.delegate = self
        resetTap.addTarget(self, action: #selector(handleDoubleTap))
        resetTap.isEnabled = allowsTimeScaleInteraction
        windowHook.isUserInteractionEnabled = false
    }

    @objc private func handleDoubleTap() {
        onDoubleTap?()
    }

    @objc private func handleChartPan(_ gesture: UIGestureRecognizer) {
        guard gesture.state == .began else { return }
        cancelEnclosingPageScroll()
    }

    func install(on view: UIView) {
        if installedOn !== view {
            installedOn?.removeGestureRecognizer(chartPan)
            installedOn?.removeGestureRecognizer(pagePan)
            installedOn?.removeGestureRecognizer(resetTap)
            windowHook.removeFromSuperview()
            view.addGestureRecognizer(chartPan)
            view.addGestureRecognizer(pagePan)
            view.addGestureRecognizer(resetTap)
            view.insertSubview(windowHook, at: 0)
            installedOn = view
        }
        resetTap.isEnabled = allowsTimeScaleInteraction
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
        if gestureRecognizer === resetTap {
            return !(other is UIPanGestureRecognizer)
        }
        guard ChartTouchScrolling.isPageScrollPan(other, enclosingScroll: boundScroll) else {
            return false
        }
        return gestureRecognizer === pagePan || gestureRecognizer === chartPan
    }

    private func bindEnclosingScrollView(from view: UIView) {
        var ancestor: UIView? = view.superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                boundScroll = scroll
                return
            }
            ancestor = current.superview
        }
    }

    /// `require(toFail: chartPan)` sticks after a successful horizontal pan and kills later page scrolls.
    private func cancelEnclosingPageScroll() {
        guard let pan = boundScroll?.panGestureRecognizer, pan.isEnabled else { return }
        pan.isEnabled = false
        pan.isEnabled = true
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
    var ownsPan: (Double, Double) -> Bool
    private var origin: CGPoint = .zero

    init(ownsPan: @escaping (Double, Double) -> Bool) {
        self.ownsPan = ownsPan
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
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
        super.touchesMoved(touches, with: event)
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
        super.touchesEnded(touches, with: event)
        if numberOfTouches > 0 { return }
        if state == .began || state == .changed {
            state = .ended
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }

    override func reset() {
        super.reset()
        origin = .zero
    }
}
