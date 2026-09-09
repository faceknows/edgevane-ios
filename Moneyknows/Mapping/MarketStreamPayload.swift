import Foundation

enum MarketStreamPayload {
    static func trade(from data: Data) -> (symbol: String, price: Double)? {
        guard let object = json(data) else { return nil }
        if let price = number(object["p"]), let symbol = string(object["s"]) {
            return (SymbolCode.normalize(symbol), price)
        }
        if let trade = object["trade"] as? [String: Any],
           let price = number(trade["p"])
        {
            let symbol = string(object["symbol"]) ?? string(trade["s"])
            if let symbol {
                return (SymbolCode.normalize(symbol), price)
            }
        }
        return nil
    }

    static func quote(from data: Data) -> StreamQuote? {
        guard let object = json(data) else { return nil }
        if let quote = object["quote"] as? [String: Any] {
            let symbol = string(object["symbol"]) ?? string(quote["s"])
            return streamQuote(symbol: symbol, fields: quote)
        }
        return streamQuote(symbol: string(object["s"]), fields: object)
    }

    static func secondBar(from data: Data) -> StreamSecondBar? {
        guard let object = json(data) else { return nil }
        let nested = object["bar"] as? [String: Any]
        let fields = nested ?? object
        let symbol = string(object["symbol"]) ?? string(fields["s"])
        guard let symbol,
              let open = number(fields["o"]),
              let high = number(fields["h"]),
              let low = number(fields["l"]),
              let close = number(fields["c"])
        else {
            return nil
        }
        let rawTime = fields["t"] ?? fields["d"]
        let timeKey = string(rawTime)
            ?? string(object["generatedAt"])
            ?? string(object["second"])
        let time = date(rawTime)
            ?? timeKey.flatMap { BarTime.parse($0) }
            ?? date(object["receivedAt"])
            ?? date(object["generatedAt"])
            ?? Date()
        return StreamSecondBar(
            symbol: SymbolCode.normalize(symbol),
            time: time,
            timeKey: timeKey ?? String(Int(time.timeIntervalSince1970)),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: number(fields["v"]) ?? 0
        )
    }

    static func snapshotQuotes(from data: Data) -> [StreamQuote] {
        guard let object = json(data) else { return [] }
        let quotes = map(object["quotes"])
        return quotes.compactMap { symbol, value in
            guard let fields = value as? [String: Any] else { return nil }
            return streamQuote(symbol: symbol, fields: fields)
        }
    }

    static func snapshotTrades(from data: Data) -> [(symbol: String, price: Double)] {
        guard let object = json(data) else { return [] }
        let trades = map(object["trades"])
        return trades.compactMap { symbol, value in
            guard let fields = value as? [String: Any], let price = number(fields["p"]) else {
                return nil
            }
            return (SymbolCode.normalize(symbol), price)
        }
    }

    static func order(from data: Data) -> StreamOrder? {
        orders(from: data).first
    }

    static func orders(from data: Data) -> [StreamOrder] {
        dictionaries(from: data).compactMap(streamOrder(from:))
    }

    private static func streamOrder(from object: [String: Any]) -> StreamOrder? {
        guard let fields = orderFields(object) else { return nil }
        guard let id = string(fields["id"]), !id.isEmpty else { return nil }
        guard let symbol = string(fields["symbol"]), !symbol.isEmpty else { return nil }
        guard let side = string(fields["side"]) else { return nil }
        guard let type = string(fields["type"]) ?? string(fields["order_type"]) else { return nil }
        guard let status = string(fields["status"]) else { return nil }
        guard let qty = number(fields["qty"]) else { return nil }
        return StreamOrder(
            id: id,
            symbol: SymbolCode.normalize(symbol),
            side: side,
            type: type,
            status: status,
            qty: qty,
            filledQty: number(fields["filled_qty"]) ?? 0,
            limitPrice: number(fields["limit_price"]),
            stopPrice: number(fields["stop_price"]),
            filledAvgPrice: number(fields["filled_avg_price"]),
            timeInForce: string(fields["time_in_force"]),
            submittedAt: date(fields["submitted_at"]),
            updatedAt: date(fields["updated_at"]),
            createdAt: date(fields["created_at"]),
            filledAt: date(fields["filled_at"]),
            clientOrderId: string(fields["client_order_id"]),
            orderClass: string(fields["order_class"]),
            parentOrderId: string(fields["parent_order_id"])
        )
    }

