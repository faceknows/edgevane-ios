import XCTest
@testable import Moneyknows

final class UserPreferencesTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(UserPreferences.defaults.valuePerTrade, 100)
        XCTAssertEqual(UserPreferences.defaults.allowTradeInMinutesAfterOpen, 30)
        XCTAssertFalse(UserPreferences.defaults.showMarketTrade)
        XCTAssertTrue(UserPreferences.defaults.showIndexBarInDetail)
        XCTAssertEqual(UserPreferences.defaults.autoTakeProfitPercent, 0)
        XCTAssertNil(UserPreferences.defaults.locale)
    }

    func testNormalizesProtectionAndVolume() {
        let dto = UserPreferenceDTO(
            valuePerTrade: 250,
            allowTradeInMinutesAfterOpen: 400,
            autoTakeProfitPercent: 2.5,
            autoStopLossPercent: -1,
            notificationVolumeThreshold: 1,
            locale: "zh",
            localeSpecified: true
        )
        let prefs = UserPreferences.normalized(from: dto)
        XCTAssertEqual(prefs.valuePerTrade, 250)
        XCTAssertEqual(prefs.allowTradeInMinutesAfterOpen, 300)
        XCTAssertEqual(prefs.autoTakeProfitPercent, 1)
        XCTAssertEqual(prefs.autoStopLossPercent, 0)
        XCTAssertEqual(prefs.notificationVolumeThreshold, 0)
        XCTAssertEqual(prefs.locale, .zh)
    }

    func testFollowSystemLocaleWhenNullSpecified() {
        let dto = UserPreferenceDTO(locale: nil, localeSpecified: true)
        let prefs = UserPreferences.normalized(from: dto, fallingBack: UserPreferences(
            valuePerTrade: 100,
            allowTradeInMinutesAfterOpen: 30,
            showOTOAction: false,
            showMarketTrade: false,
            autoTakeProfitPercent: 0,
            autoStopLossPercent: 0,
            showDailyBarInDetail: false,
            showIndexBarInDetail: true,
            notificationVolumeThreshold: 0,
            locale: .en
        ))
        XCTAssertNil(prefs.locale)
    }

    func testPreferenceEnvelopeDecode() throws {
        let json = #"{"success":true,"data":{"valuePerTrade":80,"locale":"en","showMarketTrade":true}}"#
        let dto = try UserPreferenceDTO.decodeFlexible(from: Data(json.utf8))
        XCTAssertEqual(dto.valuePerTrade, 80)
        XCTAssertEqual(dto.locale, "en")
        XCTAssertTrue(dto.localeSpecified)
        XCTAssertEqual(dto.showMarketTrade, true)
    }
}

final class RoleConfigurationTests: XCTestCase {
    func testDecodesEnvelopeAndEnabledFeatures() throws {
        let json = #"{"data":{"configuration":{"MAX_ORDER_VALUE":75,"SCANNERS":true,"ADMIN":false}}}"#
        let config = try RoleConfiguration.decodeFlexible(from: Data(json.utf8))
        XCTAssertEqual(config.maxOrderValue, 75)
        XCTAssertEqual(config.enabledFeatureKeys, ["SCANNERS"])
    }

    func testMissingMaxOrderValueIsNil() throws {
        let json = #"{"configuration":{"SCANNERS":true}}"#
        let config = try RoleConfiguration.decodeFlexible(from: Data(json.utf8))
        XCTAssertNil(config.maxOrderValue)
        XCTAssertEqual(config.enabledFeatureKeys, ["SCANNERS"])
    }

    func testRejectsInvalidLimitType() {
        let json = #"{"configuration":{"MAX_ORDER_VALUE":"big"}}"#
        XCTAssertThrowsError(try RoleConfiguration.decodeFlexible(from: Data(json.utf8)))
    }
}

@MainActor
final class AutoExitBlacklistTests: XCTestCase {
    func testAddAndRemoveNormalizedSymbols() {
        let folder = "MoneyknowsTests-blacklist-\(UUID().uuidString)"
        let store = AutoExitBlacklistStore(disk: DiskStore(folder: folder))
        store.prepareForUser("user-1")
        store.addTakeProfit(" aapl ")
        store.addTakeProfit("AAPL")
        store.addStopLoss("msft")
        XCTAssertEqual(store.values.takeProfit, ["AAPL"])
        XCTAssertTrue(store.isStopLossBlocked("Msft"))
        store.removeTakeProfit("aapl")
        XCTAssertTrue(store.values.takeProfit.isEmpty)
    }

    func testBlacklistIsIsolatedPerUserAndIgnoresGlobalFile() {
        let folder = "MoneyknowsTests-blacklist-\(UUID().uuidString)"
        let disk = DiskStore(folder: folder)
        disk.write(AutoExitBlacklist(takeProfit: ["LEAK"], stopLoss: ["LEAK"]), name: "auto-exit-blacklist.json")
        let store = AutoExitBlacklistStore(disk: disk)
        XCTAssertTrue(store.values.takeProfit.isEmpty)

        store.prepareForUser("user-a")
        store.addTakeProfit("AAPL")
        store.addStopLoss("MSFT")

        store.prepareForUser("user-b")
        XCTAssertTrue(store.values.takeProfit.isEmpty)
        XCTAssertTrue(store.values.stopLoss.isEmpty)
        store.addTakeProfit("TSLA")

        store.prepareForUser("user-a")
        XCTAssertEqual(store.values.takeProfit, ["AAPL"])
        XCTAssertEqual(store.values.stopLoss, ["MSFT"])

        store.resetSession()
        XCTAssertTrue(store.values.takeProfit.isEmpty)
        store.prepareForUser("user-a")
        XCTAssertEqual(store.values.takeProfit, ["AAPL"])
        XCTAssertFalse(store.isTakeProfitBlocked("LEAK"))
    }
}
