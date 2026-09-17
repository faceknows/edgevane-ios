import Foundation

@MainActor
final class PortfolioStore: ObservableObject {
    @Published private(set) var snapshot: Portfolio?
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    func reset() {
        snapshot = nil
        isLoading = false
        errorText = nil
    }

    func apply(_ snapshot: Portfolio?) {
        self.snapshot = snapshot
        errorText = nil
    }

    func markLoading(_ value: Bool) {
        isLoading = value
    }
}

@MainActor
final class PositionStore: ObservableObject {
    @Published private(set) var positions: [Position] = []
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    func reset() {
        positions = []
        isLoading = false
        errorText = nil
    }

    func apply(_ positions: [Position]) {
        self.positions = positions
        errorText = nil
    }

    func markLoading(_ value: Bool) {
        isLoading = value
    }

    func position(for raw: String) -> Position? {
        let symbol = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return positions.first { $0.symbol == symbol }
    }
}

@MainActor
final class OrderStore: ObservableObject {
    @Published private(set) var orders: [Order] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMoreClosed = false
    @Published private(set) var isLoadingMore = false
    @Published var errorText: String?
    @Published private(set) var historySymbol: String?
    @Published private(set) var historyOrders: [Order] = []
    @Published var historyError: String?
    @Published private(set) var historyLoading = false
    private var historyToken: UInt64 = 0

    func reset() {
        orders = []
        isLoading = false
        hasMoreClosed = false
        isLoadingMore = false
        errorText = nil
        clearHistory()
    }

    func clearHistory() {
        historyToken += 1
        historySymbol = nil
        historyOrders = []
        historyError = nil
        historyLoading = false
    }

    func beginHistory(symbol: String) -> UInt64 {
        historyToken += 1
        historySymbol = symbol
        historyOrders = []
        historyError = nil
        historyLoading = true
        return historyToken
    }

    func finishHistory(_ orders: [Order], token: UInt64, error: String? = nil) {
        guard token == historyToken else { return }
        historyOrders = sorted(orders)
        historyLoading = false
        historyError = error
    }

    func failHistory(_ message: String, token: UInt64) {
        guard token == historyToken else { return }
        historyOrders = []
        historyLoading = false
        historyError = message
    }

    func abandonHistory(token: UInt64) {
        guard token == historyToken else { return }
        historyLoading = false
    }

    func apply(_ orders: [Order]) {
        let previous = Dictionary(uniqueKeysWithValues: self.orders.map { ($0.id, $0) })
        self.orders = sorted(orders.map { $0.retainingFillTimestamp(from: previous[$0.id]) })
        errorText = nil
    }

    func applyOpen(_ open: [Order]) -> [String] {
        let previousOpen = Set(orders.filter { $0.status.isOpen }.map(\.id))
        let openIds = Set(open.map(\.id))
        let disappeared = previousOpen.subtracting(openIds)
        var byId = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        let previous = byId
        byId = byId.filter { item in
            !item.value.status.isOpen || disappeared.contains(item.key)
        }
        for order in open {
            byId[order.id] = order.retainingFillTimestamp(from: previous[order.id])
        }
        self.orders = sorted(Array(byId.values))
        errorText = nil
        return Array(disappeared)
    }

    func applyClosed(_ closed: [Order], replacingClosed: Bool = true, hasMore: Bool? = nil) {
        var byId = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        let previous = byId
        if replacingClosed {
            byId = byId.filter { $0.value.status.isOpen }
        }
        for order in closed {
            byId[order.id] = order.retainingFillTimestamp(from: previous[order.id])
        }
        self.orders = sorted(Array(byId.values))
        if let hasMore {
            hasMoreClosed = hasMore
        } else if replacingClosed {
            hasMoreClosed = false
        }
        errorText = nil
    }

    func markLoadingMore(_ value: Bool) {
        isLoadingMore = value
    }

    private func sorted(_ orders: [Order]) -> [Order] {
        orders.sorted {
            if $0.sortDate != $1.sortDate { return $0.sortDate > $1.sortDate }
            return $0.id < $1.id
        }
    }

    func markLoading(_ value: Bool) {
        isLoading = value
    }

    func applyUpdate(_ order: Order) -> OrderApplyResult {
        var byId = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        if let existing = byId[order.id] {
            if let incoming = order.updatedAt, let current = existing.updatedAt, incoming < current {
                return OrderApplyResult(accepted: false, statusChanged: false, isNewFill: false)
            }
            let incoming = order.retainingFillTimestamp(from: existing)
            if existing == incoming {
                return OrderApplyResult(accepted: false, statusChanged: false, isNewFill: false)
            }
            let statusChanged = existing.status != incoming.status
            let isNewFill = incoming.status == .filled && existing.status != .filled && !incoming.isAutoExit
            byId[order.id] = incoming
            self.orders = sorted(Array(byId.values))
            errorText = nil
            return OrderApplyResult(accepted: true, statusChanged: statusChanged, isNewFill: isNewFill)
        }
        let incoming = order.retainingFillTimestamp(from: nil)
        byId[order.id] = incoming
        self.orders = sorted(Array(byId.values))
        errorText = nil
        return OrderApplyResult(
            accepted: true,
            statusChanged: true,
            isNewFill: incoming.status == .filled && !incoming.isAutoExit
        )
    }

    func filtered(_ filter: OrderListFilter, symbol: String? = nil) -> [Order] {
        let wanted = symbol
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .flatMap { $0.isEmpty ? nil : $0 }
        return orders.filter { order in
            order.matches(filter) && (wanted == nil || order.symbol == wanted)
        }
    }

    func todayFilledSymbols(on day: String = MarketClock.usDateString()) -> [String] {
        var seen = Set<String>()
        return orders.compactMap { order -> String? in
            guard order.easternFillDay == day, seen.insert(order.symbol).inserted else { return nil }
            return order.symbol
        }
        .sorted()
    }
}