    private static func orderFields(_ object: [String: Any]) -> [String: Any]? {
        if string(object["id"]) != nil, string(object["symbol"]) != nil {
            return object
        }
        if let order = object["order"] as? [String: Any] {
            return order
        }
        if let data = object["data"] as? [String: Any] {
            if let order = data["order"] as? [String: Any] {
                return order
            }
            if string(data["id"]) != nil, string(data["symbol"]) != nil {
                return data
            }
        }
        return nil
    }

    static func news(from data: Data, source: NewsSource, now: Date = Date()) -> NewsItem? {
        guard let object = json(data) else { return nil }
        let nested = object["news"] as? [String: Any]
        let fields = nested ?? object
        let symbols = stringArray(fields["symbols"])
        let symbol = string(fields["symbol"]).map(SymbolCode.normalize)
            ?? symbols.first
        let headline = HTMLText.decode(string(fields["headline"]) ?? string(fields["title"]))
        let summary = HTMLText.decode(
            string(fields["summary"])
                ?? string(fields["content"])
                ?? string(fields["body"])
                ?? string(fields["text"])
        )
        let defaultSource = source == .ibkr ? "IBKR" : nil
        let newsSource = string(fields["source"]) ?? defaultSource
        let url = string(fields["url"])
        let published = date(fields["timestamp"])
            ?? date(fields["publishedAt"])
            ?? date(fields["published_at"])
            ?? date(fields["created_at"])
            ?? date(fields["createdAt"])
        let idTime = published
            ?? date(fields["updated_at"])
            ?? date(fields["updatedAt"])
            ?? now
        let rawId = newsID(fields["id"])
            ?? newsID(fields["newsId"])
            ?? newsID(fields["guid"])
            ?? [symbol, headline, String(idTime.timeIntervalSince1970)]
            .compactMap { $0 }
            .joined(separator: ":")
        guard !rawId.isEmpty else { return nil }
        let id = source == .ibkr && !rawId.hasPrefix("ibkr:") ? "ibkr:\(rawId)" : rawId
        return NewsItem(
            id: id,
            symbol: symbol,
            headline: headline,
            summary: summary,
            source: newsSource,
            url: url,
            publishedAt: published,
            receivedAt: now
        )
    }

    private static func streamQuote(symbol: String?, fields: [String: Any]) -> StreamQuote? {
        guard let symbol else { return nil }
        let normalized = SymbolCode.normalize(symbol)
        guard !normalized.isEmpty else { return nil }
        return StreamQuote(
            symbol: normalized,
            bid: number(fields["bp"]),
            ask: number(fields["ap"]),
            bidSize: number(fields["bs"]),
            askSize: number(fields["as"])
        )
    }

    private static func json(_ data: Data) -> [String: Any]? {
        dictionaries(from: data).first
    }

    private static func dictionaries(from data: Data) -> [[String: Any]] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let dict = object as? [String: Any] {
            return [dict]
        }
        if let array = object as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func map(_ value: Any?) -> [String: Any] {
        guard let value = value as? [String: Any] else { return [:] }
        if let nested = value["quotes"] as? [String: Any] {
            return nested
        }
        if let nested = value["trades"] as? [String: Any] {
            return nested
        }
        return value
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let items = value as? [Any] else { return [] }
        return items.compactMap { string($0) }.map(SymbolCode.normalize).filter { !$0.isEmpty }
    }

    private static func newsID(_ value: Any?) -> String? {
        if let text = string(value) { return text }
        if value is Bool { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let value = number.doubleValue
            guard value.isFinite, value == value.rounded(),
                  value >= Double(Int64.min), value <= Double(Int64.max)
            else { return nil }
            return String(Int64(value))
        }
        if let value = value as? Int { return String(value) }
        if let value = value as? Int64 { return String(value) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let text = value as? String, let value = Double(text), value.isFinite { return value }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if value is Bool { return nil }
        if let value = value as? NSNumber {
            return unixDate(value.doubleValue)
        }
        if let value = value as? Double {
            return unixDate(value)
        }
        if let value = value as? Int {
            return unixDate(Double(value))
        }
        if let text = string(value) {
            return BarTime.parse(text)
        }
        return nil
    }

    private static func unixDate(_ value: Double) -> Date? {
        BarTime.parseUnix(value)
    }
}

struct StreamQuote: Equatable {
    var symbol: String
    var bid: Double?
    var ask: Double?
    var bidSize: Double?
    var askSize: Double?
}

struct StreamSecondBar: Equatable {
    var symbol: String
    var time: Date
    var timeKey: String
    var open: Double
    var high: Double
    var low: Double
    var close: Double
    var volume: Double
}

struct StreamOrder: Equatable {
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
