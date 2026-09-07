import Foundation

struct Fill: Equatable, Identifiable {
    var orderId: String
    var symbol: String
    var side: OrderSide
    var quantity: Double
    var price: Double
    var filledAt: Date

    var id: String { DayFills.fillID(orderId: orderId, filledAt: filledAt) }
}

enum DayFills {
    static func fillID(orderId: String, day: String) -> String {
        "\(orderId)#\(day)"
    }

    static func fillID(orderId: String, filledAt: Date) -> String {
        fillID(orderId: orderId, day: MarketClock.usDateString(from: filledAt))
    }

    static func fills(from orders: [Order], symbol: String, day: String) -> [Fill] {
        fills(from: orders, symbol: symbol, days: day.isEmpty ? [] : [day])
    }

    static func fills(from orders: [Order], symbol: String, days: Set<String>) -> [Fill] {
        let symbol = SymbolCode.normalize(symbol)
        guard !symbol.isEmpty, !days.isEmpty else { return [] }
        return orders.compactMap { fill(from: $0) }
            .filter { $0.symbol == symbol && days.contains(MarketClock.usDateString(from: $0.filledAt)) }
            .sorted(by: chronologically)
    }

    static func isUnambiguous(_ order: Order) -> Bool {
        guard let filledAt = order.filledAt, let submittedAt = order.submittedAt else { return false }
        return MarketClock.usDateString(from: submittedAt) == MarketClock.usDateString(from: filledAt)
    }

    static func omitsAmbiguousOrders(
        _ orders: [Order],
        symbol: String,
        days: Set<String>,
        remote: [Fill]
    ) -> Bool {
        let symbol = SymbolCode.normalize(symbol)
        guard !symbol.isEmpty, !days.isEmpty else { return false }
        let remoteIDs = Set(remote.map(\.id))
        return orders.contains { order in
            guard !isUnambiguous(order), let fill = fill(from: order) else { return false }
            guard fill.symbol == symbol, days.contains(MarketClock.usDateString(from: fill.filledAt)) else {
                return false
            }
            return !remoteIDs.contains(fill.id)
        }
    }

    static func merging(_ first: [Fill], _ second: [Fill]) -> [Fill] {
        var byID: [String: Fill] = [:]
        for fill in first { byID[fill.id] = fill }
        for fill in second { byID[fill.id] = fill }
        return byID.values.sorted(by: chronologically)
    }

    static func combined(remote: [Fill], orders: [Order], symbol: String, day: String) -> [Fill] {
        let days: Set<String> = day.isEmpty ? [] : [day]
        return combined(remote: remote, orders: orders, symbol: symbol, days: days, successfulDays: days)
    }

    static func combined(
        remote: [Fill],
        orders: [Order],
        symbol: String,
        days: Set<String>,
        successfulDays: Set<String>
    ) -> [Fill] {
        let allowed = days.intersection(successfulDays)
        let local = fills(from: orders, symbol: symbol, days: allowed).filter { fill in
            orders.contains { $0.id == fill.orderId && isUnambiguous($0) }
        }
        return merging(local, remote)
    }

    static func chartDays(regularDate: String, extendedDate: String) -> [String] {
        var days: [String] = []
        var seen = Set<String>()
        for day in [regularDate, extendedDate] where !day.isEmpty && seen.insert(day).inserted {
            days.append(day)
        }
        return days
    }

    static func caption(_ fill: Fill) -> String {
        title(quantity: fill.quantity, price: fill.price)
    }

    static func session(for fill: Fill) -> BarSession? {
        switch MarketClock.sessionWindow(at: fill.filledAt) {
        case .premarket: return .premarket
        case .regular: return .regular
        case .aftermarket: return .aftermarket
        case nil: return nil
        }
    }

    static func isChartable(_ fill: Fill) -> Bool {
        session(for: fill) != nil
    }

    static func isChartable(
        _ fill: Fill,
        regularBars: [Bar],
        preBars: [Bar],
        afterBars: [Bar]
    ) -> Bool {
        switch session(for: fill) {
        case .regular:
            return hasContainingBar(fill, in: regularBars)
        case .premarket:
            return hasContainingBar(fill, in: preBars)
        case .aftermarket:
            return hasContainingBar(fill, in: afterBars)
        case .index, nil:
            return false
        }
    }

