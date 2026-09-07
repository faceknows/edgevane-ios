import Foundation

struct AlpacaAccountDTO: Equatable {
    var id: String
    var tradingBlocked: Bool
    var equity: Double
    var lastEquity: Double
    var cash: Double
    var buyingPower: Double
    var portfolioValue: Double?
}

struct AlpacaPositionDTO: Equatable {
    var assetId: String?
    var symbol: String
    var qty: Double
    var side: String
    var avgEntryPrice: Double
    var currentPrice: Double
    var marketValue: Double
    var costBasis: Double
    var unrealizedPL: Double
    var unrealizedPLPercent: Double
}

struct AlpacaOrderDTO: Equatable {
    var id: String
    var symbol: String
    var side: String
    var type: String
    var status: String
    var qty: Double
    var filledQty: Double
    var limitPrice: Double?
    var stopPrice: Double?
    var filledAvgPrice: Double?
    var timeInForce: String?
    var submittedAt: Date?
    var updatedAt: Date?
    var createdAt: Date?
    var clientOrderId: String?
}

struct AlpacaOrderPage: Equatable {
    var orders: [AlpacaOrderDTO]
    var nextBeforeOrderId: String?
    var hasMore: Bool
}

struct AlpacaTradingAPI {
    var client: HTTPSending
    var openPageSize: Int = 500
    var maxOpenPages: Int = 20
    var maxOpenOrders: Int = 10_000

    func account() async throws -> AlpacaAccountDTO {
        let data = try await client.sendRaw(HTTPRequest(method: .get, path: "v2/account"))
        return try Self.decodeAccount(from: data)
    }

    func positions() async throws -> [AlpacaPositionDTO] {
        let data = try await client.sendRaw(HTTPRequest(method: .get, path: "v2/positions"))
        return try Self.decodePositions(from: data)
    }

    func openOrders() async throws -> [AlpacaOrderDTO] {
        try await fetchAllPaged(status: "open", pageSize: max(1, openPageSize))
    }

    func closedOrders(limit: Int, beforeOrderId: String? = nil) async throws -> AlpacaOrderPage {
        try await fetchOrderPage(status: "closed", limit: limit, beforeOrderId: beforeOrderId)
    }

    func order(id: String) async throws -> [AlpacaOrderDTO] {
        let data = try await client.sendRaw(HTTPRequest(method: .get, path: "v2/orders/\(id)"))
        return try Self.decodeOrder(from: data)
    }

    func cancel(orderId: String) async throws {
        try await client.send(HTTPRequest(method: .delete, path: "v2/orders/\(orderId)"))
    }

    static func decodeAccount(from data: Data) throws -> AlpacaAccountDTO {
        guard let object = jsonObject(data) else { throw AppError.decoding }
        let id = string(object["id"]) ?? ""
        guard !id.isEmpty else { throw AppError.decoding }
        return AlpacaAccountDTO(
            id: id,
            tradingBlocked: try requiredBool(object["trading_blocked"]),
            equity: try requiredNumber(object["equity"]),
            lastEquity: try requiredNumber(object["last_equity"]),
            cash: try requiredNumber(object["cash"]),
            buyingPower: try requiredNumber(object["buying_power"]),
            portfolioValue: number(object["portfolio_value"])
        )
    }

    static func decodePositions(from data: Data) throws -> [AlpacaPositionDTO] {
        try array(data).map { item in
            guard let object = item as? [String: Any] else { throw AppError.decoding }
            guard let symbol = symbol(object["symbol"]), !symbol.isEmpty else {
                throw AppError.decoding
            }
            guard let side = string(object["side"]) else { throw AppError.decoding }
            return AlpacaPositionDTO(
                assetId: string(object["asset_id"]),
                symbol: symbol,
                qty: try requiredNumber(object["qty"]),
                side: side,
                avgEntryPrice: try requiredNumber(object["avg_entry_price"]),
                currentPrice: try requiredNumber(object["current_price"]),
                marketValue: try requiredNumber(object["market_value"]),
                costBasis: try requiredNumber(object["cost_basis"]),
                unrealizedPL: try requiredNumber(object["unrealized_pl"]),
                unrealizedPLPercent: try requiredNumber(object["unrealized_plpc"])
            )
        }
    }

    static func decodeOrders(from data: Data) throws -> [AlpacaOrderDTO] {
        try uniqued(
            array(data).flatMap { item -> [AlpacaOrderDTO] in
                guard let object = item as? [String: Any] else { throw AppError.decoding }
                return try decodeOrderTree(object)
            }
        )
    }

    static func decodeOrder(from data: Data) throws -> [AlpacaOrderDTO] {
        guard let object = jsonObject(data) else { throw AppError.decoding }
        return try uniqued(decodeOrderTree(object))
    }

    static func decodeOrderPage(from data: Data, requestedLimit: Int) throws -> AlpacaOrderPage {
        let items = try array(data)
        var orders: [AlpacaOrderDTO] = []
        var seen = Set<String>()
        var lastTopLevelId: String?
        var topLevelCount = 0
        for item in items {
            guard let object = item as? [String: Any] else { throw AppError.decoding }
            let tree = try decodeOrderTree(object)
            guard let top = tree.first else { throw AppError.decoding }
            topLevelCount += 1
            lastTopLevelId = top.id
            for dto in tree where seen.insert(dto.id).inserted {
                orders.append(dto)
            }
        }
        let hasMore = topLevelCount >= requestedLimit
        if hasMore, lastTopLevelId == nil || lastTopLevelId?.isEmpty == true {
            throw AppError.decoding
        }
        return AlpacaOrderPage(
            orders: orders,
            nextBeforeOrderId: hasMore ? lastTopLevelId : nil,
            hasMore: hasMore
        )
    }

