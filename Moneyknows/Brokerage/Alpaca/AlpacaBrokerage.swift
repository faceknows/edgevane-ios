import Foundation

final class AlpacaBrokerage: BrokerageServing {
    let account: BrokerageAccount
    private let api: AlpacaTradingAPI

    init(account: BrokerageAccount, key: String, secret: String, logsRequests: Bool = AppEnvironment.enableLogging) {
        self.account = account
        let client = HTTPClient(
            baseURL: account.environment.host,
            defaultHeaders: [
                "Accept": "application/json",
                "APCA-API-KEY-ID": key,
                "APCA-API-SECRET-KEY": secret,
            ],
            logsRequests: logsRequests,
            timeout: AppEnvironment.apiTimeout
        )
        api = AlpacaTradingAPI(client: client)
    }

    init(account: BrokerageAccount, api: AlpacaTradingAPI) {
        self.account = account
        self.api = api
    }

    func portfolio() async throws -> Portfolio {
        let dto = try await api.account()
        return Portfolio(
            equity: dto.equity,
            lastEquity: dto.lastEquity,
            cash: dto.cash,
            buyingPower: dto.buyingPower,
            portfolioValue: dto.portfolioValue ?? dto.equity,
            tradingBlocked: dto.tradingBlocked
        )
    }

    func positions() async throws -> [Position] {
        try await api.positions().map { dto in
            guard let side = PositionSide(rawValue: dto.side.lowercased()) else {
                throw AppError.decoding
            }
            return Position(
                symbol: dto.symbol,
                quantity: dto.qty,
                side: side,
                averageEntry: dto.avgEntryPrice,
                currentPrice: dto.currentPrice,
                marketValue: dto.marketValue,
                costBasis: dto.costBasis,
                unrealizedPL: dto.unrealizedPL,
                unrealizedPLPercent: dto.unrealizedPLPercent * 100
            )
        }
        .sorted { $0.symbol < $1.symbol }
    }

    func openOrders() async throws -> [Order] {
        try mapOrders(try await api.openOrders())
    }

    func closedOrders(limit: Int, beforeOrderId: String?) async throws -> OrderPage {
        let page = try await api.closedOrders(limit: limit, beforeOrderId: beforeOrderId)
        return OrderPage(
            orders: try mapOrders(page.orders),
            nextBeforeOrderId: page.nextBeforeOrderId,
            hasMore: page.hasMore
        )
    }

    func order(id: String) async throws -> [Order] {
        try mapOrders(try await api.order(id: id))
    }

    func cancel(orderId: String) async throws {
        try await api.cancel(orderId: orderId)
        AppLog.brokerage.info("canceled order \(orderId, privacy: .public)")
    }

    private func mapOrders(_ dtos: [AlpacaOrderDTO]) throws -> [Order] {
        try dtos.map(Self.mapOrder)
    }

    private static func mapOrder(_ dto: AlpacaOrderDTO) throws -> Order {
        guard let side = OrderSide(rawValue: dto.side.lowercased()) else {
            throw AppError.decoding
        }
        return Order(
            id: dto.id,
            symbol: dto.symbol,
            side: side,
            type: OrderType(brokerValue: dto.type),
            status: OrderStatus(brokerValue: dto.status),
            quantity: dto.qty,
            filledQuantity: dto.filledQty,
            limitPrice: dto.limitPrice,
            stopPrice: dto.stopPrice,
            filledAvgPrice: dto.filledAvgPrice,
            timeInForce: dto.timeInForce,
            submittedAt: dto.submittedAt,
            updatedAt: dto.updatedAt,
            createdAt: dto.createdAt,
            clientOrderId: dto.clientOrderId
        )
    }
}

extension OrderStatus {
    init(brokerValue: String) {
        switch brokerValue.lowercased() {
        case "new": self = .new
        case "partially_filled": self = .partiallyFilled
        case "filled": self = .filled
        case "done_for_day": self = .doneForDay
        case "canceled", "cancelled": self = .canceled
        case "expired": self = .expired
        case "replaced": self = .replaced
        case "pending_cancel": self = .pendingCancel
        case "pending_replace": self = .pendingReplace
        case "accepted": self = .accepted
        case "pending_new": self = .pendingNew
        case "accepted_for_bidding": self = .acceptedForBidding
        case "stopped": self = .stopped
        case "rejected": self = .rejected
        case "suspended": self = .suspended
        case "calculated": self = .calculated
        case "held": self = .held
        default: self = .other
        }
    }
}

extension OrderType {
    init(brokerValue: String) {
        switch brokerValue.lowercased() {
        case "market": self = .market
        case "limit": self = .limit
        case "stop": self = .stop
        case "stop_limit": self = .stopLimit
        case "trailing_stop": self = .trailingStop
        default: self = .other
        }
    }
}
