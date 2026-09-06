import Foundation

struct AlpacaAccountDTO: Decodable, Equatable {
    var id: String
    var accountNumber: String?
    var status: String?
    var tradingBlocked: Bool?
}

struct AlpacaAccountValidator: BrokerageAccountValidating {
    var logsRequests: Bool
    var session: URLSession

    init(logsRequests: Bool = AppEnvironment.enableLogging, session: URLSession = .shared) {
        self.logsRequests = logsRequests
        self.session = session
    }

    func validate(key: String, secret: String, environment: BrokerageEnvironment) async throws -> BrokerageAccount {
        let client = HTTPClient(
            baseURL: environment.host,
            defaultHeaders: [
                "Accept": "application/json",
                "APCA-API-KEY-ID": key,
                "APCA-API-SECRET-KEY": secret,
            ],
            session: session,
            logsRequests: logsRequests,
            timeout: AppEnvironment.apiTimeout
        )
        let dto: AlpacaAccountDTO = try await client.send(HTTPRequest(method: .get, path: "v2/account"))
        AppLog.brokerage.info("validated alpaca \(environment.rawValue, privacy: .public)")
        return BrokerageAccount(id: dto.id, provider: "alpaca", environment: environment)
    }
}
