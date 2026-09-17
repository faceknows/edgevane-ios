import Foundation

struct Portfolio: Equatable {
    var equity: Double
    var lastEquity: Double
    var cash: Double
    var buyingPower: Double
    var portfolioValue: Double
    var tradingBlocked: Bool

    var profitLoss: Double { equity - lastEquity }
    var profitLossPercent: Double {
        guard lastEquity != 0 else { return 0 }
        return profitLoss / lastEquity * 100
    }
}

enum PositionSide: String, Equatable {
    case long
    case short
}

struct Position: Equatable, Identifiable {
    var symbol: String
    var quantity: Double
    var side: PositionSide
    var averageEntry: Double
    var currentPrice: Double
    var marketValue: Double
    var costBasis: Double
    var unrealizedPL: Double
    var unrealizedPLPercent: Double

    var id: String { symbol }

    var absQuantity: Double { abs(quantity) }

    /// Alpaca `qty` is unsigned with `side`; the tape shows a signed share count.
    var signedQuantity: Double {
        side == .short ? -absQuantity : absQuantity
    }

    init(
        symbol: String,
        quantity: Double,
        side: PositionSide,
        averageEntry: Double,
        currentPrice: Double,
        marketValue: Double,
        costBasis: Double,
        unrealizedPL: Double,
        unrealizedPLPercent: Double
    ) {
        self.symbol = symbol
        self.quantity = abs(quantity)
        self.side = side
        self.averageEntry = averageEntry
        self.currentPrice = currentPrice
        self.marketValue = marketValue
        self.costBasis = costBasis
        self.unrealizedPL = unrealizedPL
        self.unrealizedPLPercent = unrealizedPLPercent
    }

    func unrealizedPercent(versus livePrice: Double) -> Double? {
        guard averageEntry.isFinite, averageEntry != 0, livePrice.isFinite else { return nil }
        let raw = side == .long ? livePrice - averageEntry : averageEntry - livePrice
        return raw / averageEntry * 100
    }
}

enum OrderSide: String, Equatable {
    case buy
    case sell
}

enum OrderType: Equatable {
    case market
    case limit
    case stop
    case stopLimit
    case trailingStop
    case other

    var title: String {
        switch self {
        case .market: return L10n.Orders.typeMarket
        case .limit: return L10n.Orders.typeLimit
        case .stop: return L10n.Orders.typeStop
        case .stopLimit: return L10n.Orders.typeStopLimit
        case .trailingStop: return L10n.Orders.typeTrailingStop
        case .other: return L10n.Orders.typeOther
        }
    }
}

enum OrderStatus: Equatable {
    case new
    case partiallyFilled
    case filled
    case doneForDay
    case canceled
    case expired
    case replaced
    case pendingCancel
    case pendingReplace
    case accepted
    case pendingNew
    case acceptedForBidding
    case stopped
    case rejected
    case suspended
    case calculated
    case held
    case other

    var title: String {
        switch self {
        case .new: return L10n.Orders.statusNew
        case .partiallyFilled: return L10n.Orders.statusPartiallyFilled
        case .filled: return L10n.Orders.statusFilled
        case .doneForDay: return L10n.Orders.statusDoneForDay
        case .canceled: return L10n.Orders.statusCanceled
        case .expired: return L10n.Orders.statusExpired
        case .replaced: return L10n.Orders.statusReplaced
        case .pendingCancel: return L10n.Orders.statusPendingCancel
        case .pendingReplace: return L10n.Orders.statusPendingReplace
        case .accepted: return L10n.Orders.statusAccepted
        case .pendingNew: return L10n.Orders.statusPendingNew
        case .acceptedForBidding: return L10n.Orders.statusAcceptedForBidding
        case .stopped: return L10n.Orders.statusStopped
        case .rejected: return L10n.Orders.statusRejected
        case .suspended: return L10n.Orders.statusSuspended
        case .calculated: return L10n.Orders.statusCalculated
        case .held: return L10n.Orders.statusHeld
        case .other: return L10n.Orders.statusOther
        }
    }

