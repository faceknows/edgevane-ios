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

    func reset() {
        orders = []
        isLoading = false
        hasMoreClosed = false
        isLoadingMore = false
        errorText = nil
    }

    func apply(_ orders: [Order]) {
        self.orders = sorted(orders)
        errorText = nil
    }

    func applyOpen(_ open: [Order]) -> [String] {
        let previousOpen = Set(orders.filter { $0.status.isOpen }.map(\.id))
        let openIds = Set(open.map(\.id))
        let disappeared = previousOpen.subtracting(openIds)
        var byId = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        byId = byId.filter { item in
            !item.value.status.isOpen || disappeared.contains(item.key)
        }
        for order in open {
            byId[order.id] = order
        }
        self.orders = sorted(Array(byId.values))
        errorText = nil
        return Array(disappeared)
    }

    func applyClosed(_ closed: [Order], replacingClosed: Bool = true, hasMore: Bool? = nil) {
        var byId = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        if replacingClosed {
            byId = byId.filter { $0.value.status.isOpen }
        }
        for order in closed {
            byId[order.id] = order
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
            if existing == order {
                return OrderApplyResult(accepted: false, statusChanged: false, isNewFill: false)
            }
            let statusChanged = existing.status != order.status
            let isNewFill = order.status == .filled && existing.status != .filled && !order.isAutoExit
            byId[order.id] = order
            self.orders = sorted(Array(byId.values))
            errorText = nil
            return OrderApplyResult(accepted: true, statusChanged: statusChanged, isNewFill: isNewFill)
        }
        byId[order.id] = order
        self.orders = sorted(Array(byId.values))
        errorText = nil
        return OrderApplyResult(
            accepted: true,
            statusChanged: true,
            isNewFill: order.status == .filled && !order.isAutoExit
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
}
