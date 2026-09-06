import Foundation

struct IntradayBarsDTO: Decodable {
    var symbol: String?
    var bars: [BarDTO]?
    var hasBarsKey = false

    enum CodingKeys: String, CodingKey {
        case symbol, bars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        hasBarsKey = container.contains(.bars)
        bars = try container.decodeIfPresent([BarDTO].self, forKey: .bars)
    }
}

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

    private func get(_ path: String, _ query: [String: String]) async throws -> [BarDTO] {
        let data = try await client.sendRaw(HTTPRequest(method: .get, path: path, query: query))
        return try Self.decodeBars(from: data)
    }

    static func decodeBars(from data: Data) throws -> [BarDTO] {
        let decoder = HTTPClient.makeDecoder()
        if let items = try? decoder.decode([BarDTO].self, from: data) {
            return items
        }
        if let envelope = try? decoder.decode(JSONEnvelope<[BarDTO]>.self, from: data) {
            return envelope.data
        }
        if let envelope = try? decoder.decode(JSONEnvelope<IntradayBarsDTO>.self, from: data) {
            if envelope.data.hasBarsKey || envelope.data.symbol != nil {
                return envelope.data.bars ?? []
            }
        }
        if let payload = try? decoder.decode(IntradayBarsDTO.self, from: data),
           payload.hasBarsKey || payload.symbol != nil
        {
            return payload.bars ?? []
        }
        throw AppError.decoding
    }
}
