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
    var filledAt: Date?
    var clientOrderId: String?
    var orderClass: String?
    var parentOrderId: String?
}

struct AlpacaOrderPage: Equatable {
    var orders: [AlpacaOrderDTO]
    var nextBeforeOrderId: String?
    var hasMore: Bool
}

struct AlpacaFillActivityDTO: Equatable {
    var id: String
    var orderId: String
    var symbol: String
    var side: String
    var qty: Double
    var price: Double
    var transactionTime: Date
}

struct FillActivityPage: Equatable {
    var fills: [AlpacaFillActivityDTO]
    var rawCount: Int
    var lastRawID: String?
}

struct AlpacaTradingAPI {
    var client: HTTPSending
    var openPageSize: Int = 500
    var maxOpenPages: Int = 20
    var maxOpenOrders: Int = 10_000
    var activityPageSize: Int = 100
    var maxActivityPages: Int = 20
    /// Alpaca `page_size` max is 100, so 20 pages is 2,000 account FILLs per Eastern day.
    var maxFillActivities: Int = 2_000

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

    func fillActivities(after: Date, until: Date) async throws -> [AlpacaFillActivityDTO] {
        var all: [AlpacaFillActivityDTO] = []
        var seenIDs = Set<String>()
        var seenTokens = Set<String>()
        var pageToken: String?
        var pages = 0
        let pageSize = min(100, max(1, activityPageSize))
        let pageCap = max(1, maxActivityPages)
        let fillCap = min(max(1, maxFillActivities), pageSize * pageCap)
        while true {
            let token = pageToken ?? ""
            if !seenTokens.insert(token).inserted {
                throw AppError.orderHistoryIncomplete
            }
            if pages >= pageCap {
                let probe = try await sendFillActivities(
                    after: after,
                    until: until,
                    limit: pageSize,
                    pageToken: pageToken
                )
                if probe.rawCount > 0 {
                    throw AppError.orderHistoryIncomplete
                }
                break
            }
            pages += 1
            let page = try await sendFillActivities(
                after: after,
                until: until,
                limit: pageSize,
                pageToken: pageToken
            )
            for dto in page.fills where seenIDs.insert(dto.id).inserted {
                all.append(dto)
            }
            if all.count > fillCap {
                throw AppError.orderHistoryIncomplete
            }
            guard page.rawCount >= pageSize, let next = page.lastRawID, !next.isEmpty else {
                break
            }
            pageToken = next
        }
        return all
    }

    func order(id: String) async throws -> [AlpacaOrderDTO] {
        let data = try await client.sendRaw(HTTPRequest(method: .get, path: "v2/orders/\(id)"))
        return try Self.decodeOrder(from: data)
    }

    func cancel(orderId: String) async throws {
        try await client.send(HTTPRequest(method: .delete, path: "v2/orders/\(orderId)"))
    }

    func place(_ order: NewOrder) async throws -> [AlpacaOrderDTO] {
        let data = try await client.sendRaw(
            HTTPRequest(method: .post, path: "v2/orders", body: AlpacaPlaceOrderBody(order))
        )
        return try Self.decodeOrder(from: data)
    }

    func replace(orderId: String, amendment: OrderAmendment) async throws -> [AlpacaOrderDTO] {
        let data = try await client.sendRaw(
            HTTPRequest(
                method: .patch,
                path: "v2/orders/\(orderId)",
                body: AlpacaReplaceOrderBody(amendment)
            )
        )
        return try Self.decodeOrder(from: data)
    }

