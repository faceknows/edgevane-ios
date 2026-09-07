import Foundation

@MainActor
final class AutoExit {
    var trading: TradingSession?
    var takeProfitPercent: () -> Double = { 0 }
    var stopLossPercent: () -> Double = { 0 }
    var protectionMinutes: () -> Int = { UserPreferences.defaults.allowTradeInMinutesAfterOpen }
    var maxOrderValue: () -> Double? = { nil }
    var isTakeProfitBlocked: (String) -> Bool = { _ in false }
    var isStopLossBlocked: (String) -> Bool = { _ in false }
    var now: () -> Date = Date.init
    var retryNanoseconds: UInt64 = 200_000_000
    var extraRetries = 2

    private var inFlight: Set<String> = []
    private var pending: Set<String> = []
    private var latestFill: [String: Order] = [:]
    private var fillPrevious: [String: Position] = [:]
    private var fillNetDelta: [String: Double] = [:]
    private var accumulatedFillIds: [String: Set<String>] = [:]
    private var capturedFillSymbols: Set<String> = []
    private var resyncBudget: [String: Int] = [:]
    private var generation: UInt64 = 0
    private var fillTasks: [UUID: Task<Void, Never>] = [:]

    var fillTaskCount: Int { fillTasks.count }

    func reset() {
        generation += 1
        fillTasks.values.forEach { $0.cancel() }
        fillTasks.removeAll()
        inFlight.removeAll()
        pending.removeAll()
        latestFill.removeAll()
        fillPrevious.removeAll()
        fillNetDelta.removeAll()
        accumulatedFillIds.removeAll()
        capturedFillSymbols.removeAll()
        resyncBudget.removeAll()
    }

    func scheduleFill(_ order: Order) {
        guard order.status == .filled, !order.isAutoExit else { return }
        rememberFillPrevious(for: order)
        let id = UUID()
        let generation = self.generation
        let sessionEpoch = trading?.sessionEpoch ?? 0
        let task = Task {
            await handleFill(order, generation: generation, sessionEpoch: sessionEpoch)
            fillTasks[id] = nil
        }
        fillTasks[id] = task
    }

    func handleFill(_ order: Order) async {
        guard order.status == .filled, !order.isAutoExit else { return }
        rememberFillPrevious(for: order)
        await handleFill(order, generation: generation, sessionEpoch: trading?.sessionEpoch ?? 0)
    }