    private func fetchAllPaged(status: String, pageSize: Int) async throws -> [AlpacaOrderDTO] {
        var all: [AlpacaOrderDTO] = []
        var seenOrders = Set<String>()
        var seenCursors = Set<String>()
        var beforeOrderId: String?
        var pages = 0
        let pageCap = max(1, maxOpenPages)
        let orderCap = max(1, maxOpenOrders)
        while true {
            let cursor = beforeOrderId ?? ""
            if !seenCursors.insert(cursor).inserted {
                throw AppError.decoding
            }
            if pages >= pageCap {
                let probe = try await fetchOrderPage(status: status, limit: pageSize, beforeOrderId: beforeOrderId)
                if !probe.orders.isEmpty {
                    throw AppError.decoding
                }
                break
            }
            pages += 1
            let page = try await fetchOrderPage(status: status, limit: pageSize, beforeOrderId: beforeOrderId)
            for dto in page.orders where seenOrders.insert(dto.id).inserted {
                all.append(dto)
            }
            if all.count > orderCap {
                throw AppError.decoding
            }
            guard page.hasMore, let next = page.nextBeforeOrderId, !next.isEmpty else {
                break
            }
            beforeOrderId = next
        }
        return all
    }

    private func fetchOrderPage(status: String, limit: Int, beforeOrderId: String?) async throws -> AlpacaOrderPage {
        let data = try await sendOrders(status: status, limit: limit, beforeOrderId: beforeOrderId)
        return try Self.decodeOrderPage(from: data, requestedLimit: limit)
    }

    private func sendOrders(status: String, limit: Int, beforeOrderId: String?) async throws -> Data {
        var query = [
            "status": status,
            "limit": String(limit),
            "direction": "desc",
            "nested": "true",
        ]
        if let beforeOrderId, !beforeOrderId.isEmpty {
            query["before_order_id"] = beforeOrderId
        }
        return try await client.sendRaw(
            HTTPRequest(method: .get, path: "v2/orders", query: query)
        )
    }

    private static func decodeOrderTree(_ object: [String: Any]) throws -> [AlpacaOrderDTO] {
        var rows = [try decodeOrderFields(object)]
        if let legs = object["legs"] {
            guard let items = legs as? [Any] else { throw AppError.decoding }
            for item in items {
                guard let child = item as? [String: Any] else { throw AppError.decoding }
                rows.append(contentsOf: try decodeOrderTree(child))
            }
        }
        return rows
    }

    private static func decodeOrderFields(_ object: [String: Any]) throws -> AlpacaOrderDTO {
        guard let id = string(object["id"]), !id.isEmpty else { throw AppError.decoding }
        guard let symbol = symbol(object["symbol"]), !symbol.isEmpty else { throw AppError.decoding }
        guard let side = string(object["side"]) else { throw AppError.decoding }
        guard let type = string(object["type"]) ?? string(object["order_type"]) else {
            throw AppError.decoding
        }
        guard let status = string(object["status"]) else { throw AppError.decoding }
        let qty = try requiredNumber(object["qty"])
        let filledQty = number(object["filled_qty"])
        let filledAvgPrice = number(object["filled_avg_price"])
        try validateFillFields(status: status, qty: qty, filledQty: filledQty, filledAvgPrice: filledAvgPrice)
        return AlpacaOrderDTO(
            id: id,
            symbol: symbol,
            side: side,
            type: type,
            status: status,
            qty: qty,
            filledQty: filledQty ?? 0,
            limitPrice: number(object["limit_price"]),
            stopPrice: number(object["stop_price"]),
            filledAvgPrice: filledAvgPrice,
            timeInForce: string(object["time_in_force"]),
            submittedAt: parseTime(object["submitted_at"]),
            updatedAt: parseTime(object["updated_at"]),
            createdAt: parseTime(object["created_at"]),
            clientOrderId: string(object["client_order_id"])
        )
    }

    private static func validateFillFields(
        status: String,
        qty: Double,
        filledQty: Double?,
        filledAvgPrice: Double?
    ) throws {
        switch status.lowercased() {
        case "filled", "partially_filled":
            guard let filledQty, let filledAvgPrice else { throw AppError.decoding }
            guard filledQty > 0, filledQty <= qty, filledAvgPrice > 0 else { throw AppError.decoding }
        default:
            break
        }
    }

    private static func uniqued(_ orders: [AlpacaOrderDTO]) -> [AlpacaOrderDTO] {
        var seen = Set<String>()
        return orders.filter { seen.insert($0.id).inserted }
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func array(_ data: Data) throws -> [Any] {
        if let items = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            return items
        }
        throw AppError.decoding
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func symbol(_ value: Any?) -> String? {
        string(value)?.uppercased()
    }

    private static func parseTime(_ value: Any?) -> Date? {
        guard let raw = string(value) else { return nil }
        timeLock.lock()
        defer { timeLock.unlock() }
        if let date = isoFractional.date(from: raw) { return date }
        return isoInternet.date(from: raw)
    }

    private static let timeLock = NSLock()

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoInternet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func requiredNumber(_ value: Any?) throws -> Double {
        guard let value = number(value) else { throw AppError.decoding }
        return value
    }

    private static func requiredBool(_ value: Any?) throws -> Bool {
        guard let value else { throw AppError.decoding }
        let object = value as AnyObject
        if object === kCFBooleanTrue { return true }
        if object === kCFBooleanFalse { return false }
        throw AppError.decoding
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber, !(value is Bool) { return value.doubleValue }
        if let text = string(value), let value = Double(text), value.isFinite { return value }
        return nil
    }
}