    func closePosition(
        symbol: String,
        percentage: Double,
        cancelOpenOrders: Bool
    ) async throws -> [AlpacaOrderDTO] {
        let data = try await client.sendRaw(
            HTTPRequest(
                method: .delete,
                path: "v2/positions/\(SymbolCode.normalize(symbol))",
                query: [
                    "percentage": AlpacaNumberFormat.string(percentage),
                    "cancel_orders": cancelOpenOrders ? "true" : "false",
                ]
            )
        )
        if data.isEmpty { return [] }
        return try Self.decodeOrder(from: data)
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

    private func fetchAllPaged(
        status: String,
        pageSize: Int,
        symbols: String? = nil
    ) async throws -> [AlpacaOrderDTO] {
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
                let probe = try await fetchOrderPage(
                    status: status,
                    limit: pageSize,
                    beforeOrderId: beforeOrderId,
                    symbols: symbols
                )
                if !probe.orders.isEmpty {
                    throw AppError.decoding
                }
                break
            }
            pages += 1
            let page = try await fetchOrderPage(
                status: status,
                limit: pageSize,
                beforeOrderId: beforeOrderId,
                symbols: symbols
            )
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

    private func fetchOrderPage(
        status: String,
        limit: Int,
        beforeOrderId: String?,
        symbols: String? = nil,
        after: Date? = nil,
        until: Date? = nil
    ) async throws -> AlpacaOrderPage {
        let data = try await sendOrders(
            status: status,
            limit: limit,
            beforeOrderId: beforeOrderId,
            symbols: symbols,
            after: after,
            until: until
        )
        return try Self.decodeOrderPage(from: data, requestedLimit: limit)
    }

    private func sendOrders(
        status: String,
        limit: Int,
        beforeOrderId: String?,
        symbols: String? = nil,
        after: Date? = nil,
        until: Date? = nil
    ) async throws -> Data {
        var query = [
            "status": status,
            "limit": String(limit),
            "direction": "desc",
            "nested": "true",
        ]
        if let beforeOrderId, !beforeOrderId.isEmpty {
            query["before_order_id"] = beforeOrderId
        }
        if let symbols, !symbols.isEmpty {
            query["symbols"] = symbols
        }
        if let after {
            query["after"] = Self.formatTime(after)
        }
        if let until {
            query["until"] = Self.formatTime(until)
        }
        return try await client.sendRaw(
            HTTPRequest(method: .get, path: "v2/orders", query: query)
        )
    }

    private func sendFillActivities(
        after: Date,
        until: Date,
        limit: Int,
        pageToken: String?
    ) async throws -> FillActivityPage {
        var query = [
            "activity_types": "FILL",
            "page_size": String(limit),
            "direction": "desc",
            "after": Self.formatTime(after),
            "until": Self.formatTime(until),
        ]
        if let pageToken, !pageToken.isEmpty {
            query["page_token"] = pageToken
        }
        let data = try await client.sendRaw(
            HTTPRequest(method: .get, path: "v2/account/activities", query: query)
        )
        return try Self.decodeFillActivityPage(from: data)
    }

    static func decodeFillActivities(from data: Data) throws -> [AlpacaFillActivityDTO] {
        try decodeFillActivityPage(from: data).fills
    }

    static func decodeFillActivityPage(from data: Data) throws -> FillActivityPage {
        let items: [Any]
        do {
            items = try fillActivityItems(from: data)
        } catch {
            logFillDecodeFailure(data)
            throw error as? AppError ?? AppError.decoding
        }
        var fills: [AlpacaFillActivityDTO] = []
        var skipped = 0
        var firstSkip: (reason: String, keys: String)?
        for item in items {
            switch fillRow(fromJSON: item) {
            case let .fill(dto):
                fills.append(dto)
            case let .skip(reason, keys):
                skipped += 1
                if firstSkip == nil {
                    firstSkip = (reason, keys)
                }
            case .ignore:
                break
            }
        }
        if let firstSkip {
            AppLog.brokerage.error(
                "fill activities skipped \(skipped, privacy: .public) reason \(firstSkip.reason, privacy: .public) keys \(firstSkip.keys, privacy: .public)"
            )
        }
        if fills.isEmpty, skipped > 0 {
            throw AppError.orderHistoryIncomplete
        }
        return FillActivityPage(
            fills: fills,
            rawCount: items.count,
            lastRawID: lastRawActivityID(from: items)
        )
    }

    /// Null slots and non-FILL rows are ignored. An incomplete FILL is skipped so the rest of the page can load.
    private static func fillRow(fromJSON item: Any) -> FillRow {
        if item is NSNull { return .ignore }
        guard let object = item as? [String: Any] else {
            return .skip(reason: "non_object", keys: "value")
        }
        let keys = object.keys.sorted().joined(separator: ",")
        let activityType = string(object["activity_type"])?.uppercased()
        if let activityType, activityType != "FILL" {
            return .ignore
        }
        if activityType == nil {
            let kind = string(object["type"])?.lowercased()
            guard kind == "fill" || kind == "partial_fill" else { return .ignore }
        }
        guard let id = identifier(object["id"]), !id.isEmpty else {
            return .skip(reason: "missing_id", keys: keys)
        }
        guard let orderId = identifier(object["order_id"]), !orderId.isEmpty else {
            return .skip(reason: "missing_order_id", keys: keys)
        }
        guard let symbol = symbol(object["symbol"]), !symbol.isEmpty else {
            return .skip(reason: "missing_symbol", keys: keys)
        }
        guard let side = fillSide(object["side"]) else {
            let raw = string(object["side"]) ?? "missing"
            return .skip(reason: "invalid_side:\(raw)", keys: keys)
        }
        guard let qty = number(object["qty"]), qty > 0 else {
            return .skip(reason: "invalid_qty", keys: keys)
        }
        guard let price = number(object["price"]), price > 0 else {
            return .skip(reason: "invalid_price", keys: keys)
        }
        guard let transactionTime = parseTime(object["transaction_time"]) else {
            return .skip(reason: "invalid_transaction_time", keys: keys)
        }
        return .fill(
            AlpacaFillActivityDTO(
                id: id,
                orderId: orderId,
                symbol: symbol,
                side: side,
                qty: qty,
                price: price,
                transactionTime: transactionTime
            )
        )
    }

    private static func lastRawActivityID(from items: [Any]) -> String? {
        for item in items.reversed() {
            guard let object = item as? [String: Any],
                  let id = identifier(object["id"]), !id.isEmpty
            else { continue }
            return id
        }
        return nil
    }

    private enum FillRow {
        case fill(AlpacaFillActivityDTO)
        case skip(reason: String, keys: String)
        case ignore
    }

    private static func decodeOrderTree(
        _ object: [String: Any],
        inheritedClientId: String? = nil,
        inheritedOrderClass: String? = nil,
        inheritedParentId: String? = nil
    ) throws -> [AlpacaOrderDTO] {
        var row = try decodeOrderFields(object)
        if row.clientOrderId == nil, let inheritedClientId {
            row.clientOrderId = inheritedClientId
        }
        if row.orderClass == nil, let inheritedOrderClass {
            row.orderClass = inheritedOrderClass
        }
        if row.parentOrderId == nil, let inheritedParentId {
            row.parentOrderId = inheritedParentId
        }
        var rows = [row]
        if let items = try arrayValue(object["legs"]) {
            for item in items {
                guard let child = item as? [String: Any] else { throw AppError.decoding }
                rows.append(contentsOf: try decodeOrderTree(
                    child,
                    inheritedClientId: row.clientOrderId ?? inheritedClientId,
                    inheritedOrderClass: row.orderClass ?? inheritedOrderClass,
                    inheritedParentId: row.id
                ))
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
            filledAt: parseTime(object["filled_at"]),
            clientOrderId: string(object["client_order_id"]),
            orderClass: string(object["order_class"]),
            parentOrderId: string(object["parent_order_id"])
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

    /// Alpaca simple orders send `"legs": null`. JSON null is `NSNull`, which is not `nil`.
    private static func arrayValue(_ value: Any?) throws -> [Any]? {
        guard let value, !(value is NSNull) else { return nil }
        guard let items = value as? [Any] else { throw AppError.decoding }
        return items
    }

    private static func array(_ data: Data) throws -> [Any] {
        if let items = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            return items
        }
        throw AppError.decoding
    }

    private static func fillActivityItems(from data: Data) throws -> [Any] {
        if data.isEmpty { return [] }
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AppError.decoding
        }
        if json is NSNull { return [] }
        if let items = json as? [Any] { return items }
        if let object = json as? [String: Any] {
            for key in ["data", "activities"] {
                guard let nested = object[key] else { continue }
                if nested is NSNull { return [] }
                if let items = nested as? [Any] { return items }
            }
        }
        throw AppError.decoding
    }

    private static func logFillDecodeFailure(_ data: Data) {
        let keys: String
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            keys = object.keys.sorted().joined(separator: ",")
        } else if let items = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            keys = "array \(items.count)"
        } else {
            keys = "invalid"
        }
        AppLog.brokerage.error("fill activities decode failed keys \(keys, privacy: .public)")
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func symbol(_ value: Any?) -> String? {
        string(value)?.uppercased()
    }

    private static func identifier(_ value: Any?) -> String? {
        if let text = string(value) { return text }
        if let number = number(value), let exact = Int64(exactly: number) {
            return String(exact)
        }
        return nil
    }

    /// Order `side` is buy/sell. FILL activities also send `sell_short` (and similar prefixes).
    static func fillSide(_ value: Any?) -> String? {
        guard let raw = string(value)?.lowercased() else { return nil }
        if raw == "buy" || raw == "cover" || raw.hasPrefix("buy") { return "buy" }
        if raw == "sell" || raw == "short" || raw.hasPrefix("sell") { return "sell" }
        return nil
    }

    private static func parseTime(_ value: Any?) -> Date? {
        guard let raw = string(value) else { return nil }
        timeLock.lock()
        let fractional = isoFractional.date(from: raw)
        let internet = isoInternet.date(from: raw)
        timeLock.unlock()
        if let fractional { return fractional }
        if let internet { return internet }
        return BarTime.parse(raw)
    }

    private static func formatTime(_ date: Date) -> String {
        timeLock.lock()
        defer { timeLock.unlock() }
        return isoInternet.string(from: date)
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

enum AlpacaNumberFormat {
    static func string(_ value: Double) -> String {
        if value == value.rounded(), value >= Double(Int.min), value <= Double(Int.max) {
            return String(Int(value))
        }
        var text = String(format: "%.4f", value)
        while text.contains("."), text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    static func price(_ value: Double) -> String {
        let rounded = OrderSizing.roundPrice(value)
        if rounded >= 1 {
            return String(format: "%.2f", rounded)
        }
        return String(format: "%.4f", rounded)
    }
}

private struct AlpacaPlaceOrderBody: Encodable {
    var symbol: String
    var qty: String
    var side: String
    var type: String
    var timeInForce: String
    var limitPrice: String?
    var stopPrice: String?
    var extendedHours: Bool?
    var clientOrderId: String?
    var orderClass: String?
    var takeProfit: AlpacaTakeProfitBody?
    var stopLoss: AlpacaStopLossBody?

    init(_ order: NewOrder) {
        symbol = order.symbol
        qty = AlpacaNumberFormat.string(order.quantity)
        side = order.side.rawValue
        switch order.kind {
        case .limit, .oto:
            type = "limit"
        case .stop:
            type = "stop"
        case .oco:
            type = "limit"
        }
        timeInForce = order.timeInForce
        switch order.kind {
        case .oco:
            limitPrice = nil
            stopPrice = nil
        default:
            limitPrice = order.limitPrice.map(AlpacaNumberFormat.price)
            stopPrice = order.stopPrice.map(AlpacaNumberFormat.price)
        }
        extendedHours = order.extendedHours ? true : nil
        clientOrderId = order.clientOrderId
        if order.kind == .oto {
            orderClass = "oto"
            takeProfit = order.takeProfitLimitPrice.map { AlpacaTakeProfitBody(limitPrice: AlpacaNumberFormat.price($0)) }
        }
        if order.kind == .oco {
            orderClass = "oco"
            takeProfit = order.limitPrice.map { AlpacaTakeProfitBody(limitPrice: AlpacaNumberFormat.price($0)) }
            stopLoss = order.stopPrice.map { AlpacaStopLossBody(stopPrice: AlpacaNumberFormat.price($0)) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case qty
        case side
        case type
        case timeInForce = "time_in_force"
        case limitPrice = "limit_price"
        case stopPrice = "stop_price"
        case extendedHours = "extended_hours"
        case clientOrderId = "client_order_id"
        case orderClass = "order_class"
        case takeProfit = "take_profit"
        case stopLoss = "stop_loss"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(qty, forKey: .qty)
        try container.encode(side, forKey: .side)
        try container.encode(type, forKey: .type)
        try container.encode(timeInForce, forKey: .timeInForce)
        try container.encodeIfPresent(limitPrice, forKey: .limitPrice)
        try container.encodeIfPresent(stopPrice, forKey: .stopPrice)
        try container.encodeIfPresent(extendedHours, forKey: .extendedHours)
        try container.encodeIfPresent(clientOrderId, forKey: .clientOrderId)
        try container.encodeIfPresent(orderClass, forKey: .orderClass)
        try container.encodeIfPresent(takeProfit, forKey: .takeProfit)
        try container.encodeIfPresent(stopLoss, forKey: .stopLoss)
    }
}

private struct AlpacaTakeProfitBody: Encodable {
    var limitPrice: String

    enum CodingKeys: String, CodingKey {
        case limitPrice = "limit_price"
    }
}

private struct AlpacaStopLossBody: Encodable {
    var stopPrice: String

    enum CodingKeys: String, CodingKey {
        case stopPrice = "stop_price"
    }
}

private struct AlpacaReplaceOrderBody: Encodable {
    var qty: String?
    var limitPrice: String?
    var stopPrice: String?

    init(_ amendment: OrderAmendment) {
        qty = amendment.quantity.map(AlpacaNumberFormat.string)
        limitPrice = amendment.limitPrice.map(AlpacaNumberFormat.price)
        stopPrice = amendment.stopPrice.map(AlpacaNumberFormat.price)
    }

    enum CodingKeys: String, CodingKey {
        case qty
        case limitPrice = "limit_price"
        case stopPrice = "stop_price"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(qty, forKey: .qty)
        try container.encodeIfPresent(limitPrice, forKey: .limitPrice)
        try container.encodeIfPresent(stopPrice, forKey: .stopPrice)
    }
}
