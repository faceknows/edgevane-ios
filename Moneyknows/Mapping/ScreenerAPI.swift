import Foundation

struct BarDTO: Decodable, Equatable {
    var d: String?
    var o: Double?
    var h: Double?
    var l: Double?
    var c: Double?
    var v: Double?
    var n: Double?
    var vw: Double?

    init(
        d: String? = nil,
        o: Double? = nil,
        h: Double? = nil,
        l: Double? = nil,
        c: Double? = nil,
        v: Double? = nil,
        n: Double? = nil,
        vw: Double? = nil
    ) {
        self.d = d
        self.o = o
        self.h = h
        self.l = l
        self.c = c
        self.v = v
        self.n = n
        self.vw = vw
    }

    enum CodingKeys: String, CodingKey {
        case d, o, h, l, c, v, n, vw, t
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        d = FlexibleJSON.decodeTimestampRaw(container, forKey: .d)
            ?? FlexibleJSON.decodeTimestampRaw(container, forKey: .t)
        o = FlexibleJSON.decodeDouble(container, forKey: .o)
        h = FlexibleJSON.decodeDouble(container, forKey: .h)
        l = FlexibleJSON.decodeDouble(container, forKey: .l)
        c = FlexibleJSON.decodeDouble(container, forKey: .c)
        v = FlexibleJSON.decodeDouble(container, forKey: .v)
        n = FlexibleJSON.decodeDouble(container, forKey: .n)
        vw = FlexibleJSON.decodeDouble(container, forKey: .vw)
    }
}

struct SnapshotDTO: Decodable, Equatable {
    var dailyBar: BarDTO?
    var prevDailyBar: BarDTO?
    var currentPrice: Double?
    var marketCap: Double?

    enum CodingKeys: String, CodingKey {
        case dailyBar, prevDailyBar, currentPrice, marketCap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dailyBar = try container.decodeIfPresent(BarDTO.self, forKey: .dailyBar)
        prevDailyBar = try container.decodeIfPresent(BarDTO.self, forKey: .prevDailyBar)
        currentPrice = FlexibleJSON.decodeDouble(container, forKey: .currentPrice)
        marketCap = FlexibleJSON.decodeDouble(container, forKey: .marketCap)
    }
}

struct LiteIndicatorsDTO: Decodable, Equatable {
    var rsi: Double?
    var adx: Double?
    var atr: Double?
    var ema: Double?
    var diPlus: Double?
    var diMinus: Double?

    enum CodingKeys: String, CodingKey {
        case rsi, adx, atr, ema, diPlus, diMinus, plusDI, minusDI
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rsi = FlexibleJSON.decodeDouble(container, forKey: .rsi)
        adx = FlexibleJSON.decodeDouble(container, forKey: .adx)
        atr = FlexibleJSON.decodeDouble(container, forKey: .atr)
        ema = FlexibleJSON.decodeDouble(container, forKey: .ema)
        diPlus = FlexibleJSON.decodeDouble(container, forKey: .diPlus)
            ?? FlexibleJSON.decodeDouble(container, forKey: .plusDI)
        diMinus = FlexibleJSON.decodeDouble(container, forKey: .diMinus)
            ?? FlexibleJSON.decodeDouble(container, forKey: .minusDI)
    }
}

struct SymbolSummaryDTO: Decodable, Equatable {
    var symbol: String
    var snapshot: SnapshotDTO?
    var indicators: LiteIndicatorsDTO?
    var atr: Double?

    enum CodingKeys: String, CodingKey {
        case symbol, snapshot, indicators, atr
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        snapshot = try container.decodeIfPresent(SnapshotDTO.self, forKey: .snapshot)
        indicators = try container.decodeIfPresent(LiteIndicatorsDTO.self, forKey: .indicators)
        atr = FlexibleJSON.decodeDouble(container, forKey: .atr)
    }
}

@MainActor
struct ScreenerAPI {
    var client: HTTPSending

    func summaries(market: String = "us", symbols: String) async throws -> [SymbolSummaryDTO] {
        try await get("stocks/summaries", [
            "market": market,
            "symbols": symbols,
        ])
    }

    func yahooScreener(market: String, scrIds: String, count: String) async throws -> [SymbolSummaryDTO] {
        try await get("intraday-stocks/yahoo/screener", [
            "market": market,
            "scrIds": scrIds,
            "count": count,
        ])
    }

    func topMomentum(query: [String: String]) async throws -> [SymbolSummaryDTO] {
        try await get("intraday-stocks/top-momentum", query)
    }

    func topATR(query: [String: String]) async throws -> [SymbolSummaryDTO] {
        try await get("intraday-stocks/top-atr-stocks", query)
    }

    func priceSlope(query: [String: String]) async throws -> [SymbolSummaryDTO] {
        try await get("intraday-stocks/price-slope", query)
    }

    func stairSetups(query: [String: String]) async throws -> [SymbolSummaryDTO] {
        try await get("intraday-stocks/top-stair-setups", query)
    }

    func rsiAdx(query: [String: String]) async throws -> [SymbolSummaryDTO] {
        try await get("intraday-stocks/indicators-rsi-adx", query)
    }

    func topVolumes(query: [String: String]) async throws -> [SymbolSummaryDTO] {
        try await get("intraday-stocks/top-volumes-increased", query)
    }

    func ibkrScreener(query: [String: String]) async throws -> [SymbolSummaryDTO] {
        try await get("intraday-stocks/ibkr/screener", query)
    }

    private func get(_ path: String, _ query: [String: String]) async throws -> [SymbolSummaryDTO] {
        let data = try await client.sendRaw(
            HTTPRequest(method: .get, path: path, query: compact(query))
        )
        return try Self.decodeList(from: data)
    }

    private func compact(_ query: [String: String]) -> [String: String] {
        query.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func decodeList(from data: Data) throws -> [SymbolSummaryDTO] {
        let decoder = HTTPClient.makeDecoder()
        if let items = try? decoder.decode([SymbolSummaryDTO].self, from: data) {
            return items
        }
        if let envelope = try? decoder.decode(JSONEnvelope<[SymbolSummaryDTO]>.self, from: data) {
            return envelope.data
        }
        if let record = try? decoder.decode([String: SymbolSummaryDTO].self, from: data) {
            return Array(record.values)
        }
        if let envelope = try? decoder.decode(JSONEnvelope<[String: SymbolSummaryDTO]>.self, from: data) {
            return Array(envelope.data.values)
        }
        throw AppError.decoding
    }
}
