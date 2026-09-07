import Foundation

struct OrderPlacement {
    var now: () -> Date = Date.init

    func submit(
        _ order: NewOrder,
        serving: BrokerageServing?,
        tradingBlocked: Bool,
        protectionMinutes: Int,
        maxOrderValue: Double?
    ) async throws -> [Order] {
        try validate(
            order,
            serving: serving,
            tradingBlocked: tradingBlocked,
            protectionMinutes: protectionMinutes,
            maxOrderValue: maxOrderValue
        )
        guard let serving else { throw TradingGuard.noAccount }
        var submitted = order
        if submitted.kind == .oto, submitted.clientOrderId == nil {
            submitted.clientOrderId = OTOOrder.clientId()
        }
        return try await serving.place(submitted)
    }

    func replace(
        orderId: String,
        amendment: OrderAmendment,
        original: Order,
        serving: BrokerageServing?,
        tradingBlocked: Bool,
        protectionMinutes: Int,
        maxOrderValue: Double?
    ) async throws -> [Order] {
        try guards(
            serving: serving,
            tradingBlocked: tradingBlocked,
            protectionMinutes: protectionMinutes
        )
        let quantity = amendment.quantity ?? original.quantity
        try validateQuantity(quantity)
        let price = amendment.limitPrice ?? amendment.stopPrice ?? original.limitPrice ?? original.stopPrice
        try validatePrice(price)
        if original.type == .limit || amendment.limitPrice != nil {
            if let limit = amendment.limitPrice ?? original.limitPrice {
                try validatePrice(limit)
            } else {
                throw TradingGuard.invalidPrice
            }
        }
        if original.type == .stop || amendment.stopPrice != nil {
            if let stop = amendment.stopPrice ?? original.stopPrice {
                try validatePrice(stop)
            } else {
                throw TradingGuard.invalidPrice
            }
        }
        try validateNotional(quantity: quantity, price: price, maxOrderValue: maxOrderValue)
        guard let serving else { throw TradingGuard.noAccount }
        return try await serving.replace(orderId: orderId, amendment: amendment)
    }

    func close(
        _ command: ClosePositionCommand,
        serving: BrokerageServing?,
        tradingBlocked: Bool,
        protectionMinutes: Int
    ) async throws -> [Order] {
        try guards(
            serving: serving,
            tradingBlocked: tradingBlocked,
            protectionMinutes: protectionMinutes
        )
        guard !command.symbol.isEmpty else { throw TradingGuard.invalidSymbol }
        guard command.percentage.isFinite, command.percentage > 0 else { throw TradingGuard.invalidQuantity }
        guard let serving else { throw TradingGuard.noAccount }
        return try await serving.closePosition(
            symbol: command.symbol,
            percentage: command.percentage,
            cancelOpenOrders: command.cancelOpenOrders
        )
    }

    func validate(
        _ order: NewOrder,
        serving: BrokerageServing?,
        tradingBlocked: Bool,
        protectionMinutes: Int,
        maxOrderValue: Double?
    ) throws {
        try guards(
            serving: serving,
            tradingBlocked: tradingBlocked,
            protectionMinutes: protectionMinutes
        )
        guard !order.symbol.isEmpty else { throw TradingGuard.invalidSymbol }
        try validateQuantity(order.quantity)
        switch order.kind {
        case .limit:
            try validatePrice(order.limitPrice)
            try validateNotional(quantity: order.quantity, price: order.limitPrice, maxOrderValue: maxOrderValue)
        case .stop:
            try validatePrice(order.stopPrice)
            try validateNotional(quantity: order.quantity, price: order.stopPrice, maxOrderValue: maxOrderValue)
        case .oto:
            try validatePrice(order.limitPrice)
            try validatePrice(order.takeProfitLimitPrice)
            guard let entry = order.limitPrice, let takeProfit = order.takeProfitLimitPrice else {
                throw TradingGuard.invalidPrice
            }
            if abs(entry - takeProfit) < OrderSizing.minimumPriceDelta {
                throw TradingGuard.otoSpread
            }
            try validateNotional(quantity: order.quantity, price: order.displayPrice, maxOrderValue: maxOrderValue)
        case .oco:
            try validatePrice(order.limitPrice)
            try validatePrice(order.stopPrice)
            guard let takeProfit = order.limitPrice, let stop = order.stopPrice else {
                throw TradingGuard.invalidPrice
            }
            if abs(takeProfit - stop) < OrderSizing.minimumPriceDelta {
                throw TradingGuard.otoSpread
            }
            let notionalPrice = max(takeProfit, stop)
            try validateNotional(quantity: order.quantity, price: notionalPrice, maxOrderValue: maxOrderValue)
        }
    }