    var isOpen: Bool {
        switch self {
        case .filled, .canceled, .expired, .replaced, .rejected, .doneForDay, .calculated, .other:
            return false
        case .new, .partiallyFilled, .accepted, .pendingNew, .acceptedForBidding,
             .pendingCancel, .pendingReplace, .stopped, .suspended, .held:
            return true
        }
    }

    var isCancellable: Bool {
        switch self {
        case .new, .partiallyFilled, .accepted, .pendingNew, .acceptedForBidding:
            return true
        default:
            return false
        }
    }

    /// Detail-bar Orders button: new / accepted / accepted_for_bidding.
    var showsOnDetailTradeBar: Bool {
        switch self {
        case .new, .accepted, .acceptedForBidding:
            return true
        default:
            return false
        }
    }
}

enum OrderListFilter: String, CaseIterable, Identifiable {
    case all
    case filled
    case new

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.Orders.filterAll
        case .filled: return L10n.Orders.filterFilled
        case .new: return L10n.Orders.filterNew
        }
    }
}

struct Order: Equatable, Identifiable {
    var id: String
    var symbol: String
    var side: OrderSide
    var type: OrderType
    var status: OrderStatus
    var quantity: Double
    var filledQuantity: Double
    var limitPrice: Double?
    var stopPrice: Double?
    var filledAvgPrice: Double?
    var timeInForce: String?
    var submittedAt: Date?
    var updatedAt: Date?
    var createdAt: Date?
    var filledAt: Date?
    var clientOrderId: String?
    var orderClass: String?
    var parentOrderId: String?

    var sortDate: Date {
        updatedAt ?? submittedAt ?? createdAt ?? Date.distantPast
    }

    var isCancellable: Bool { status.isCancellable }

    var isAmendable: Bool {
        isCancellable && (type == .limit || type == .stop)
    }

    var isAutoExit: Bool {
        AutoExitOrder.isAutoExit(clientOrderId)
    }

    var isOTOBracket: Bool {
        OTOOrder.isOTO(clientOrderId) || orderClass?.lowercased() == "oto"
    }

    var isOCOBracket: Bool {
        AutoExitOrder.isOCO(clientOrderId) || orderClass?.lowercased() == "oco"
    }

    var isProtectiveExit: Bool {
        isAutoExit || isOTOBracket || isOCOBracket
    }

    var ocoGroupId: String {
        if let parentOrderId, !parentOrderId.isEmpty {
            return parentOrderId
        }
        return id
    }

    var listQuantity: Double {
        filledQuantity > 0 ? filledQuantity : quantity
    }

    var listPrice: Double? {
        filledQuantity > 0 ? filledAvgPrice : (limitPrice ?? stopPrice)
    }

    var remainingQuantity: Double {
        max(0, quantity - filledQuantity)
    }

    var showsPartialFill: Bool {
        filledQuantity > 0 && filledQuantity < quantity
    }

    var needsFillActivity: Bool {
        filledQuantity > 0 && filledAt == nil
    }

    /// Alpaca leaves `filledAt` empty on canceled partials; `updatedAt` is then the cancel time.
    var fillEventAt: Date? {
        if let filledAt { return filledAt }
        guard filledQuantity > 0 else { return nil }
        if status.isOpen {
            return updatedAt ?? submittedAt
        }
        guard let submittedAt, let updatedAt else {
            return submittedAt ?? updatedAt
        }
        if MarketClock.usDateString(from: submittedAt) == MarketClock.usDateString(from: updatedAt) {
            return updatedAt
        }
        return nil
    }

    var easternFillDay: String? {
        guard filledQuantity > 0, let date = fillEventAt else { return nil }
        return MarketClock.usDateString(from: date)
    }

    func belongsToEasternDay(_ day: String) -> Bool {
        easternFillDay == day
    }

    func retainingFillTimestamp(from existing: Order?) -> Order {
        var order = self
        guard order.filledQuantity > 0 else { return order }
        let previousQty = existing?.filledQuantity ?? 0
        if order.filledQuantity > previousQty, existing != nil || order.status.isOpen {
            if order.filledAt == nil {
                order.filledAt = order.updatedAt ?? existing?.filledAt
            }
            return order
        }
        if order.filledAt == nil, let kept = existing?.filledAt {
            order.filledAt = kept
        }
        return order
    }