    static func markers(_ fills: [Fill], bars: [Bar] = [], session: BarSession? = nil) -> [ChartMarker] {
        fills.compactMap { fill in
            if let session, Self.session(for: fill) != session { return nil }
            let bar: Bar?
            if bars.isEmpty {
                bar = nil
            } else {
                bar = ChartHitTesting.containingBar(in: bars, at: fill.filledAt, duration: 60)
                guard bar != nil else { return nil }
            }
            let price = fill.price > 0 ? fill.price : bar?.close
            guard let price, price > 0 else { return nil }
            return ChartMarker(
                id: fill.id,
                time: bar?.time ?? fill.filledAt,
                price: price,
                kind: fill.side == .buy ? .buy : .sell,
                title: title(quantity: fill.quantity, price: price),
                position: fill.side == .buy ? .belowBar : .aboveBar
            )
        }
    }

    static func fill(from order: Order) -> Fill? {
        guard order.filledQuantity > 0, let filledAt = order.filledAt else { return nil }
        return Fill(
            orderId: order.id,
            symbol: SymbolCode.normalize(order.symbol),
            side: order.side,
            quantity: order.filledQuantity,
            price: order.filledAvgPrice ?? 0,
            filledAt: filledAt
        )
    }

    private static func hasContainingBar(_ fill: Fill, in bars: [Bar]) -> Bool {
        guard !bars.isEmpty else { return false }
        return ChartHitTesting.containingBar(in: bars, at: fill.filledAt, duration: 60) != nil
    }

    private static func title(quantity: Double, price: Double) -> String {
        "\(MarketFormat.quantity(quantity))@\(MarketFormat.price(price > 0 ? price : nil))"
    }

    private static func chronologically(_ lhs: Fill, _ rhs: Fill) -> Bool {
        if lhs.filledAt != rhs.filledAt { return lhs.filledAt < rhs.filledAt }
        return lhs.id < rhs.id
    }
}

@MainActor
final class DayFillsSession: ObservableObject {
    static let todayReloadDelayNanoseconds: UInt64 = 400_000_000

    @Published var selectedFillID: String?
    @Published private(set) var fills: [Fill] = []
    @Published private(set) var errorText: String?

    private var remote: [Fill] = []
    private var symbol = ""
    private var days: Set<String> = []
    private var successfulDays: Set<String> = []
    private var fetchErrorText: String?
    private var loadID: UInt64 = 0
    private var boundEpoch: UInt64 = 0
    private var loading = false
    private var lastTodayLocal: [Fill] = []
    private var reloadTask: Task<Void, Never>?
    private let now: () -> Date
    private let reloadDelayNanoseconds: UInt64

    init(
        now: @escaping () -> Date = Date.init,
        reloadDelayNanoseconds: UInt64 = DayFillsSession.todayReloadDelayNanoseconds
    ) {
        self.now = now
        self.reloadDelayNanoseconds = reloadDelayNanoseconds
    }

    func reset() {
        reloadTask?.cancel()
        reloadTask = nil
        loading = false
        lastTodayLocal = []
        loadID += 1
        boundEpoch = 0
        remote = []
        successfulDays = []
        fetchErrorText = nil
        fills = []
        errorText = nil
        selectedFillID = nil
        symbol = ""
        days = []
    }

    func load(symbol: String, day: String, trading: TradingSession) async {
        await load(symbol: symbol, days: [day], trading: trading)
    }

