import Foundation

final class AlpacaBrokerage: BrokerageServing {
    let account: BrokerageAccount
    var maxFillBuckets = 32
    let orderUpdates: AsyncStream<Order>
    let unauthorizedUpdates: AsyncStream<Void>
    private let api: AlpacaTradingAPI
    private let fillCache = FillActivityCache()
    private let tradeSocket: AlpacaTradeSocket?
    private let orderUpdatesContinuation: AsyncStream<Order>.Continuation?
    private let unauthorizedUpdatesContinuation: AsyncStream<Void>.Continuation?

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
        var orders: AsyncStream<Order>.Continuation!
        var unauthorized: AsyncStream<Void>.Continuation!
        orderUpdates = AsyncStream { orders = $0 }
        unauthorizedUpdates = AsyncStream { unauthorized = $0 }
        orderUpdatesContinuation = orders
        unauthorizedUpdatesContinuation = unauthorized
        let socket = AlpacaTradeSocket(
            url: account.environment.streamURL,
            key: key,
            secret: secret
        )
        tradeSocket = socket
        socket.onOrderData = { data in
            for stream in MarketStreamPayload.orders(from: data) {
                guard let order = Order(stream: stream) else { continue }
                orders.yield(order)
            }
        }
        socket.onUnauthorized = {
            unauthorized.yield(())
        }
        socket.connect()
    }

    init(account: BrokerageAccount, api: AlpacaTradingAPI) {
        self.account = account
        self.api = api
        tradeSocket = nil
        orderUpdatesContinuation = nil
        unauthorizedUpdatesContinuation = nil
        orderUpdates = AsyncStream { $0.finish() }
        unauthorizedUpdates = AsyncStream { $0.finish() }
    }

    deinit {
        tradeSocket?.disconnect()
        orderUpdatesContinuation?.finish()
        unauthorizedUpdatesContinuation?.finish()
    }

    func disconnectStreams() {
        tradeSocket?.disconnect()
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
                quantity: abs(dto.qty),
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

    func closedOrders(limit: Int, beforeOrderId: String?, symbols: String?, until: Date?) async throws -> OrderPage {
        let page = try await api.closedOrders(
            limit: limit,
            beforeOrderId: beforeOrderId,
            symbols: symbols,
            until: until
        )
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

    func place(_ order: NewOrder) async throws -> [Order] {
        try mapOrders(try await api.place(order))
    }

    func replace(orderId: String, amendment: OrderAmendment) async throws -> [Order] {
        try mapOrders(try await api.replace(orderId: orderId, amendment: amendment))
    }

    func closePosition(symbol: String, percentage: Double, cancelOpenOrders: Bool) async throws -> [Order] {
        try mapOrders(
            try await api.closePosition(
                symbol: symbol,
                percentage: percentage,
                cancelOpenOrders: cancelOpenOrders
            )
        )
    }

    func fills(symbol: String, day: Date) async throws -> [Fill] {
        let symbol = SymbolCode.normalize(symbol)
        guard !symbol.isEmpty else { return [] }
        let dayString = MarketClock.usDateString(from: day)
        guard let bounds = MarketClock.easternDayBounds(dayString) else { return [] }
        let activities = try await fillCache.activities(
            day: dayString,
            isToday: dayString == MarketClock.usDateString(),
            maxBuckets: maxFillBuckets
        ) {
            try await self.api.fillActivities(after: bounds.start, until: bounds.end)
        }
        return try Self.fills(from: activities, symbol: symbol, day: dayString)
    }

    private static func fills(
        from activities: [AlpacaFillActivityDTO],
        symbol: String,
        day: String
    ) throws -> [Fill] {
        var groups: [String: (side: OrderSide, qty: Double, notional: Double, time: Date)] = [:]
        var order: [String] = []
        for dto in activities {
            guard dto.symbol == symbol else { continue }
            guard MarketClock.usDateString(from: dto.transactionTime) == day else { continue }
            guard let mapped = AlpacaTradingAPI.fillSide(dto.side),
                  let side = OrderSide(rawValue: mapped)
            else {
                throw AppError.decoding
            }
            if var existing = groups[dto.orderId] {
                existing.qty += dto.qty
                existing.notional += dto.price * dto.qty
                if dto.transactionTime > existing.time {
                    existing.time = dto.transactionTime
                }
                groups[dto.orderId] = existing
            } else {
                groups[dto.orderId] = (side, dto.qty, dto.price * dto.qty, dto.transactionTime)
                order.append(dto.orderId)
            }
        }
        return order.compactMap { id in
            guard let group = groups[id], group.qty > 0 else { return nil }
            return Fill(
                orderId: id,
                symbol: symbol,
                side: group.side,
                quantity: group.qty,
                price: group.notional / group.qty,
                filledAt: group.time
            )
        }
        .sorted {
            if $0.filledAt != $1.filledAt { return $0.filledAt < $1.filledAt }
            return $0.id < $1.id
        }
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
            filledAt: dto.filledAt,
            clientOrderId: dto.clientOrderId,
            orderClass: dto.orderClass,
            parentOrderId: dto.parentOrderId
        )
    }
}

private actor FillActivityCache {
    private var activitiesByDay: [String: [AlpacaFillActivityDTO]] = [:]
    private var order: [String] = []
    private var inflight: [String: Task<[AlpacaFillActivityDTO], Error>] = [:]

    func activities(
        day: String,
        isToday: Bool,
        maxBuckets: Int,
        fetch: @escaping () async throws -> [AlpacaFillActivityDTO]
    ) async throws -> [AlpacaFillActivityDTO] {
        if !isToday, let cached = activitiesByDay[day] {
            touch(day)
            return cached
        }
        if let existing = inflight[day] {
            return try await existing.value
        }
        let task = Task {
            try await fetch()
        }
        inflight[day] = task
        defer { inflight[day] = nil }
        let value = try await task.value
        if !isToday {
            remember(day, value, maxBuckets: maxBuckets)
        }
        return value
    }

    private func remember(_ day: String, _ value: [AlpacaFillActivityDTO], maxBuckets: Int) {
        activitiesByDay[day] = value
        touch(day)
        let cap = max(1, maxBuckets)
        while order.count > cap {
            let evicted = order.removeFirst()
            activitiesByDay[evicted] = nil
        }
    }

    private func touch(_ day: String) {
        order.removeAll { $0 == day }
        order.append(day)
    }
}
