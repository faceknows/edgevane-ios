import Foundation

struct SubscriptionsDTO: Equatable {
    var all: [String]
    var me: [String]
}

struct SubscribeAPI {
    var client: HTTPSending

    func list() async throws -> SubscriptionsDTO {
        let data = try await client.sendRaw(
            HTTPRequest(method: .get, path: "alpaca/market/subscriptions")
        )
        return try Self.decodeList(from: data)
    }

    func subscribe(symbols: [String]) async throws {
        try await sendChange(path: "alpaca/market/subscribe", symbols: symbols)
    }

    func unsubscribe(symbols: [String]) async throws {
        try await sendChange(path: "alpaca/market/unsubscribe", symbols: symbols)
    }

    private func sendChange(path: String, symbols: [String]) async throws {
        try await client.send(
            HTTPRequest(
                method: .post,
                path: path,
                body: SymbolsBody(symbols: symbols)
            )
        )
    }

    static func decodeList(from data: Data) throws -> SubscriptionsDTO {
        let decoder = HTTPClient.makeDecoder()
        if let envelope = try? decoder.decode(JSONEnvelope<SubscriptionsBody>.self, from: data) {
            return envelope.data.normalized
        }
        if let payload = try? decoder.decode(SubscriptionsBody.self, from: data) {
            return payload.normalized
        }
        throw AppError.decoding
    }
}

private struct SymbolsBody: Encodable {
    var symbols: [String]
}

private struct SubscriptionsBody: Decodable {
    var all: [String]?
    var me: [String]?

    var normalized: SubscriptionsDTO {
        SubscriptionsDTO(all: Self.normalize(all), me: Self.normalize(me))
    }

    private static func normalize(_ symbols: [String]?) -> [String] {
        Array(Set((symbols ?? []).map(SymbolCode.normalize).filter { !$0.isEmpty })).sorted()
    }
}