    private func handleFill(_ order: Order, generation: UInt64, sessionEpoch: UInt64) async {
        guard order.status == .filled, !order.isAutoExit else { return }
        guard isCurrent(generation: generation, sessionEpoch: sessionEpoch) else {
            forgetFillPrevious(for: SymbolCode.normalize(order.symbol))
            return
        }
        let symbol = SymbolCode.normalize(order.symbol)
        guard !symbol.isEmpty else { return }
        accumulateFill(order, symbol: symbol)
        latestFill[symbol] = order
        pending.insert(symbol)
        guard inFlight.insert(symbol).inserted else { return }
        defer {
            inFlight.remove(symbol)
            if isCurrent(generation: generation, sessionEpoch: sessionEpoch),
               pending.contains(symbol),
               let queued = latestFill[symbol] {
                scheduleFill(queued)
            } else if isCurrent(generation: generation, sessionEpoch: sessionEpoch) {
                latestFill[symbol] = nil
                resyncBudget[symbol] = nil
                forgetFillPrevious(for: symbol)
            }
        }
        while pending.remove(symbol) != nil {
            guard isCurrent(generation: generation, sessionEpoch: sessionEpoch) else { return }
            guard let fill = latestFill[symbol] else { continue }
            await run(symbol: symbol, fill: fill, generation: generation, sessionEpoch: sessionEpoch)
            if pending.contains(symbol), retryNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: retryNanoseconds)
            }
        }
    }

    private func rememberFillPrevious(for order: Order) {
        let symbol = SymbolCode.normalize(order.symbol)
        guard !symbol.isEmpty, !capturedFillSymbols.contains(symbol) else { return }
        capturedFillSymbols.insert(symbol)
        fillPrevious[symbol] = trading?.positionBeforeFill(for: symbol)
    }

    private func forgetFillPrevious(for symbol: String) {
        capturedFillSymbols.remove(symbol)
        fillPrevious[symbol] = nil
        fillNetDelta[symbol] = nil
        accumulatedFillIds[symbol] = nil
    }

    private func accumulateFill(_ order: Order, symbol: String) {
        var ids = accumulatedFillIds[symbol] ?? []
        guard ids.insert(order.id).inserted else { return }
        accumulatedFillIds[symbol] = ids
        fillNetDelta[symbol, default: 0] += Self.signedDelta(order, previous: fillPrevious[symbol])
    }

    private func liveFill(symbol: String, fallback: Order, previous: Position?) -> Order {
        Self.effectiveFill(
            latestFill[symbol] ?? fallback,
            previous: previous,
            net: netDelta(symbol: symbol, fallback: fallback, previous: previous)
        )
    }

    private func netDelta(symbol: String, fallback: Order, previous: Position?) -> Double {
        fillNetDelta[symbol] ?? Self.signedDelta(fallback, previous: previous)
    }

    private func run(symbol: String, fill: Order, generation: UInt64, sessionEpoch: UInt64) async {
        guard let trading, isCurrent(generation: generation, sessionEpoch: sessionEpoch) else { return }
        let previous: Position?
        if capturedFillSymbols.contains(symbol) {
            previous = fillPrevious[symbol]
        } else {
            previous = trading.positions.position(for: symbol)
        }
        let lookup = await lookupPosition(symbol: symbol, fill: fill, previous: previous, trading: trading)
        guard isCurrent(generation: generation, sessionEpoch: sessionEpoch) else { return }
        let effective = liveFill(symbol: symbol, fallback: fill, previous: previous)

        switch lookup {
        case .unavailable:
            requestResync(symbol, fill: effective, previous: previous, error: AppError.network, trading: trading)
            return
        case .empty:
            if let positionSide = flattenSide(fill: effective, previous: previous, orders: trading.orders.orders) {
                await cancelLeftoversOrNotice(symbol: symbol, positionSide: positionSide, trading: trading)
                resyncBudget[symbol] = nil
            } else {
                requestResync(symbol, fill: effective, previous: previous, error: TradingGuard.noPosition, trading: trading)
            }
            return
        case let .open(position):
            resyncBudget[symbol] = nil
            if let previous, previous.quantity > 0, previous.side != position.side {
                do {
                    try await cancelExisting(symbol: symbol, positionSide: previous.side, trading: trading)
                } catch {
                    if error.isCancellation { return }
                    noticeFailure(kind: L10n.Trading.autoExitKind, symbol: symbol, error: error, trading: trading)
                    return
                }
            }
            await reconcile(symbol: symbol, position: position, trading: trading)
        }
    }

    private func reconcile(
        symbol: String,
        position: Position,
        trading: TradingSession
    ) async {
        guard position.quantity >= 1 else {
            await cancelLeftoversOrNotice(symbol: symbol, positionSide: position.side, trading: trading)
            return
        }

        let takeProfitOn = takeProfitPercent() > 0 && !isTakeProfitBlocked(symbol)
        let stopLossOn = stopLossPercent() > 0 && !isStopLossBlocked(symbol)
        guard takeProfitOn || stopLossOn else { return }

        trading.placement.now = now
        await placeExits(
            symbol: symbol,
            position: position,
            takeProfitOn: takeProfitOn,
            stopLossOn: stopLossOn,
            trading: trading
        )
    }

    private enum PositionLookup {
        case open(Position)
        case empty
        case unavailable
    }

    private func lookupPosition(
        symbol: String,
        fill: Order,
        previous: Position?,
        trading: TradingSession
    ) async -> PositionLookup {
        var sawSuccessfulEmpty = false
        var sawFailure = false
        var sawUndersized = false
        let attempts = extraRetries + 1
        for attempt in 0..<attempts {
            if attempt > 0, retryNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: retryNanoseconds)
            }
            await trading.refresh(includingClosed: false)
            let net = netDelta(symbol: symbol, fallback: fill, previous: previous)
            if trading.positions.errorText != nil {
                sawFailure = true
                if let position = trading.positions.position(for: symbol),
                   position.quantity > 0,
                   Self.position(position, covers: previous, net: net) {
                    return .open(position)
                }
                continue
            }
            if let position = trading.positions.position(for: symbol), position.quantity > 0 {
                if Self.position(position, covers: previous, net: net) {
                    return .open(position)
                }
                sawUndersized = true
                continue
            }
            let needed = Self.inferredPosition(previous: previous, net: net).quantity
            if needed < 1 {
                return .empty
            }
            sawSuccessfulEmpty = true
        }
        if sawUndersized || sawFailure { return .unavailable }
        if sawSuccessfulEmpty {
            let net = netDelta(symbol: symbol, fallback: fill, previous: previous)
            let needed = Self.inferredPosition(previous: previous, net: net).quantity
            if let previous, previous.quantity > 0, needed >= 1 {
                return .unavailable
            }
            return .empty
        }
        return .empty
    }

    private func requestResync(
        _ symbol: String,
        fill: Order,
        previous: Position?,
        error: Error,
        trading: TradingSession
    ) {
        let left = resyncBudget[symbol] ?? extraRetries
        guard left > 0 else {
            noticeResyncExhausted(symbol: symbol, fill: fill, previous: previous, error: error, trading: trading)
            return
        }
        resyncBudget[symbol] = left - 1
        pending.insert(symbol)
    }

    private func noticeResyncExhausted(
        symbol: String,
        fill: Order,
        previous: Position?,
        error: Error,
        trading: TradingSession
    ) {
        let takeProfitOn = takeProfitPercent() > 0 && !isTakeProfitBlocked(symbol)
        let stopLossOn = stopLossPercent() > 0 && !isStopLossBlocked(symbol)
        guard takeProfitOn || stopLossOn else { return }
        let needed = Self.inferredPosition(
            previous: previous,
            net: fillNetDelta[symbol] ?? Self.signedDelta(fill, previous: previous)
        )
        guard needed.quantity >= 1 else { return }
        let protected = OrderSizing.protectedExitQuantity(
            symbol: symbol,
            positionSide: needed.side,
            orders: trading.orders.orders
        )
        guard protected + 1e-9 < needed.quantity else { return }
        let kind: String
        if takeProfitOn, stopLossOn {
            kind = L10n.Trading.autoExitKind
        } else if takeProfitOn {
            kind = L10n.Trading.takeProfitKind
        } else {
            kind = L10n.Trading.stopLossKind
        }
        noticeFailure(kind: kind, symbol: symbol, error: error, trading: trading)
    }

    private func cancelLeftoversOrNotice(
        symbol: String,
        positionSide: PositionSide,
        trading: TradingSession
    ) async {
        do {
            try await cancelExisting(symbol: symbol, positionSide: positionSide, trading: trading)
        } catch {
            if error.isCancellation { return }
            noticeFailure(kind: L10n.Trading.autoExitKind, symbol: symbol, error: error, trading: trading)
        }
    }

    private func cancelExisting(
        symbol: String,
        positionSide: PositionSide,
        trading: TradingSession
    ) async throws {
        var lastError: Error?
        let attempts = extraRetries + 1
        for attempt in 0..<attempts {
            if attempt > 0, retryNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: retryNanoseconds)
            }
            do {
                try await trading.cancelProtectiveExits(symbol: symbol, positionSide: positionSide)
                return
            } catch {
                if error.isCancellation { throw error }
                lastError = error
            }
        }
        throw lastError ?? AppError.network
    }

    private func placeExits(
        symbol: String,
        position: Position,
        takeProfitOn: Bool,
        stopLossOn: Bool,
        trading: TradingSession
    ) async {
        let takeProfitPrice = takeProfitOn
            ? OrderSizing.exitPrice(
                cost: position.averageEntry,
                percent: takeProfitPercent(),
                side: position.side,
                takingProfit: true
            )
            : nil
        let stopPrice = stopLossOn
            ? OrderSizing.exitPrice(
                cost: position.averageEntry,
                percent: stopLossPercent(),
                side: position.side,
                takingProfit: false
            )
            : nil

        if takeProfitOn, takeProfitPrice == nil {
            noticeFailure(kind: L10n.Trading.takeProfitKind, symbol: symbol, error: TradingGuard.invalidPrice, trading: trading)
            return
        }
        if stopLossOn, stopPrice == nil {
            noticeFailure(kind: L10n.Trading.stopLossKind, symbol: symbol, error: TradingGuard.invalidPrice, trading: trading)
            return
        }

        let quantity = OrderSizing.availableExitQuantity(
            position: position,
            openOrders: trading.orders.orders
        )
        guard quantity >= 1 else {
            await cancelLeftoversOrNotice(symbol: symbol, positionSide: position.side, trading: trading)
            return
        }

        let side: OrderSide = position.side == .short ? .buy : .sell
        if let takeProfitPrice, let stopPrice {
            let order = NewOrder(
                symbol: symbol,
                side: side,
                kind: .oco,
                quantity: quantity,
                limitPrice: takeProfitPrice,
                stopPrice: stopPrice,
                timeInForce: "day",
                extendedHours: false,
                clientOrderId: AutoExitOrder.ocoClientId()
            )
            await submit(order, kind: L10n.Trading.autoExitKind, symbol: symbol, trading: trading)
            return
        }
        if let takeProfitPrice {
            let order = NewOrder(
                symbol: symbol,
                side: side,
                kind: .limit,
                quantity: quantity,
                limitPrice: takeProfitPrice,
                timeInForce: "day",
                extendedHours: MarketClock.isExtendedHoursSession(at: now()),
                clientOrderId: AutoExitOrder.takeProfitClientId()
            )
            await submit(order, kind: L10n.Trading.takeProfitKind, symbol: symbol, trading: trading)
            return
        }
        if let stopPrice {
            let order = NewOrder(
                symbol: symbol,
                side: side,
                kind: .stop,
                quantity: quantity,
                stopPrice: stopPrice,
                timeInForce: "day",
                extendedHours: false,
                clientOrderId: AutoExitOrder.stopLossClientId()
            )
            await submit(order, kind: L10n.Trading.stopLossKind, symbol: symbol, trading: trading)
        }
    }

    private func submit(_ order: NewOrder, kind: String, symbol: String, trading: TradingSession) async {
        do {
            _ = try await trading.place(
                order,
                protectionMinutes: protectionMinutes(),
                maxOrderValue: maxOrderValue(),
                submitRetries: extraRetries
            )
            trading.postNotice(L10n.Trading.autoExitPlaced(kind, symbol))
        } catch {
            if error.isCancellation { return }
            if let appError = error as? AppError, case let .http(_, _, code) = appError, code == "TRADING_RESTORE_FAILED" {
                return
            }
            noticeFailure(kind: kind, symbol: symbol, error: error, trading: trading)
        }
    }

    private func noticeFailure(kind: String, symbol: String, error: Error?, trading: TradingSession) {
        let message = error.flatMap(UserFacingError.message(from:)) ?? L10n.Errors.generic
        trading.postNotice(L10n.Trading.autoExitFailed(kind, symbol, message))
    }

    private func isCurrent(generation: UInt64, sessionEpoch: UInt64) -> Bool {
        self.generation == generation && trading?.sessionEpoch == sessionEpoch && !Task.isCancelled
    }

    private func flattenSide(fill: Order, previous: Position?, orders: [Order]) -> PositionSide? {
        if Self.isReducing(fill, previous: previous), let previous {
            return previous.side
        }
        let longExits = OrderSizing.openExitOrders(symbol: fill.symbol, positionSide: .long, orders: orders)
            .filter(\.isProtectiveExit)
        let shortExits = OrderSizing.openExitOrders(symbol: fill.symbol, positionSide: .short, orders: orders)
            .filter(\.isProtectiveExit)
        if fill.side == .sell, !longExits.isEmpty { return .long }
        if fill.side == .buy, !shortExits.isEmpty { return .short }
        return nil
    }

    private static func signedDelta(_ fill: Order, previous: Position?) -> Double {
        if let previous, previous.quantity > 0 {
            if isReducing(fill, previous: previous) {
                return -fill.filledQuantity
            }
            if isIncreasing(fill, previous: previous) {
                return fill.filledQuantity
            }
            return 0
        }
        return fill.side == .buy ? fill.filledQuantity : -fill.filledQuantity
    }

    private static func effectiveFill(_ fill: Order, previous: Position?, net: Double) -> Order {
        var effective = fill
        effective.filledQuantity = abs(net)
        effective.quantity = abs(net)
        if let previous, previous.quantity > 0 {
            if net < -1e-9 {
                effective.side = previous.side == .long ? .sell : .buy
            } else if net > 1e-9 {
                effective.side = previous.side == .long ? .buy : .sell
            }
        } else if net < -1e-9 {
            effective.side = .sell
        } else if net > 1e-9 {
            effective.side = .buy
        }
        return effective
    }

    private static func inferredPosition(previous: Position?, net: Double) -> (side: PositionSide, quantity: Double) {
        if let previous, previous.quantity > 0 {
            let remaining = previous.quantity + net
            if remaining > 1e-9 {
                return (previous.side, remaining)
            }
            if remaining < -1e-9 {
                return (previous.side == .long ? .short : .long, -remaining)
            }
            return (previous.side, 0)
        }
        if net > 1e-9 {
            return (.long, net)
        }
        if net < -1e-9 {
            return (.short, -net)
        }
        return (.long, 0)
    }

    private static func isIncreasing(_ fill: Order, previous: Position) -> Bool {
        (previous.side == .long && fill.side == .buy)
            || (previous.side == .short && fill.side == .sell)
    }

    private static func position(_ position: Position, covers previous: Position?, net: Double) -> Bool {
        let needed = inferredPosition(previous: previous, net: net)
        guard needed.quantity >= 1 else { return false }
        guard position.side == needed.side else { return false }
        if let previous, previous.quantity > 0,
           needed.side != previous.side || needed.quantity + 1e-9 < previous.quantity {
            return abs(position.quantity - needed.quantity) <= 1e-9
        }
        return position.quantity + 1e-9 >= needed.quantity
    }

    private static func isReducing(_ fill: Order, previous: Position?) -> Bool {
        guard let previous else { return false }
        return (previous.side == .long && fill.side == .sell)
            || (previous.side == .short && fill.side == .buy)
    }
}
