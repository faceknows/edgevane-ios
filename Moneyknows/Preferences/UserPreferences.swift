import Foundation

enum AppLocale: String, Codable, CaseIterable {
    case en
    case zh
}

struct UserPreferences: Equatable, Codable {
    var valuePerTrade: Double
    var allowTradeInMinutesAfterOpen: Int
    var showOTOAction: Bool
    var showMarketTrade: Bool
    var autoTakeProfitPercent: Double
    var autoStopLossPercent: Double
    var showDailyBarInDetail: Bool
    var showIndexBarInDetail: Bool
    var notificationVolumeThreshold: Int
    var locale: AppLocale?

    static let defaults = UserPreferences(
        valuePerTrade: 100,
        allowTradeInMinutesAfterOpen: 30,
        showOTOAction: false,
        showMarketTrade: false,
        autoTakeProfitPercent: 0,
        autoStopLossPercent: 0,
        showDailyBarInDetail: false,
        showIndexBarInDetail: true,
        notificationVolumeThreshold: 0,
        locale: nil
    )

    static let volumeThresholds = [0, 2, 3, 4, 5, 6, 7, 8]
    static let protectionMin = 0.1
    static let protectionMax = 1.0
    static let protectionDefault = 0.2

    var isAutoTakeProfitOn: Bool { autoTakeProfitPercent > 0 }
    var isAutoStopLossOn: Bool { autoStopLossPercent > 0 }

    static func normalized(from dto: UserPreferenceDTO, fallingBack fallback: UserPreferences = .defaults) -> UserPreferences {
        var next = fallback
        if let value = dto.valuePerTrade, value.isFinite, value > 0 {
            next.valuePerTrade = value
        }
        if let value = dto.allowTradeInMinutesAfterOpen, value.isFinite {
            next.allowTradeInMinutesAfterOpen = clamp(Int(value.rounded()), min: 0, max: 300)
        }
        if let value = dto.showOTOAction {
            next.showOTOAction = value
        }
        if let value = dto.showMarketTrade {
            next.showMarketTrade = value
        }
        if let value = dto.autoTakeProfitPercent {
            next.autoTakeProfitPercent = normalizeProtection(value)
        }
        if let value = dto.autoStopLossPercent {
            next.autoStopLossPercent = normalizeProtection(value)
        }
        if let value = dto.showDailyBarInDetail {
            next.showDailyBarInDetail = value
        }
        if let value = dto.showIndexBarInDetail {
            next.showIndexBarInDetail = value
        }
        if let value = dto.notificationVolumeThreshold, value.isFinite {
            next.notificationVolumeThreshold = normalizeVolumeThreshold(Int(value.rounded()))
        }
        if dto.localeSpecified {
            next.locale = AppLocale(rawValue: dto.locale ?? "")
        }
        return next
    }

    static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.min(max, Swift.max(min, value))
    }

    static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(max, Swift.max(min, value))
    }

    static func normalizeProtection(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return clamp(value, min: protectionMin, max: protectionMax)
    }

    static func protectionOrDefault(_ value: Double) -> Double {
        let normalized = normalizeProtection(value)
        return normalized > 0 ? normalized : protectionDefault
    }

    static func normalizeVolumeThreshold(_ value: Int) -> Int {
        volumeThresholds.contains(value) ? value : 0
    }

    static func clampValuePerTrade(_ value: Double, maxOrderValue: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaults.valuePerTrade }
        return Swift.min(value, maxOrderValue)
    }
}