    /// Compact row `qty | price`: instruction while the order is still open; fill avg once it is done.
    var rowPrice: Double? {
        if status.isOpen {
            return limitPrice ?? stopPrice
        }
        return filledAvgPrice ?? limitPrice ?? stopPrice
    }

    var rowShowsMarketPrice: Bool {
        rowPrice == nil && type == .market
    }

    func matches(_ filter: OrderListFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .filled:
            return filledQuantity > 0
        case .new:
            return status == .new
        }
    }
}

struct OrderPage: Equatable {
    var orders: [Order]
    var nextBeforeOrderId: String?
    var hasMore: Bool
}

struct OrderApplyResult: Equatable {
    var accepted: Bool
    var statusChanged: Bool
    var isNewFill: Bool
}

enum NewOrderKind: Equatable {
    case limit
    case stop
    case oto
    case oco

    var isExtendedHoursEligible: Bool { self == .limit }
}

struct NewOrder: Equatable {
    var symbol: String
    var side: OrderSide
    var kind: NewOrderKind
    var quantity: Double
    var limitPrice: Double?
    var stopPrice: Double?
    var takeProfitLimitPrice: Double?
    var timeInForce: String
    var extendedHours: Bool
    var clientOrderId: String?

    init(
        symbol: String,
        side: OrderSide,
        kind: NewOrderKind,
        quantity: Double,
        limitPrice: Double? = nil,
        stopPrice: Double? = nil,
        takeProfitLimitPrice: Double? = nil,
        timeInForce: String = "day",
        clientOrderId: String? = nil
    ) {
        self.symbol = SymbolCode.normalize(symbol)
        self.side = side
        self.kind = kind
        self.quantity = quantity
        self.limitPrice = limitPrice
        self.stopPrice = stopPrice
        self.takeProfitLimitPrice = takeProfitLimitPrice
        self.timeInForce = timeInForce
        self.extendedHours = kind.isExtendedHoursEligible
        self.clientOrderId = clientOrderId
    }

    var displayPrice: Double? {
        switch kind {
        case .limit, .oto, .oco:
            return limitPrice
        case .stop:
            return stopPrice
        }
    }
}

struct OrderAmendment: Equatable {
    var quantity: Double?
    var limitPrice: Double?
    var stopPrice: Double?
}

struct ClosePositionCommand: Equatable {
    var symbol: String
    var percentage: Double
    var cancelOpenOrders: Bool

    init(symbol: String, percentage: Double = 100, cancelOpenOrders: Bool) {
        self.symbol = SymbolCode.normalize(symbol)
        self.percentage = percentage
        self.cancelOpenOrders = cancelOpenOrders
    }
}

enum AutoExitOrder {
    static let takeProfitPrefix = "auto-tp-"
    static let stopLossPrefix = "auto-sl-"
    static let ocoPrefix = "auto-oco-"

    static func isAutoExit(_ clientOrderId: String?) -> Bool {
        isTakeProfit(clientOrderId) || isStopLoss(clientOrderId) || isOCO(clientOrderId)
    }

    static func isTakeProfit(_ clientOrderId: String?) -> Bool {
        hasPrefix(clientOrderId, takeProfitPrefix)
    }

    static func isStopLoss(_ clientOrderId: String?) -> Bool {
        hasPrefix(clientOrderId, stopLossPrefix)
    }

    static func isOCO(_ clientOrderId: String?) -> Bool {
        hasPrefix(clientOrderId, ocoPrefix)
    }

    static func takeProfitClientId() -> String {
        "\(takeProfitPrefix)\(UUID().uuidString)"
    }

    static func stopLossClientId() -> String {
        "\(stopLossPrefix)\(UUID().uuidString)"
    }

    static func ocoClientId() -> String {
        "\(ocoPrefix)\(UUID().uuidString)"
    }

    private static func hasPrefix(_ clientOrderId: String?, _ prefix: String) -> Bool {
        guard let clientOrderId, !clientOrderId.isEmpty else { return false }
        return clientOrderId.lowercased().hasPrefix(prefix)
    }
}

enum OTOOrder {
    static let prefix = "oto-"

