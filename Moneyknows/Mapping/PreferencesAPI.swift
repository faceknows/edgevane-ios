import Foundation

struct UserPreferenceDTO: Decodable, Equatable {
    var valuePerTrade: Double?
    var allowTradeInMinutesAfterOpen: Double?
    var showOTOAction: Bool?
    var showMarketTrade: Bool?
    var autoTakeProfitPercent: Double?
    var autoStopLossPercent: Double?
    var showDailyBarInDetail: Bool?
    var showIndexBarInDetail: Bool?
    var notificationVolumeThreshold: Double?
    var locale: String?
    var localeSpecified = false

    enum CodingKeys: String, CodingKey {
        case valuePerTrade
        case allowTradeInMinutesAfterOpen
        case showOTOAction
        case showMarketTrade
        case autoTakeProfitPercent
        case autoStopLossPercent
        case showDailyBarInDetail
        case showIndexBarInDetail
        case notificationVolumeThreshold
        case locale
        case data
    }

    init(
        valuePerTrade: Double? = nil,
        allowTradeInMinutesAfterOpen: Double? = nil,
        showOTOAction: Bool? = nil,
        showMarketTrade: Bool? = nil,
        autoTakeProfitPercent: Double? = nil,
        autoStopLossPercent: Double? = nil,
        showDailyBarInDetail: Bool? = nil,
        showIndexBarInDetail: Bool? = nil,
        notificationVolumeThreshold: Double? = nil,
        locale: String? = nil,
        localeSpecified: Bool = false
    ) {
        self.valuePerTrade = valuePerTrade
        self.allowTradeInMinutesAfterOpen = allowTradeInMinutesAfterOpen
        self.showOTOAction = showOTOAction
        self.showMarketTrade = showMarketTrade
        self.autoTakeProfitPercent = autoTakeProfitPercent
        self.autoStopLossPercent = autoStopLossPercent
        self.showDailyBarInDetail = showDailyBarInDetail
        self.showIndexBarInDetail = showIndexBarInDetail
        self.notificationVolumeThreshold = notificationVolumeThreshold
        self.locale = locale
        self.localeSpecified = localeSpecified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.data),
           let nested = try? container.decode(UserPreferenceDTO.self, forKey: .data) {
            self = nested
            return
        }
        valuePerTrade = try container.decodeIfPresent(Double.self, forKey: .valuePerTrade)
        allowTradeInMinutesAfterOpen = try container.decodeIfPresent(Double.self, forKey: .allowTradeInMinutesAfterOpen)
        showOTOAction = try container.decodeIfPresent(Bool.self, forKey: .showOTOAction)
        showMarketTrade = try container.decodeIfPresent(Bool.self, forKey: .showMarketTrade)
        autoTakeProfitPercent = try container.decodeIfPresent(Double.self, forKey: .autoTakeProfitPercent)
        autoStopLossPercent = try container.decodeIfPresent(Double.self, forKey: .autoStopLossPercent)
        showDailyBarInDetail = try container.decodeIfPresent(Bool.self, forKey: .showDailyBarInDetail)
        showIndexBarInDetail = try container.decodeIfPresent(Bool.self, forKey: .showIndexBarInDetail)
        notificationVolumeThreshold = try container.decodeIfPresent(Double.self, forKey: .notificationVolumeThreshold)
        localeSpecified = container.contains(.locale)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
    }

    static func decodeFlexible(from data: Data) throws -> UserPreferenceDTO {
        let decoder = HTTPClient.makeDecoder()
        if let envelope = try? decoder.decode(JSONEnvelope<UserPreferenceDTO>.self, from: data) {
            return envelope.data
        }
        if let dto = try? decoder.decode(UserPreferenceDTO.self, from: data) {
            return dto
        }
        throw AppError.decoding
    }
}

struct UserPreferencePatch: Encodable {
    var valuePerTrade: Double?
    var allowTradeInMinutesAfterOpen: Int?
    var showOTOAction: Bool?
    var showMarketTrade: Bool?
    var autoTakeProfitPercent: Double?
    var autoStopLossPercent: Double?
    var showDailyBarInDetail: Bool?
    var showIndexBarInDetail: Bool?
    var notificationVolumeThreshold: Int?
    var locale: LocalePatch?

    enum LocalePatch: Encodable {
        case followSystem
        case code(String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .followSystem:
                try container.encodeNil()
            case let .code(value):
                try container.encode(value)
            }
        }
    }
}

@MainActor
struct PreferencesAPI {
    var client: HTTPSending

    func fetch() async throws -> UserPreferenceDTO {
        let data = try await client.sendRaw(HTTPRequest(method: .get, path: "v1/users/preferences"))
        return try UserPreferenceDTO.decodeFlexible(from: data)
    }

    func patch(_ body: UserPreferencePatch) async throws -> UserPreferenceDTO {
        let data = try await client.sendRaw(
            HTTPRequest(method: .patch, path: "v1/users/preferences", body: body)
        )
        if data.isEmpty {
            return UserPreferenceDTO()
        }
        return try UserPreferenceDTO.decodeFlexible(from: data)
    }
}
