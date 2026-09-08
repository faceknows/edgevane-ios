import Foundation

enum OrderSizing {
    static let sliderLockDuration: TimeInterval = 10
    static let minimumPriceDelta = 0.01

    /// SwiftUI `Slider(..., step:)` traps (`max stride must be positive`) when the
    /// range has no room for a positive step — a tight second-chart high/low, or a
    /// thumb sitting outside the bounds when the range updates.
    static func sliderStep(span: Double) -> Double {
        span > 20 ? 0.05 : 0.01
    }

    static func sliderBounds(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        guard range.lowerBound.isFinite, range.upperBound.isFinite else {
            return 0.99...1.01
        }
        var lower = min(range.lowerBound, range.upperBound)
        var upper = max(range.lowerBound, range.upperBound)
        if upper <= 0 {
            return 0.01...0.03
        }
        if lower < 0 {
            lower = 0
        }
        let minSpan = sliderStep(span: upper - lower) * 2
        if upper - lower < minSpan {
            let mid = (lower + upper) / 2
            lower = max(0, mid - minSpan / 2)
            upper = lower + minSpan
        }
        return lower...upper
    }

    static func clampSliderPrice(_ price: Double, in range: ClosedRange<Double>) -> Double {
        let bounds = sliderBounds(range)
        guard price.isFinite else {
            return (bounds.lowerBound + bounds.upperBound) / 2
        }
        return min(max(price, bounds.lowerBound), bounds.upperBound)
    }

    static let multipliers: [(label: String, value: Double)] = [
        ("1/3", 1.0 / 3.0),
        ("1/2", 0.5),
        ("1", 1),
        ("2", 2),
        ("3", 3),
    ]

    static func baseShares(valuePerTrade: Double, price: Double) -> Int {
        guard valuePerTrade.isFinite, valuePerTrade > 0, price.isFinite, price > 0 else {
            return 0
        }
        return max(Int(floor(valuePerTrade / price)), 1)
    }

    static func shares(valuePerTrade: Double, price: Double, multiplier: Double = 1) -> Int {
        let base = baseShares(valuePerTrade: valuePerTrade, price: price)
        guard base > 0, multiplier.isFinite, multiplier > 0 else { return 0 }
        return max(Int(floor(Double(base) * multiplier)), 1)
    }

    static func notional(quantity: Double, price: Double) -> Double? {
        guard quantity.isFinite, quantity > 0, price.isFinite, price > 0 else { return nil }
        return quantity * price
    }

    static func openExitOrders(symbol: String, positionSide: PositionSide, orders: [Order]) -> [Order] {
        let code = SymbolCode.normalize(symbol)
        let exitSide: OrderSide = positionSide == .short ? .buy : .sell
        return orders.filter { order in
            order.symbol == code && order.status.isOpen && order.side == exitSide
        }
    }

    static func availableExitQuantity(position: Position, openOrders: [Order]) -> Double {
        let reserved = openExitOrders(symbol: position.symbol, positionSide: position.side, orders: openOrders)
            .reduce(0.0) { total, order in
                if order.isProtectiveExit {
                    return total
                }
                return total + order.remainingQuantity
            }
        return max(0, position.quantity - reserved)
    }

    static func protectedExitQuantity(symbol: String, positionSide: PositionSide, orders: [Order]) -> Double {
        let open = openExitOrders(symbol: symbol, positionSide: positionSide, orders: orders)
            .filter(\.isProtectiveExit)
        var consumed: Set<String> = []
        var total = 0.0
        let grouped = Dictionary(grouping: open.filter(\.isOCOBracket)) { $0.ocoGroupId }
        for (_, group) in grouped {
            total += group.map(\.remainingQuantity).max() ?? 0
            group.forEach { consumed.insert($0.id) }
        }
        for order in open where !consumed.contains(order.id) {
            total += order.remainingQuantity
        }
        return total
    }

    static func tickSize(for price: Double) -> Double {
        price >= 1 ? 0.01 : 0.0001
    }

    static func roundPrice(_ price: Double) -> Double {
        guard price.isFinite, price > 0 else { return price }
        let tick = tickSize(for: price)
        let units = (price / tick).rounded()
        let rounded = units * tick
        let places = tick >= 0.01 ? 2.0 : 4.0
        let scale = pow(10, places)
        return (rounded * scale).rounded() / scale
    }

    static func exitPrice(cost: Double, percent: Double, side: PositionSide, takingProfit: Bool) -> Double? {
        guard cost.isFinite, cost > 0, percent.isFinite, percent > 0 else { return nil }
        let factor = percent / 100
        let raw: Double
        switch (side, takingProfit) {
        case (.long, true), (.short, false):
            raw = cost * (1 + factor)
        case (.long, false), (.short, true):
            raw = cost * (1 - factor)
        }
        guard raw.isFinite, raw > 0 else { return nil }
        var price = raw
        if abs(price - cost) < minimumPriceDelta {
            price = takingProfit
                ? (side == .long ? cost + minimumPriceDelta : cost - minimumPriceDelta)
                : (side == .long ? cost - minimumPriceDelta : cost + minimumPriceDelta)
        }
        guard price > 0 else { return nil }
        price = roundPrice(price)
        let minDelta = max(minimumPriceDelta, tickSize(for: max(price, cost)))
        switch (side, takingProfit) {
        case (.long, true), (.short, false):
            if price < cost + minDelta {
                price = roundPrice(cost + minDelta)
            }
        case (.long, false), (.short, true):
            if price > cost - minDelta {
                price = roundPrice(cost - minDelta)
            }
        }
        return price > 0 && price != roundPrice(cost) ? price : nil
    }
}