    static func isOTO(_ clientOrderId: String?) -> Bool {
        guard let clientOrderId, !clientOrderId.isEmpty else { return false }
        return clientOrderId.lowercased().hasPrefix(prefix)
    }

    static func clientId() -> String {
        "\(prefix)\(UUID().uuidString)"
    }
}

enum ProtectiveExit {
    static func snapshots(from orders: [Order], symbol: String, positionSide: PositionSide) -> [NewOrder] {
        let open = OrderSizing.openExitOrders(symbol: symbol, positionSide: positionSide, orders: orders)
            .filter(\.isProtectiveExit)
        var consumed: Set<String> = []
        var snapshots: [NewOrder] = []
        let grouped = Dictionary(grouping: open.filter(\.isOCOBracket)) { $0.ocoGroupId }
        for (_, group) in grouped {
            let quantity = group.map(\.remainingQuantity).max() ?? 0
            let limitPrice = group.compactMap(\.limitPrice).first
            let stopPrice = group.compactMap(\.stopPrice).first
            guard quantity >= 1, let limitPrice, let stopPrice else { continue }
            snapshots.append(
                NewOrder(
                    symbol: symbol,
                    side: group[0].side,
                    kind: .oco,
                    quantity: quantity,
                    limitPrice: limitPrice,
                    stopPrice: stopPrice,
                    timeInForce: "day",
                    clientOrderId: AutoExitOrder.ocoClientId()
                )
            )
            group.forEach { consumed.insert($0.id) }
        }
        for order in open where !consumed.contains(order.id) {
            guard order.remainingQuantity >= 1 else { continue }
            if order.type == .stop || AutoExitOrder.isStopLoss(order.clientOrderId) {
                snapshots.append(
                    NewOrder(
                        symbol: symbol,
                        side: order.side,
                        kind: .stop,
                        quantity: order.remainingQuantity,
                        stopPrice: order.stopPrice,
                        clientOrderId: AutoExitOrder.stopLossClientId()
                    )
                )
            } else {
                let clientId = order.isOTOBracket ? OTOOrder.clientId() : AutoExitOrder.takeProfitClientId()
                snapshots.append(
                    NewOrder(
                        symbol: symbol,
                        side: order.side,
                        kind: .limit,
                        quantity: order.remainingQuantity,
                        limitPrice: order.limitPrice,
                        clientOrderId: clientId
                    )
                )
            }
        }
        return snapshots
    }
}

enum StopQuantityMode: String, CaseIterable, Identifiable {
    case available
    case total
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: return L10n.Trading.stopQtyAvailable
        case .total: return L10n.Trading.stopQtyTotal
        case .custom: return L10n.Trading.stopQtyCustom
        }
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

extension Order {
    init?(stream: StreamOrder) {
        guard let side = OrderSide(rawValue: stream.side.lowercased()) else { return nil }
        self.init(
            id: stream.id,
            symbol: stream.symbol,
            side: side,
            type: OrderType(brokerValue: stream.type),
            status: OrderStatus(brokerValue: stream.status),
            quantity: stream.qty,
            filledQuantity: stream.filledQty,
            limitPrice: stream.limitPrice,
            stopPrice: stream.stopPrice,
            filledAvgPrice: stream.filledAvgPrice,
            timeInForce: stream.timeInForce,
            submittedAt: stream.submittedAt,
            updatedAt: stream.updatedAt,
            createdAt: stream.createdAt,
            filledAt: stream.filledAt,
            clientOrderId: stream.clientOrderId,
            orderClass: stream.orderClass,
            parentOrderId: stream.parentOrderId
        )
    }
}

struct TradingNotice: Equatable, Identifiable {
    let id: UUID
    let text: String
    let boldTerms: [String]

    init(text: String, boldTerms: [String] = [], id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.boldTerms = boldTerms
    }
}

enum DailyPnL {
    static let warningThreshold = -1.5

    enum Tone: Equatable {
        case profit
        case loss
        case warning
    }

    static func tone(percent: Double?) -> Tone {
        guard let percent, percent.isFinite else { return .profit }
        if percent <= warningThreshold { return .warning }
        return percent < 0 ? .loss : .profit
    }
}