    func load(symbol: String, days: [String], trading: TradingSession) async {
        reloadTask?.cancel()
        reloadTask = nil
        let symbol = SymbolCode.normalize(symbol)
        let uniqueDays = uniqueDays(days)
        loadID += 1
        let loadID = self.loadID
        loading = true
        defer {
            if self.loadID == loadID {
                loading = false
            }
        }
        boundEpoch = trading.sessionEpoch
        self.symbol = symbol
        self.days = Set(uniqueDays)
        selectedFillID = nil
        errorText = nil
        lastTodayLocal = []
        remote = []
        successfulDays = []
        fetchErrorText = nil
        fills = []
        guard trading.hasAccount, !symbol.isEmpty, !uniqueDays.isEmpty else { return }
        let todayLocalBefore = todayLocalFills(from: trading.orders.orders)
        var remote: [Fill] = []
        var successfulDays = Set<String>()
        var loadError: String?
        for day in uniqueDays {
            do {
                remote = DayFills.merging(remote, try await trading.fills(symbol: symbol, day: day))
                successfulDays.insert(day)
            } catch {
                guard self.loadID == loadID else { return }
                if error.isCancellation { return }
                if loadError == nil {
                    loadError = UserFacingError.message(from: error)
                }
            }
        }
        guard self.loadID == loadID else { return }
        guard trading.hasAccount, trading.sessionEpoch == boundEpoch else {
            reset()
            return
        }
        self.remote = remote
        self.successfulDays = successfulDays
        fetchErrorText = loadError
        lastTodayLocal = todayLocalFills(from: trading.orders.orders)
        applyFills(from: trading.orders.orders)
        let todayChanged = lastTodayLocal != todayLocalBefore
        loading = false
        if todayChanged {
            scheduleTodayReload(trading: trading)
        }
    }

    func refresh(orders: [Order], trading: TradingSession) {
        if !trading.hasAccount {
            reset()
            return
        }
        if boundEpoch != 0, trading.sessionEpoch != boundEpoch {
            reset()
            return
        }
        guard !loading else { return }
        applyFills(from: orders)
        let todayLocal = todayLocalFills(from: orders)
        guard todayLocal != lastTodayLocal else { return }
        lastTodayLocal = todayLocal
        scheduleTodayReload(trading: trading)
    }

    func markers(bars: [Bar], session: BarSession) -> [ChartMarker] {
        DayFills.markers(fills, bars: bars, session: session)
    }

    private func applyFills(from orders: [Order]) {
        fills = DayFills.combined(
            remote: remote,
            orders: orders,
            symbol: symbol,
            days: days,
            successfulDays: successfulDays
        )
        let omitted = DayFills.omitsAmbiguousOrders(
            orders,
            symbol: symbol,
            days: successfulDays,
            remote: remote
        )
        errorText = fetchErrorText ?? (omitted ? L10n.Trading.orderHistoryIncomplete : nil)
    }

    private func uniqueDays(_ days: [String]) -> [String] {
        var seen = Set<String>()
        return days.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func todayString() -> String {
        MarketClock.usDateString(from: now())
    }

    private func todayLocalFills(from orders: [Order]) -> [Fill] {
        let today = todayString()
        guard days.contains(today) else { return [] }
        return DayFills.fills(from: orders, symbol: symbol, day: today)
    }

    private func scheduleTodayReload(trading: TradingSession) {
        let today = todayString()
        guard days.contains(today), trading.hasAccount, !symbol.isEmpty else { return }
        reloadTask?.cancel()
        let loadID = self.loadID
        let boundEpoch = self.boundEpoch
        let symbol = self.symbol
        let delay = reloadDelayNanoseconds
        reloadTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            await self.reloadToday(
                today: today,
                symbol: symbol,
                loadID: loadID,
                boundEpoch: boundEpoch,
                trading: trading
            )
        }
    }

    private func reloadToday(
        today: String,
        symbol: String,
        loadID: UInt64,
        boundEpoch: UInt64,
        trading: TradingSession
    ) async {
        guard self.loadID == loadID, !loading else { return }
        guard trading.hasAccount, trading.sessionEpoch == boundEpoch else {
            reset()
            return
        }
        guard days.contains(today), self.symbol == symbol else { return }
        do {
            let fresh = try await trading.fills(symbol: symbol, day: today)
            guard self.loadID == loadID else { return }
            guard trading.hasAccount, trading.sessionEpoch == boundEpoch else {
                reset()
                return
            }
            remote = DayFills.merging(
                remote.filter { MarketClock.usDateString(from: $0.filledAt) != today },
                fresh
            )
            successfulDays.insert(today)
            if successfulDays == days {
                fetchErrorText = nil
            }
            applyFills(from: trading.orders.orders)
        } catch {
            guard self.loadID == loadID else { return }
            if error.isCancellation { return }
            if fetchErrorText == nil {
                fetchErrorText = UserFacingError.message(from: error)
            }
            applyFills(from: trading.orders.orders)
        }
    }
}
