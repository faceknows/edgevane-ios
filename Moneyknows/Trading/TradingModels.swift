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
    var clientOrderId: String?

    var sortDate: Date {
        updatedAt ?? submittedAt ?? createdAt ?? Date.distantPast
    }

    var isCancellable: Bool { status.isCancellable }

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