    func remainingProtectionMinutes(_ minutes: Int) -> Int? {
        MarketClock.remainingOpeningProtectionMinutes(minutes: minutes, at: now())
    }

    private func guards(
        serving: BrokerageServing?,
        tradingBlocked: Bool,
        protectionMinutes: Int
    ) throws {
        guard serving != nil else { throw TradingGuard.noAccount }
        if tradingBlocked { throw TradingGuard.blocked }
        if let remaining = remainingProtectionMinutes(protectionMinutes) {
            throw TradingGuard.protected(minutes: remaining)
        }
    }

    private func validateQuantity(_ quantity: Double) throws {
        guard quantity.isFinite, quantity >= 1 else { throw TradingGuard.invalidQuantity }
    }

    private func validatePrice(_ price: Double?) throws {
        guard let price, price.isFinite, price > 0 else { throw TradingGuard.invalidPrice }
    }

    private func validateNotional(quantity: Double, price: Double?, maxOrderValue: Double?) throws {
        guard let maxOrderValue, maxOrderValue.isFinite, maxOrderValue > 0 else { return }
        guard let notional = OrderSizing.notional(quantity: quantity, price: price ?? 0) else {
            throw TradingGuard.invalidPrice
        }
        if notional > maxOrderValue {
            throw TradingGuard.maxOrderValue
        }
    }
}

enum TradingGuard {
    static let noAccount = AppError.http(
        status: 400,
        message: L10n.Trading.addCredentialsBody,
        errorCode: "TRADING_NO_ACCOUNT"
    )
    static let blocked = AppError.http(
        status: 400,
        message: L10n.Trading.blocked,
        errorCode: "TRADING_BLOCKED"
    )
    static let invalidQuantity = AppError.http(
        status: 400,
        message: L10n.Trading.invalidQuantity,
        errorCode: "TRADING_INVALID_QTY"
    )
    static let invalidPrice = AppError.http(
        status: 400,
        message: L10n.Trading.invalidPrice,
        errorCode: "TRADING_INVALID_PRICE"
    )
    static let invalidSymbol = AppError.http(
        status: 400,
        message: L10n.Trading.invalidSymbol,
        errorCode: "TRADING_INVALID_SYMBOL"
    )
    static let otoSpread = AppError.http(
        status: 400,
        message: L10n.Trading.otoSpread,
        errorCode: "TRADING_OTO_SPREAD"
    )
    static let maxOrderValue = AppError.http(
        status: 400,
        message: L10n.Trading.maxOrderValue,
        errorCode: "TRADING_MAX_VALUE"
    )
    static let noPosition = AppError.http(
        status: 400,
        message: L10n.Trading.noPosition,
        errorCode: "TRADING_NO_POSITION"
    )

    static func protectionRestoreFailed(symbol: String, error: Error) -> AppError {
        let detail = UserFacingError.message(from: error) ?? L10n.Errors.generic
        return AppError.http(
            status: 502,
            message: L10n.Trading.protectionRestoreFailed(symbol, detail),
            errorCode: "TRADING_RESTORE_FAILED"
        )
    }

    static func protected(minutes: Int) -> AppError {
        AppError.http(
            status: 400,
            message: L10n.Trading.protectionWindow(minutes),
            errorCode: "TRADING_PROTECTED"
        )
    }
}
