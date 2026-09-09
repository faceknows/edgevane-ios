import Foundation

enum BrokerageEnvironment: String, Codable, CaseIterable, Equatable {
    case paper
    case live

    var host: URL {
        switch self {
        case .paper:
            return URL(string: "https://paper-api.alpaca.markets")!
        case .live:
            return URL(string: "https://api.alpaca.markets")!
        }
    }

    var streamURL: URL {
        switch self {
        case .paper:
            return URL(string: "wss://paper-api.alpaca.markets/stream")!
        case .live:
            return URL(string: "wss://api.alpaca.markets/stream")!
        }
    }
}

struct BrokerageAccount: Codable, Equatable {
    var id: String
    var provider: String
    var environment: BrokerageEnvironment
}

protocol BrokerageAccountValidating {
    func validate(key: String, secret: String, environment: BrokerageEnvironment) async throws -> BrokerageAccount
}
