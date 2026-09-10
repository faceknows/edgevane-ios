import Foundation

struct BarsAPI {
    var client: HTTPSending

    func intraday(symbol: String, date: String, timeFrame: String = "1Min") async throws -> [BarDTO] {
        try await get("alpaca/market/intraday-bars", [
            "symbol": symbol,
            "date": date,
            "timeFrame": timeFrame,
        ])
    }

    func preMarket(symbol: String, date: String, timeFrame: String = "1Min") async throws -> [BarDTO] {
        try await get("alpaca/market/intraday/pre/bars", [
            "symbol": symbol,
            "date": date,
            "timeFrame": timeFrame,
        ])
    }

    func afterMarket(symbol: String, date: String, timeFrame: String = "1Min") async throws -> [BarDTO] {
        try await get("alpaca/market/intraday/after/bars", [
            "symbol": symbol,
            "date": date,
            "timeFrame": timeFrame,
        ])
    }

    func indexIntraday(symbol: String = "COMP", date: String, timeFrame: String = "1Min") async throws -> [BarDTO] {
        try await get("ibkr/market/intraday-bars", [
            "symbol": symbol,
            "date": date,
            "timeFrame": timeFrame,
        ])
    }

    func daily(symbol: String, startDate: String, timeFrame: String = "1Day", market: String = "us") async throws -> [BarDTO] {
        try await get("alpaca/market/daily-bars", [
            "symbol": symbol,
            "startDate": startDate,
            "timeFrame": timeFrame,
            "market": market,
        ])
    }

    func latestSnapshot(symbols: [String]) async throws -> Data {
        let joined = symbols.map(SymbolCode.normalize).filter { !$0.isEmpty }.joined(separator: ",")
        guard !joined.isEmpty else { return Data("{}".utf8) }
        return try await client.sendRaw(
            HTTPRequest(
                method: .get,
                path: "alpaca/market/latest-snapshot",
                query: ["symbols": joined]
            )
        )
    }

    private func get(_ path: String, _ query: [String: String]) async throws -> [BarDTO] {
        let data = try await client.sendRaw(HTTPRequest(method: .get, path: path, query: query))
        return try Self.decodeBars(from: data)
    }

    static func decodeBars(from data: Data) throws -> [BarDTO] {
        if let json = try? JSONSerialization.jsonObject(with: data),
           let bars = bars(fromJSON: json)
        {
            return bars
        }
        logDecodeFailure(data)
        throw AppError.decoding
    }

    /// RN `parseIntradayBars` keeps going when a slot is null or `bars` is keyed by symbol.
    /// JSONDecoder `[BarDTO]` throws on either, which the UI then shows as the generic error.
    private static func bars(fromJSON json: Any) -> [BarDTO]? {
        if json is NSNull {
            return []
        }
        if let array = json as? [Any] {
            return array.compactMap(barDTO(fromJSON:))
        }
        guard let object = json as? [String: Any] else { return nil }
        if let nested = object["data"], let bars = bars(fromJSON: nested) {
            return bars
        }
        if object.keys.contains("bars") {
            return bars(fromJSON: object["bars"] as Any) ?? bars(fromKeyedBars: object["bars"])
        }
        if object["symbol"] != nil || object["timeFrame"] != nil || object["startDate"] != nil {
            return []
        }
        return nil
    }

    private static func bars(fromKeyedBars raw: Any?) -> [BarDTO]? {
        guard let object = raw as? [String: Any] else { return nil }
        let flattened = object.values.flatMap { bars(fromJSON: $0) ?? [] }
        return flattened
    }

    private static func barDTO(fromJSON json: Any) -> BarDTO? {
        guard let object = json as? [String: Any] else { return nil }
        return BarDTO(
            d: stringValue(object["d"]) ?? stringValue(object["t"]),
            o: doubleValue(object["o"]),
            h: doubleValue(object["h"]),
            l: doubleValue(object["l"]),
            c: doubleValue(object["c"]),
            v: doubleValue(object["v"]),
            n: doubleValue(object["n"]),
            vw: doubleValue(object["vw"])
        )
    }

    private static func stringValue(_ raw: Any?) -> String? {
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = finiteNumber(raw) {
            if let exact = Int64(exactly: number) {
                return String(exact)
            }
            return String(number)
        }
        return nil
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        finiteNumber(raw)
    }

    private static func finiteNumber(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            let value = number.doubleValue
            return value.isFinite ? value : nil
        }
        if let value = raw as? Double, value.isFinite { return value }
        if let value = raw as? Float, value.isFinite { return Double(value) }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? Int64 { return Double(value) }
        if let value = raw as? UInt64 { return Double(value) }
        if let value = raw as? Decimal {
            let converted = NSDecimalNumber(decimal: value).doubleValue
            return converted.isFinite ? converted : nil
        }
        if let raw = raw as? String,
           let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           value.isFinite
        {
            return value
        }
        return nil
    }

    private static func logDecodeFailure(_ data: Data) {
        let keys: String
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            keys = object.keys.sorted().joined(separator: ",")
        } else if let _ = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            keys = "array"
        } else {
            keys = "invalid"
        }
        AppLog.market.error("bars decode failed keys \(keys, privacy: .public)")
    }
}
