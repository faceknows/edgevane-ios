import UserNotifications
import XCTest
@testable import Moneyknows

final class NotificationHistoryTests: XCTestCase {
    func testDecodesBareArrayEnvelopeNotificationsAndItems() {
        let bare = Data(#"[{"id":"a","title":"A","body":"one","sentAt":1700000002000},{"id":"b","title":"B","body":"two","sentAt":1700000001000}]"#.utf8)
        XCTAssertEqual(PushAPI.decodeHistory(from: bare).map(\.id), ["a", "b"])

        let enveloped = Data(#"{"data":[{"id":1,"title":"N","body":"","sentAt":1700000000}]}"#.utf8)
        XCTAssertEqual(PushAPI.decodeHistory(from: enveloped).first?.id, "1")

        let named = Data(#"{"notifications":[{"_id":"x","notificationTitle":"Hi","notificationBody":"There","createdAt":1700000000}]}"#.utf8)
        XCTAssertEqual(PushAPI.decodeHistory(from: named).first?.id, "x")
        XCTAssertEqual(PushAPI.decodeHistory(from: named).first?.title, "Hi")

        let items = Data(#"{"items":[{"messageId":"m1","title":"T","body":"B","updatedAt":1700000000}]}"#.utf8)
        XCTAssertEqual(PushAPI.decodeHistory(from: items).first?.id, "m1")
    }

    func testKeepsIntegerIdWhenTitleChanges() {
        let first = NotificationHistory.normalize(
            ["id": 412345, "title": "First", "body": "", "sentAt": 1_700_000_000_000],
            index: 0
        )
        let updated = NotificationHistory.normalize(
            ["id": 412345, "title": "Changed", "body": "", "sentAt": 1_700_000_100_000],
            index: 1
        )
        XCTAssertEqual(first?.id, "412345")
        XCTAssertEqual(updated?.id, "412345")
    }

    func testNormalizesUnixSecondsToMilliseconds() {
        let item = NotificationHistory.normalize(
            ["id": "n", "title": "T", "body": "", "sentAt": 1_700_000_000],
            index: 0
        )
        XCTAssertEqual(item?.sentAt, 1_700_000_000_000)
    }
}

final class NotificationParserTests: XCTestCase {
    func testParsesBullishTrendReversalAndPreservesSymbolOrder() {
        let parsed = NotificationParser.parse(
            AppNotification(
                id: "1",
                title: "3 Trend Reversal Candidates",
                body: "AMD, NVDA, and TSLA met the bullish trend-reversal setup.",
                sentAt: 1,
                data: [
                    "type": NotificationKind.marketTrendUpReversal.rawValue,
                    "direction": "long",
                    "count": "3",
                    "symbols": " AMD, NVDA, ,TSLA ",
                    "longSymbols": "AMD, NVDA, TSLA",
                    "shortSymbols": "",
                    "prioritySymbols": " AMD ",
                ]
            )
        )
        XCTAssertEqual(parsed.kind, .marketTrendUpReversal)
        XCTAssertEqual(parsed.symbols, ["AMD", "NVDA", "TSLA"])
        XCTAssertEqual(parsed.longSymbols, ["AMD", "NVDA", "TSLA"])
        XCTAssertEqual(parsed.prioritySymbols, ["AMD"])
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(
            NotificationParser.titleKey(for: parsed),
            "notifications.marketTrendUpReversalTitle"
        )
    }

    func testParsesBearishTrendReversalAsShort() {
        let parsed = NotificationParser.parse(
            makeNotification(
                type: .marketTrendDownReversal,
                data: [
                    "type": NotificationKind.marketTrendDownReversal.rawValue,
                    "direction": "short",
                    "count": "1",
                    "symbols": "TSLA",
                    "shortSymbols": " TSLA ",
                ]
            )
        )
        XCTAssertEqual(parsed.kind, .marketTrendDownReversal)
        XCTAssertEqual(parsed.symbols, ["TSLA"])
        XCTAssertEqual(parsed.shortSymbols, ["TSLA"])
        XCTAssertEqual(
            NotificationParser.titleKey(for: parsed),
            "notifications.marketTrendDownReversalTitle"
        )
    }

    func testDirectionComesFromTypeNotPayload() {
        let up = NotificationParser.parse(
            makeNotification(
                type: .marketTrendUpReversal,
                data: ["type": NotificationKind.marketTrendUpReversal.rawValue, "direction": "short", "symbols": "AMD"]
            )
        )
        XCTAssertEqual(up.kind, .marketTrendUpReversal)
        let down = NotificationParser.parse(
            makeNotification(
                type: .marketTrendDownReversal,
                data: ["type": NotificationKind.marketTrendDownReversal.rawValue, "direction": "long", "symbols": "AMD"]
            )
        )
        XCTAssertEqual(down.kind, .marketTrendDownReversal)
    }

    func testParsesHighAndLowRetestSides() {
        let high = NotificationParser.parse(
            makeNotification(
                type: .intradayHighRetest,
                data: [
                    "type": NotificationKind.intradayHighRetest.rawValue,
                    "symbols": "AMD,NVDA",
                    "prioritySymbols": "AMD",
                    "shortSymbols": "NVDA",
                ]
            )
        )
        XCTAssertEqual(high.kind, .intradayHighRetest)
        XCTAssertEqual(NotificationParser.titleKey(for: high), "notifications.intradayHighRetestTitle")

        let low = NotificationParser.parse(
            makeNotification(
                type: .intradayLowRetest,
                data: ["type": NotificationKind.intradayLowRetest.rawValue, "symbols": "TSLA"]
            )
        )
        XCTAssertEqual(low.kind, .intradayLowRetest)
        XCTAssertEqual(NotificationParser.titleKey(for: low), "notifications.intradayLowRetestTitle")
    }

    func testParsesBreakoutAndWeakPullback() {
        let data = [
            "type": NotificationKind.intradayBreakout.rawValue,
            "symbols": "AMD,TSLA",
            "longSymbols": "AMD",
            "shortSymbols": "TSLA",
            "screen": "Markets",
        ]
        let breakout = NotificationParser.parse(makeNotification(type: .intradayBreakout, data: data))
        XCTAssertEqual(breakout.kind, .intradayBreakout)
        XCTAssertEqual(breakout.longSymbols, ["AMD"])
        XCTAssertEqual(breakout.shortSymbols, ["TSLA"])

        var pullbackData = data
        pullbackData["type"] = NotificationKind.intradayWeakPullback.rawValue
        let pullback = NotificationParser.parse(makeNotification(type: .intradayWeakPullback, data: pullbackData))
        XCTAssertEqual(pullback.kind, .intradayWeakPullback)
    }

    func testUnknownTypeKeepsBaseShape() {
        let parsed = NotificationParser.parse(
            AppNotification(
                id: "4",
                notificationType: "unknown_type",
                title: "Generic Notification",
                body: "watch AMD closely",
                sentAt: 1,
                data: ["symbols": "AMD"]
            )
        )
        XCTAssertNil(parsed.kind)
        XCTAssertEqual(parsed.rawType, "unknown_type")
        XCTAssertEqual(parsed.symbols, ["AMD"])
        XCTAssertNil(NotificationParser.titleKey(for: parsed))
    }

    func testTypeAndSymbolFilters() {
        let notifications = [
            makeNotification(id: "newest-up", type: .marketTrendUpReversal, sentAt: 3),
            makeNotification(id: "high", type: .intradayHighRetest, sentAt: 2),
            makeNotification(id: "older-up", type: .marketTrendUpReversal, sentAt: 1),
        ]
        XCTAssertEqual(NotificationParser.filter(notifications, type: nil).map(\.id), ["newest-up", "high", "older-up"])
        XCTAssertEqual(
            NotificationParser.filter(notifications, type: .marketTrendUpReversal).map(\.id),
            ["newest-up", "older-up"]
        )

        let withSymbols = [
            AppNotification(id: "amd-nvda", title: "AMD and NVDA", body: "", sentAt: 2, data: ["symbols": "AMD,NVDA"]),
            AppNotification(id: "tsla", title: "TSLA", body: "", sentAt: 1, data: ["symbol": "TSLA"]),
        ]
        XCTAssertEqual(NotificationParser.filter(withSymbols, symbols: "  ").map(\.id), ["amd-nvda", "tsla"])
        XCTAssertEqual(NotificationParser.filter(withSymbols, symbols: "tsla, amd").map(\.id), ["amd-nvda", "tsla"])
    }
}

final class NotificationDestinationTests: XCTestCase {
    func testSingleSymbolOpensDetailEvenWithMarketsScreen() {
        let destination = NotificationParser.destination(
            for: makeNotification(
                type: .intradayBreakout,
                data: [
                    "type": NotificationKind.intradayBreakout.rawValue,
                    "symbols": "AMD",
                    "screen": "Markets",
                ]
            )
        )
        XCTAssertEqual(destination, .symbol("AMD"))
    }

    func testTrendOrHighLowWithMarketsOpensCatalogEvenForSingleSymbol() {
        let low = NotificationParser.destination(
            for: makeNotification(
                type: .intradayLowRetest,
                data: [
                    "type": NotificationKind.intradayLowRetest.rawValue,
                    "symbols": "TSLA",
                    "screen": "Markets",
                ]
            )
        )
        XCTAssertEqual(low, .screenerCatalog(symbols: ["TSLA"]))
    }

    func testTrendAndHighLowWithMultipleSymbolsAndMarketsOpenCatalogChips() {
        let cases: [(NotificationKind, String)] = [
            (.intradayHighRetest, "AMD,NVDA"),
            (.marketTrendUpReversal, " AMD, NVDA "),
            (.marketTrendDownReversal, "TSLA,AMD"),
        ]
        for (type, symbols) in cases {
            let destination = NotificationParser.destination(
                for: makeNotification(
                    type: type,
                    data: [
                        "type": type.rawValue,
                        "symbols": symbols,
                        "screen": "Markets",
                    ]
                )
            )
            XCTAssertEqual(
                destination,
                .screenerCatalog(symbols: NotificationParser.extractSymbols(from: symbols)),
                file: #filePath,
                line: #line
            )
        }
    }

    func testMultiSymbolBreakoutWithMarketsOpensNotificationCenter() {
        let destination = NotificationParser.destination(
            for: makeNotification(
                type: .intradayBreakout,
                data: [
                    "type": NotificationKind.intradayBreakout.rawValue,
                    "symbols": "AMD,TSLA",
                    "longSymbols": "AMD",
                    "shortSymbols": "TSLA",
                    "screen": "Markets",
                ]
            )
        )
        XCTAssertEqual(destination, .notifications)
    }

    func testFallbackIsNotificationCenter() {
        let destination = NotificationParser.destination(
            for: AppNotification(
                id: "fallback",
                title: "Pullback batch",
                body: "AMD and NVDA setup",
                sentAt: 1,
                data: ["type": "unknown_type", "symbols": "AMD,NVDA"]
            )
        )
        XCTAssertEqual(destination, .notifications)
    }
}

final class NotificationVolumeTests: XCTestCase {
    func testThresholdZeroPassesAllAndMissingVolumePasses() {
        let low = AppNotification(id: "low", title: "t", body: "", sentAt: 1, data: ["volume": "1"])
        let high = AppNotification(id: "high", title: "t", body: "", sentAt: 2, data: ["volume": "5"])
        let missing = AppNotification(id: "missing", title: "t", body: "", sentAt: 3, data: ["symbols": "AMD"])
        XCTAssertTrue(NotificationVolume.passes(low, threshold: 0))
        XCTAssertTrue(NotificationVolume.passes(missing, threshold: 4))
        XCTAssertFalse(NotificationVolume.passes(low, threshold: 4))
        XCTAssertTrue(NotificationVolume.passes(high, threshold: 4))
        XCTAssertEqual(NotificationVolume.filter([low, high, missing], threshold: 4).map(\.id), ["high", "missing"])
    }
}

@MainActor
final class NotificationStoreAndPushTests: XCTestCase {
    func testHistoryRetriesLastTimeAsSecondsWhenMillisecondsReturnEmpty() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data("[]".utf8)),
            .success(Data(#"[{"id":"n1","title":"T","body":"","sentAt":1700000000}]"#.utf8)),
        ]
        let api = PushAPI(client: http)
        let items = try await api.history(limit: 20, lastTime: 1_700_000_000_000)
        XCTAssertEqual(items.first?.id, "n1")
        XCTAssertEqual(http.requests.map(\.query["lastTime"]), ["1700000000000", "1700000000"])
    }

    func testFirstInstallRequestsPermissionBeforeRemoteRegistration() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let auth = FakeNotificationAuthorization(status: .notDetermined, requestGranted: true)
        let preference = PushPreferenceStore(defaults: defaults, authorization: auth)
        XCTAssertTrue(preference.isEnabled)
        let allowed = await preference.prepareForPush()
        XCTAssertTrue(allowed)
        XCTAssertEqual(auth.requestCount, 1)
        XCTAssertEqual(auth.registerCount, 0)
        XCTAssertFalse(preference.permissionDenied)

        let push = PushRegistration(
            api: PushAPI(client: ScriptedHTTP()),
            publicClient: ScriptedHTTP(),
            preference: preference,
            tokens: FakePushTokenProvider()
        )
        await push.registerIfNeeded()
        XCTAssertEqual(auth.registerCount, 1)
    }

    func testFirstInstallDenialTurnsSwitchOffAndDoesNotRegisterRemote() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let auth = FakeNotificationAuthorization(status: .notDetermined, requestGranted: false)
        let preference = PushPreferenceStore(defaults: defaults, authorization: auth)
        let allowed = await preference.prepareForPush()
        XCTAssertFalse(allowed)
        XCTAssertFalse(preference.isEnabled)
        XCTAssertTrue(preference.permissionDenied)
        XCTAssertEqual(auth.requestCount, 1)
        XCTAssertEqual(auth.registerCount, 0)
    }

    func testDeniedStatusDoesNotRepromptAndDisabledSwitchDoesNotPrompt() async {
        let deniedDefaults = UserDefaults(suiteName: UUID().uuidString)!
        deniedDefaults.set(true, forKey: "push_notifications_enabled")
        let deniedAuth = FakeNotificationAuthorization(status: .denied, requestGranted: true)
        let denied = PushPreferenceStore(defaults: deniedDefaults, authorization: deniedAuth)
        let deniedAllowed = await denied.prepareForPush()
        XCTAssertFalse(deniedAllowed)
        XCTAssertEqual(deniedAuth.requestCount, 0)
        XCTAssertTrue(denied.permissionDenied)

        let offDefaults = UserDefaults(suiteName: UUID().uuidString)!
        offDefaults.set(false, forKey: "push_notifications_enabled")
        let offAuth = FakeNotificationAuthorization(status: .notDetermined, requestGranted: true)
        let off = PushPreferenceStore(defaults: offDefaults, authorization: offAuth)
        let offAllowed = await off.prepareForPush()
        XCTAssertFalse(offAllowed)
        XCTAssertEqual(offAuth.requestCount, 0)
    }

    func testRefreshRegistersIosPlatformAndLogoutUnregistersAndClearsCache() async throws {
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/users/fcm-token": Data(#"{"success":true,"message":"ok"}"#.utf8),
            "v1/notifications/history": Data(#"[{"id":"keep","title":"T","body":"","sentAt":1,"data":{"volume":"8"}}]"#.utf8),
        ]
        let folder = "NotificationStoreTests-\(UUID().uuidString)"
        let disk = DiskStore(folder: folder)
        let store = NotificationStore(api: PushAPI(client: http), disk: disk)
        store.activate(userId: "user-1")
        await store.refresh(userId: "user-1")
        XCTAssertEqual(store.items.map(\.id), ["keep"])
        XCTAssertEqual(store.visibleItems(volumeThreshold: 4).map(\.id), ["keep"])

        let (preference, _) = makeEnabledPushPreference()
        let tokens = FakePushTokenProvider(token: "fcm-abc")
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: tokens
        )
        await push.registerIfNeeded()
        let register = try jsonObject(from: http.requests.first { $0.method == .post && $0.path == "v1/users/fcm-token" }!)
        XCTAssertEqual(register["token"] as? String, "fcm-abc")
        XCTAssertEqual(register["platform"] as? String, "ios")
        XCTAssertEqual(register["deviceId"] as? String, "fcm-abc")
        XCTAssertTrue(push.isRegistered)

        store.reset()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.isActive)
        XCTAssertNil(disk.read([AppNotification].self, name: NotificationStore.cacheName(for: "user-1")))

        await push.unregister()
        XCTAssertTrue(http.requests.contains { $0.method == .delete && $0.path == "v1/users/fcm-token" })
        XCTAssertFalse(push.isRegistered)
    }

    func testStaleRegisterAfterUnregisterSendsCompensatingDelete() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/users/fcm-token": Data(#"{"success":true,"message":"ok"}"#.utf8),
        ]
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc")
        )
        http.pauseSends = true
        let registerTask = Task { await push.registerIfNeeded() }
        await waitUntil {
            http.requests.contains { $0.method == .post && $0.path == "v1/users/fcm-token" }
        }
        let unregisterTask = Task { await push.unregister() }
        await Task.yield()
        XCTAssertFalse(http.requests.contains { $0.method == .delete && $0.path == "v1/users/fcm-token" })
        http.releasePaused()
        await registerTask.value
        await unregisterTask.value
        XCTAssertFalse(push.isRegistered)
        let tokenCalls = http.requests.filter { $0.path == "v1/users/fcm-token" }
        XCTAssertEqual(tokenCalls.map(\.method), [.post, .delete])
    }

    func testStaleUnregisterAfterReregisterLeavesTokenRegistered() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/users/fcm-token": Data(#"{"success":true,"message":"ok"}"#.utf8),
        ]
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc")
        )
        await push.registerIfNeeded()
        XCTAssertTrue(push.isRegistered)

        http.pauseSends = true
        let unregisterTask = Task { await push.unregister() }
        await waitUntil {
            http.requests.contains { $0.method == .delete && $0.path == "v1/users/fcm-token" }
        }
        let registerTask = Task { await push.registerIfNeeded() }
        await Task.yield()
        XCTAssertEqual(
            http.requests.filter { $0.path == "v1/users/fcm-token" }.map(\.method),
            [.post, .delete]
        )
        http.releasePaused()
        await unregisterTask.value
        await registerTask.value
        XCTAssertTrue(push.isRegistered)
        XCTAssertEqual(
            http.requests.filter { $0.path == "v1/users/fcm-token" }.map(\.method),
            [.post, .delete, .post]
        )
    }

    func testIngestAfterResetDoesNotRewriteCache() {
        let folder = "NotificationIngestReset-\(UUID().uuidString)"
        let disk = DiskStore(folder: folder)
        let store = NotificationStore(api: PushAPI(client: ScriptedHTTP()), disk: disk)
        store.activate(userId: "user-1")
        let item = AppNotification(id: "keep", userId: "user-1", title: "T", body: "", sentAt: 1)
        store.ingest(item, showToast: true, volumeThreshold: 0)
        XCTAssertEqual(store.items.map(\.id), ["keep"])
        store.reset()
        store.ingest(item, showToast: true, volumeThreshold: 0)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.toast)
        XCTAssertNil(disk.read([AppNotification].self, name: NotificationStore.cacheName(for: "user-1")))
    }

    func testIngestIsDroppedUntilStoreIsActivated() {
        let folder = "NotificationActivate-\(UUID().uuidString)"
        let store = NotificationStore(api: PushAPI(client: ScriptedHTTP()), disk: DiskStore(folder: folder))
        let item = AppNotification(id: "n1", userId: "user-1", title: "T", body: "", sentAt: 1)
        store.ingest(item, showToast: true, volumeThreshold: 0, userId: "user-1")
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.toast)

        store.activate(userId: "user-1")
        store.ingest(item, showToast: true, volumeThreshold: 0, userId: "user-1")
        XCTAssertEqual(store.items.map(\.id), ["n1"])
        XCTAssertEqual(store.toast?.id, "n1")
    }

    func testRefreshClearsStuckLoadMore() async {
        let http = ScriptedHTTP()
        let page = (0..<20).map { #"{"id":"n\#($0)","title":"T","body":"","sentAt":\#(100 - $0)}"# }.joined(separator: ",")
        http.rawResults = [
            .success(Data("[\(page)]".utf8)),
            .success(Data(#"[{"id":"more","title":"T","body":"","sentAt":1}]"#.utf8)),
            .success(Data("[\(page)]".utf8)),
            .success(Data(#"[{"id":"later","title":"T","body":"","sentAt":1}]"#.utf8)),
        ]
        let store = NotificationStore(api: PushAPI(client: http), disk: DiskStore(folder: "NotificationLoadMore-\(UUID().uuidString)"))
        store.activate(userId: "user-1")
        await store.refresh(userId: "user-1")
        XCTAssertTrue(store.hasMore)
        http.pauseSends = true
        let more = Task { await store.loadMore(userId: "user-1") }
        await waitUntil { store.isLoadingMore }
        http.pauseSends = false
        await store.refresh(userId: "user-1")
        XCTAssertFalse(store.isLoadingMore)
        http.releasePaused()
        await more.value
        XCTAssertFalse(store.isLoadingMore)
        await store.loadMore(userId: "user-1")
        XCTAssertTrue(http.requests.filter { $0.path == "v1/notifications/history" }.count >= 4)
    }

    func testVolumeFilterAppliesToToastAndListTheSameWay() {
        let folder = "NotificationToastTests-\(UUID().uuidString)"
        let store = NotificationStore(api: PushAPI(client: ScriptedHTTP()), disk: DiskStore(folder: folder))
        store.activate(userId: "user-1")
        let low = AppNotification(id: "low", userId: "user-1", title: "Low", body: "x", sentAt: 2, data: ["volume": "1"])
        let high = AppNotification(id: "high", userId: "user-1", title: "High", body: "y", sentAt: 3, data: ["volume": "6"])
        store.ingest(low, showToast: true, volumeThreshold: 4)
        XCTAssertNil(store.toast)
        store.ingest(high, showToast: true, volumeThreshold: 4)
        XCTAssertEqual(store.toast?.id, "high")
        XCTAssertEqual(store.visibleItems(volumeThreshold: 4).map(\.id), ["high"])
        XCTAssertEqual(store.items.map(\.id), ["high", "low"])
        XCTAssertTrue(store.hasActiveFilters(volumeThreshold: 4))
        XCTAssertFalse(store.hasActiveFilters(volumeThreshold: 0))
    }

    func testPendingDeepLinkWaitsForVersionAndSignIn() {
        let router = AppRouter()
        let notification = makeNotification(
            type: .intradayBreakout,
            data: ["type": NotificationKind.intradayBreakout.rawValue, "symbols": "AMD"]
        )
        router.handleNotification(notification, versionPassed: false, signedIn: false)
        XCTAssertNil(router.overlay)
        XCTAssertEqual(router.pendingNotification, .symbol("AMD"))

        router.consumePending(versionPassed: false, signedIn: true)
        XCTAssertNil(router.overlay)
        XCTAssertEqual(router.pendingNotification, .symbol("AMD"))

        router.consumePending(versionPassed: true, signedIn: false)
        XCTAssertNil(router.overlay)

        router.consumePending(versionPassed: true, signedIn: true)
        XCTAssertEqual(router.overlay, .symbol("AMD"))
        XCTAssertNil(router.pendingNotification)
    }

    func testPendingDeepLinkIsIsolatedByUserId() {
        let router = AppRouter()
        let notification = AppNotification(
            id: "owned",
            userId: "user-a",
            title: "T",
            body: "",
            sentAt: 1,
            data: ["type": NotificationKind.intradayBreakout.rawValue, "symbols": "AMD", "userId": "user-a"]
        )
        router.handleNotification(notification, versionPassed: true, signedIn: false)
        XCTAssertEqual(router.pendingNotification, .symbol("AMD"))
        XCTAssertEqual(router.pendingNotificationUserId, "user-a")

        router.consumePending(versionPassed: true, signedIn: true, currentUserId: "user-b")
        XCTAssertNil(router.overlay)
        XCTAssertNil(router.pendingNotification)

        router.handleNotification(notification, versionPassed: true, signedIn: false)
        router.consumePending(versionPassed: true, signedIn: true, currentUserId: "user-a")
        XCTAssertEqual(router.overlay, .symbol("AMD"))

        router.dismissOverlay()
        router.handleNotification(
            notification,
            versionPassed: true,
            signedIn: true,
            currentUserId: "user-b"
        )
        XCTAssertNil(router.overlay)
    }

    func testIngestIgnoresOtherUserAndKeepsPerUserCache() {
        let folder = "NotificationUserIsolation-\(UUID().uuidString)"
        let disk = DiskStore(folder: folder)
        let store = NotificationStore(api: PushAPI(client: ScriptedHTTP()), disk: disk)
        store.activate(userId: "user-a")
        store.ingest(
            AppNotification(id: "a1", userId: "user-a", title: "A", body: "", sentAt: 2),
            showToast: false,
            volumeThreshold: 0,
            userId: "user-a"
        )
        store.ingest(
            AppNotification(id: "b1", userId: "user-b", title: "B", body: "", sentAt: 3),
            showToast: true,
            volumeThreshold: 0,
            userId: "user-a"
        )
        XCTAssertEqual(store.items.map(\.id), ["a1"])
        XCTAssertNil(store.toast)
        XCTAssertEqual(
            disk.read([AppNotification].self, name: NotificationStore.cacheName(for: "user-a"))?.map(\.id),
            ["a1"]
        )

        store.activate(userId: "user-b")
        XCTAssertTrue(store.items.isEmpty)
        store.ingest(
            AppNotification(id: "b1", userId: "user-b", title: "B", body: "", sentAt: 3),
            showToast: false,
            volumeThreshold: 0,
            userId: "user-b"
        )
        XCTAssertEqual(store.items.map(\.id), ["b1"])
        XCTAssertEqual(
            disk.read([AppNotification].self, name: NotificationStore.cacheName(for: "user-a"))?.map(\.id),
            ["a1"]
        )
    }

    func testTokenRefreshRegistersNewTokenAndDeletesPrevious() async throws {
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/users/fcm-token": Data(#"{"success":true,"message":"ok"}"#.utf8),
        ]
        let (preference, _) = makeEnabledPushPreference()
        let tokens = FakePushTokenProvider(token: "fcm-a")
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: tokens
        )
        await push.registerIfNeeded()
        tokens.token = "fcm-b"
        await push.handleTokenRefresh("fcm-b", signedIn: true)
        XCTAssertTrue(push.isRegistered)
        let tokenCalls = http.requests.filter { $0.path == "v1/users/fcm-token" }
        XCTAssertEqual(tokenCalls.map(\.method), [.post, .delete, .post])
        XCTAssertEqual(try jsonObject(from: tokenCalls[0])["token"] as? String, "fcm-a")
        XCTAssertEqual(try jsonObject(from: tokenCalls[1])["token"] as? String, "fcm-a")
        XCTAssertEqual(try jsonObject(from: tokenCalls[2])["token"] as? String, "fcm-b")
    }

    func testFailedDeleteIsRetriedOnNetworkRecovery() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .failure(AppError.network),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc")
        )
        await push.registerIfNeeded()
        await push.unregister()
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 1)
        await push.retryIfNeeded()
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 2)
        XCTAssertFalse(push.isRegistered)
    }

    func testLogoutDeleteRetriesAfterSignOutAndRestart() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .failure(AppError.network),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let credentials = MemoryCredentialStore()
        let (preference, _) = makeEnabledPushPreference()
        let tokens = FakePushTokenProvider(token: "fcm-abc")
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: tokens,
            credentials: credentials
        )
        await push.registerIfNeeded()
        push.isSessionActive = { false }
        push.unregisterBestEffort(accessToken: "old-access")
        await waitUntil {
            http.requests.contains { $0.method == .delete && $0.path == "v1/users/fcm-token" }
        }
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 1)

        await push.retryIfNeeded()
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 2)
        let restarted = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: tokens,
            credentials: credentials
        )
        restarted.isSessionActive = { false }
        http.rawResults = [
            .failure(AppError.network),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        // pending should already be cleared after successful retry
        await restarted.retryIfNeeded()
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 2)
    }

    func testPersistedLogoutDeleteRetriesOnNewSession() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .failure(AppError.network),
        ]
        let credentials = MemoryCredentialStore()
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc"),
            credentials: credentials
        )
        await push.registerIfNeeded()
        push.isSessionActive = { false }
        push.unregisterBestEffort(accessToken: "old-access")
        await waitUntil {
            http.requests.filter { $0.method == .delete }.count == 1
        }

        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let restarted = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc"),
            credentials: credentials
        )
        restarted.isSessionActive = { false }
        await restarted.retryIfNeeded()
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 2)
        let header = http.requests.last { $0.method == .delete }?.extraHeaders["Authorization"]
        XCTAssertEqual(header, "Bearer old-access")
    }

    func testOfflineLogoutThenOtherAccountReregistersSameToken() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .failure(AppError.network),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let credentials = MemoryCredentialStore()
        let (preference, _) = makeEnabledPushPreference()
        var userId: String? = "user-a"
        var signedIn = true
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc"),
            credentials: credentials
        )
        push.currentUserId = { userId }
        push.isSessionActive = { signedIn }
        await push.registerIfNeeded()
        XCTAssertEqual(http.requests.filter { $0.method == .post && $0.path == "v1/users/fcm-token" }.count, 1)

        signedIn = false
        push.unregisterBestEffort(accessToken: "a-access", userId: userId)
        await waitUntil {
            http.requests.contains { $0.method == .delete && $0.path == "v1/users/fcm-token" }
        }
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 1)

        userId = "user-b"
        signedIn = true
        await push.registerIfNeeded()

        let tokenCalls = http.requests.filter { $0.path == "v1/users/fcm-token" }
        XCTAssertEqual(tokenCalls.map(\.method), [.post, .delete, .delete, .post])
        XCTAssertEqual(try jsonObject(from: tokenCalls[0])["token"] as? String, "fcm-abc")
        XCTAssertEqual(try jsonObject(from: tokenCalls[3])["token"] as? String, "fcm-abc")
        XCTAssertEqual(tokenCalls[1].extraHeaders["Authorization"], "Bearer a-access")
        XCTAssertEqual(tokenCalls[2].extraHeaders["Authorization"], "Bearer a-access")
        XCTAssertTrue(push.isRegistered)
    }

    func testInFlightRegisterDoesNotApplyToAnotherAccount() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let credentials = MemoryCredentialStore()
        let (preference, _) = makeEnabledPushPreference()
        var userId: String? = "user-a"
        var signedIn = true
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc"),
            credentials: credentials
        )
        push.currentUserId = { userId }
        push.isSessionActive = { signedIn }
        http.pauseSends = true
        let registerA = Task { await push.registerIfNeeded() }
        await waitUntil {
            http.requests.contains { $0.method == .post && $0.path == "v1/users/fcm-token" }
        }

        signedIn = false
        push.unregisterBestEffort(accessToken: "a-access", userId: "user-a")
        userId = "user-b"
        signedIn = true
        let registerB = Task { await push.registerIfNeeded() }
        http.releasePaused()
        await registerA.value
        await registerB.value

        let tokenCalls = http.requests.filter { $0.path == "v1/users/fcm-token" }
        XCTAssertGreaterThanOrEqual(tokenCalls.filter { $0.method == .post }.count, 2)
        XCTAssertTrue(
            tokenCalls.contains {
                $0.method == .delete && $0.extraHeaders["Authorization"] == "Bearer a-access"
            }
        )
        XCTAssertTrue(push.isRegistered)
    }

    func testExpiredCapturedDeleteTokenStopsUnauthorizedRetriesUntilOwnerReturns() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .failure(AppError.http(status: 401, message: nil, errorCode: nil)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let credentials = MemoryCredentialStore()
        let (preference, _) = makeEnabledPushPreference()
        var userId: String? = "user-a"
        var signedIn = true
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc"),
            credentials: credentials
        )
        push.currentUserId = { userId }
        push.isSessionActive = { signedIn }
        await push.registerIfNeeded()

        signedIn = false
        push.unregisterBestEffort(accessToken: "expired-access", userId: "user-a")
        await waitUntil {
            http.requests.filter { $0.method == .delete }.count == 1
        }
        XCTAssertEqual(
            http.requests.last { $0.method == .delete }?.extraHeaders["Authorization"],
            "Bearer expired-access"
        )

        await push.retryIfNeeded()
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 1)

        signedIn = true
        await push.registerIfNeeded()
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 1)
        XCTAssertEqual(
            http.requests.last { $0.method == .delete }?.extraHeaders["Authorization"],
            "Bearer expired-access"
        )
        XCTAssertTrue(push.isRegistered)
    }

    func testDeleteServerErrorRetriesAfterBackoff() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .failure(AppError.http(status: 503, message: nil, errorCode: nil)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc")
        )
        let gate = WaitGate()
        push.waitForRetry = { _ in await gate.wait() }
        push.currentUserId = { "user-a" }
        push.isSessionActive = { true }
        await push.registerIfNeeded()
        let unregister = Task { await push.unregister() }
        await waitUntil { gate.isWaiting }
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 1)
        gate.resume()
        await unregister.value
        await waitUntil {
            http.requests.filter { $0.method == .delete }.count == 2
        }
        XCTAssertFalse(push.isRegistered)
    }

    func testNetworkRegisterFailureRetriesAfterBackoff() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .failure(AppError.network),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc")
        )
        let gate = WaitGate()
        push.waitForRetry = { _ in await gate.wait() }
        let register = Task { await push.registerIfNeeded() }
        await waitUntil { gate.isWaiting }
        XCTAssertFalse(push.isRegistered)
        XCTAssertEqual(http.requests.filter { $0.method == .post }.count, 1)
        gate.resume()
        await register.value
        await waitUntil { push.isRegistered }
        XCTAssertEqual(http.requests.filter { $0.method == .post }.count, 2)
    }

    func testPersistedTokenIsUsedWhenUnregisterHasNoInMemoryToken() async {
        PushInbox.shared.token = nil
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let credentials = MemoryCredentialStore()
        try? credentials.set("fcm-saved", account: "push.lastFcmToken")
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: nil),
            credentials: credentials
        )
        push.isSessionActive = { false }
        push.unregisterBestEffort(accessToken: "expired-access", userId: "user-a")
        await waitUntil {
            http.requests.contains { $0.method == .delete && $0.path == "v1/users/fcm-token" }
        }
        XCTAssertEqual(try jsonObject(from: http.requests.last { $0.method == .delete }!)["token"] as? String, "fcm-saved")
        XCTAssertEqual(
            http.requests.last { $0.method == .delete }?.extraHeaders["Authorization"],
            "Bearer expired-access"
        )
    }

    func testTokenArrivingAfterLogoutFillsDeferredDelete() async throws {
        PushInbox.shared.token = nil
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let credentials = MemoryCredentialStore()
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: nil),
            credentials: credentials
        )
        push.isSessionActive = { false }
        push.unregisterBestEffort(accessToken: "a-access", userId: "user-a")
        XCTAssertTrue(http.requests.filter { $0.method == .delete }.isEmpty)

        await push.handleTokenRefresh("fcm-late", signedIn: false)
        let deletes = http.requests.filter { $0.method == .delete }
        XCTAssertEqual(deletes.count, 1)
        XCTAssertEqual(try jsonObject(from: deletes[0])["token"] as? String, "fcm-late")
        XCTAssertEqual(deletes[0].extraHeaders["Authorization"], "Bearer a-access")
    }

    func testUnattemptableDeleteDoesNotBlockLaterAccountUnregister() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .failure(AppError.http(status: 401, message: nil, errorCode: nil)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let credentials = MemoryCredentialStore()
        let (preference, _) = makeEnabledPushPreference()
        var userId: String? = "user-a"
        var signedIn = true
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc"),
            credentials: credentials
        )
        push.currentUserId = { userId }
        push.isSessionActive = { signedIn }
        await push.registerIfNeeded()

        signedIn = false
        push.unregisterBestEffort(accessToken: "expired-access", userId: "user-a")
        await waitUntil { http.requests.filter { $0.method == .delete }.count == 1 }

        userId = "user-b"
        signedIn = true
        await push.registerIfNeeded()
        await push.unregister()
        XCTAssertGreaterThanOrEqual(http.requests.filter { $0.method == .delete }.count, 2)
        XCTAssertNil(http.requests.last { $0.method == .delete }?.extraHeaders["Authorization"])
        XCTAssertFalse(push.isRegistered)
    }

    func testLegacyNilUserIdPendingDoesNotDeleteNewAccountRegistration() async throws {
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/users/fcm-token": Data(#"{"success":true,"message":"ok"}"#.utf8),
        ]
        let credentials = MemoryCredentialStore()
        let payload = #"[{"token":"fcm-abc"}]"#
        try credentials.set(payload, account: "push.pendingDeletes")
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc"),
            credentials: credentials
        )
        push.currentUserId = { "user-b" }
        push.isSessionActive = { true }
        await push.registerIfNeeded()
        XCTAssertTrue(push.isRegistered)
        XCTAssertEqual(http.requests.filter { $0.path == "v1/users/fcm-token" }.map(\.method), [.post])
    }

    func testUnownedForegroundNotificationIsAttributedToSignedInUser() {
        let store = NotificationStore(
            api: PushAPI(client: ScriptedHTTP()),
            disk: DiskStore(folder: "NotificationUnowned-\(UUID().uuidString)")
        )
        store.activate(userId: "user-b")
        store.ingest(
            AppNotification(id: "late", title: "T", body: "", sentAt: 1),
            showToast: true,
            volumeThreshold: 0,
            userId: "user-b"
        )
        XCTAssertEqual(store.items.map(\.id), ["late"])
        XCTAssertEqual(store.items.first?.userId, "user-b")
        XCTAssertEqual(store.toast?.id, "late")

        let router = AppRouter()
        router.handleNotification(
            AppNotification(
                id: "late",
                title: "T",
                body: "",
                sentAt: 1,
                data: ["type": NotificationKind.intradayBreakout.rawValue, "symbols": "AMD"]
            ),
            versionPassed: true,
            signedIn: true,
            currentUserId: "user-b"
        )
        XCTAssertEqual(router.overlay, .symbol("AMD"))
    }

    func testUnstampedCacheIsRestoredForCurrentUser() {
        let disk = DiskStore(folder: "NotificationUnstampedCache-\(UUID().uuidString)")
        disk.write(
            [AppNotification(id: "old", title: "T", body: "", sentAt: 1)],
            name: NotificationStore.cacheName(for: "user-1")
        )
        let store = NotificationStore(api: PushAPI(client: ScriptedHTTP()), disk: disk)
        store.activate(userId: "user-1")
        XCTAssertEqual(store.items.map(\.id), ["old"])
        XCTAssertEqual(store.items.first?.userId, "user-1")
    }

    func testRefreshKeepsIngestedRealtimeItem() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"id":"server","title":"T","body":"","sentAt":2000}]"#.utf8)),
        ]
        let disk = DiskStore(folder: "NotificationRefreshIngest-\(UUID().uuidString)")
        let store = NotificationStore(api: PushAPI(client: http), disk: disk)
        store.activate(userId: "user-1")
        http.pauseSends = true
        let refresh = Task { await store.refresh(userId: "user-1") }
        await waitUntil { store.isLoading }
        store.ingest(
            AppNotification(id: "live", userId: "user-1", title: "Live", body: "", sentAt: 3000),
            showToast: true,
            volumeThreshold: 0,
            userId: "user-1"
        )
        XCTAssertEqual(store.items.map(\.id), ["live"])
        http.releasePaused()
        await refresh.value
        XCTAssertEqual(Set(store.items.map(\.id)), ["live", "server"])
        XCTAssertEqual(store.toast?.id, "live")
        XCTAssertEqual(
            Set(disk.read([AppNotification].self, name: NotificationStore.cacheName(for: "user-1"))?.map(\.id) ?? []),
            ["live", "server"]
        )
    }

    func testTypeChangeFailedRefreshDoesNotPageWithOldCursor() async {
        let http = ScriptedHTTP()
        let page = (0..<20).map {
            #"{"id":"n\#($0)","title":"T","body":"","sentAt":\#(200 - $0)}"#
        }.joined(separator: ",")
        http.rawResults = [
            .success(Data("[\(page)]".utf8)),
            .failure(AppError.network),
            .success(Data(#"[{"id":"typed","title":"T","body":"","sentAt":1,"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)"}}]"#.utf8)),
        ]
        let store = NotificationStore(
            api: PushAPI(client: http),
            disk: DiskStore(folder: "NotificationTypeCursor-\(UUID().uuidString)")
        )
        store.activate(userId: "user-1")
        await store.refresh(userId: "user-1")
        XCTAssertTrue(store.hasMore)
        store.selectedType = .intradayBreakout
        await store.refresh(userId: "user-1")
        XCTAssertNotNil(store.errorText)
        XCTAssertFalse(store.hasMore)
        let before = http.requests.filter { $0.path == "v1/notifications/history" }.count
        await store.loadMore(userId: "user-1")
        XCTAssertEqual(http.requests.filter { $0.path == "v1/notifications/history" }.count, before)
    }

    func testFailedRegisterDoesNotBlockPendingDelete() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .failure(AppError.network),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
            .failure(AppError.http(status: 503, message: nil, errorCode: nil)),
        ]
        let credentials = MemoryCredentialStore()
        let (preference, _) = makeEnabledPushPreference()
        var userId: String? = "user-a"
        var signedIn = true
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc"),
            credentials: credentials
        )
        let gate = WaitGate()
        push.waitForRetry = { _ in await gate.wait() }
        push.currentUserId = { userId }
        push.isSessionActive = { signedIn }
        await push.registerIfNeeded()

        signedIn = false
        push.unregisterBestEffort(accessToken: "a-access", userId: "user-a")
        await waitUntil { http.requests.filter { $0.method == .delete }.count == 1 }

        userId = "user-b"
        signedIn = true
        await push.registerIfNeeded()
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 2)
        XCTAssertEqual(
            http.requests.last { $0.method == .delete }?.extraHeaders["Authorization"],
            "Bearer a-access"
        )
        XCTAssertEqual(http.requests.filter { $0.method == .post }.count, 2)
        XCTAssertFalse(push.isRegistered)
        if gate.isWaiting {
            gate.resume()
        }
    }

    func testTokenRefreshDuringInFlightRegisterDeletesOldToken() async {
        PushInbox.shared.token = nil
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/users/fcm-token": Data(#"{"success":true,"message":"ok"}"#.utf8),
        ]
        let (preference, _) = makeEnabledPushPreference()
        let tokens = FakePushTokenProvider(token: "fcm-a")
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: tokens
        )
        http.pauseSends = true
        let register = Task { await push.registerIfNeeded() }
        await waitUntil {
            http.requests.contains { $0.method == .post && $0.path == "v1/users/fcm-token" }
        }
        tokens.token = "fcm-b"
        let refresh = Task { await push.handleTokenRefresh("fcm-b", signedIn: true) }
        await waitUntil { PushInbox.shared.token == "fcm-b" }
        http.releasePaused()
        await register.value
        await refresh.value
        await waitUntil {
            http.requests.filter { $0.path == "v1/users/fcm-token" }.count >= 3
        }
        let tokenCalls = http.requests.filter { $0.path == "v1/users/fcm-token" }
        XCTAssertEqual(tokenCalls.map(\.method), [.post, .delete, .post])
        XCTAssertEqual(try jsonObject(from: tokenCalls[0])["token"] as? String, "fcm-a")
        XCTAssertEqual(try jsonObject(from: tokenCalls[1])["token"] as? String, "fcm-a")
        XCTAssertEqual(try jsonObject(from: tokenCalls[2])["token"] as? String, "fcm-b")
        XCTAssertTrue(push.isRegistered)
    }

    func testFailedDeleteDoesNotBlockLaterPendingDelete() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .failure(AppError.http(status: 503, message: nil, errorCode: nil)),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let credentials = MemoryCredentialStore()
        try? credentials.set(
            #"[{"token":"fcm-a","accessToken":"access-a","userId":"user-a"},{"token":"fcm-c","accessToken":"access-c","userId":"user-c"}]"#,
            account: "push.pendingDeletes"
        )
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: nil),
            credentials: credentials
        )
        let gate = WaitGate()
        push.waitForRetry = { _ in await gate.wait() }
        push.isSessionActive = { false }
        await push.retryPendingDeletes()
        let deletes = http.requests.filter { $0.method == .delete }
        XCTAssertEqual(deletes.count, 2)
        XCTAssertEqual(try jsonObject(from: deletes[0])["token"] as? String, "fcm-a")
        XCTAssertEqual(try jsonObject(from: deletes[1])["token"] as? String, "fcm-c")
        if gate.isWaiting {
            gate.resume()
        }
    }

    func testPendingDeletePersistFailureIsRetried() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/users/fcm-token": Data(#"{"success":true,"message":"ok"}"#.utf8),
        ]
        let credentials = FailingSetCredentialStore()
        try? credentials.set("fcm-saved", account: "push.lastFcmToken")
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: nil),
            credentials: credentials
        )
        push.retryDelayNanoseconds = { _ in 0 }
        let gate = WaitGate()
        push.waitForRetry = { _ in await gate.wait() }
        push.isSessionActive = { false }
        credentials.failSet = true
        http.pauseSends = true
        push.unregisterBestEffort(accessToken: "a-access", userId: "user-a")
        await waitUntil {
            http.requests.contains { $0.method == .delete && $0.path == "v1/users/fcm-token" }
        }
        XCTAssertNil(credentials.string(account: "push.pendingDeletes"))
        credentials.failSet = false
        gate.resume()
        await waitUntil { credentials.string(account: "push.pendingDeletes") != nil }
        http.releasePaused()
        await waitUntil { http.requests.filter { $0.method == .delete }.count == 1 }
        await waitUntil { credentials.string(account: "push.pendingDeletes") == nil }
    }

    func testLoadMoreCursorIgnoresIngestedRealtimeItem() async {
        let http = ScriptedHTTP()
        let page = (0..<20).map {
            #"{"id":"n\#($0)","title":"T","body":"","sentAt":\#(200 - $0)}"#
        }.joined(separator: ",")
        http.rawResults = [
            .success(Data("[\(page)]".utf8)),
            .success(Data(#"[{"id":"older","title":"T","body":"","sentAt":150}]"#.utf8)),
        ]
        let store = NotificationStore(
            api: PushAPI(client: http),
            disk: DiskStore(folder: "NotificationHistoryCursor-\(UUID().uuidString)")
        )
        store.activate(userId: "user-1")
        await store.refresh(userId: "user-1")
        store.ingest(
            AppNotification(id: "delayed", userId: "user-1", title: "T", body: "", sentAt: 1),
            showToast: false,
            volumeThreshold: 0,
            userId: "user-1"
        )
        XCTAssertEqual(store.items.last?.id, "delayed")
        await store.loadMore(userId: "user-1")
        let history = http.requests.filter { $0.path == "v1/notifications/history" }
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.last?.query["lastTime"], "181000")
        XCTAssertTrue(store.items.map(\.id).contains("older"))
        XCTAssertTrue(store.items.map(\.id).contains("delayed"))
    }

    func testTypeFilterDoesNotOverwriteUnfilteredCache() async {
        let http = ScriptedHTTP()
        let unfiltered = #"[{"id":"a","title":"T","body":"","sentAt":2},{"id":"b","title":"T","body":"","sentAt":1}]"#
        let typed = #"[{"id":"typed","title":"T","body":"","sentAt":3,"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)"}}]"#
        http.rawResults = [
            .success(Data(unfiltered.utf8)),
            .success(Data(typed.utf8)),
        ]
        let disk = DiskStore(folder: "NotificationTypeCache-\(UUID().uuidString)")
        let store = NotificationStore(api: PushAPI(client: http), disk: disk)
        store.activate(userId: "user-1")
        await store.refresh(userId: "user-1")
        XCTAssertEqual(store.items.map(\.id), ["a", "b"])
        store.selectedType = .intradayBreakout
        await store.refresh(userId: "user-1")
        XCTAssertEqual(store.items.map(\.id), ["typed"])
        XCTAssertEqual(
            disk.read([AppNotification].self, name: NotificationStore.cacheName(for: "user-1"))?.map(\.id),
            ["a", "b"]
        )

        let relaunched = NotificationStore(api: PushAPI(client: ScriptedHTTP()), disk: disk)
        relaunched.activate(userId: "user-1")
        XCTAssertNil(relaunched.selectedType)
        XCTAssertEqual(relaunched.items.map(\.id), ["a", "b"])
    }

    func testSymbolFilterKeepsLoadingUntilPageIsFilled() async {
        let http = ScriptedHTTP()
        let page1Matches = (0..<19).map {
            #"{"id":"a\#($0)","title":"T","body":"","sentAt":\#(200 - $0),"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)","symbols":"AMD"}}"#
        } + [#"{"id":"nvda-1","title":"T","body":"","sentAt":181,"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)","symbols":"NVDA"}}"#]
        let page2 = (0..<20).map {
            #"{"id":"b\#($0)","title":"T","body":"","sentAt":\#(180 - $0),"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)","symbols":"AMD"}}"#
        }
        let page3 = #"{"id":"nvda-2","title":"T","body":"","sentAt":1,"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)","symbols":"NVDA"}}"#
        http.rawResults = [
            .success(Data("[\(page1Matches.joined(separator: ","))]".utf8)),
            .success(Data("[\(page2.joined(separator: ","))]".utf8)),
            .success(Data("[\(page3)]".utf8)),
        ]
        let store = NotificationStore(
            api: PushAPI(client: http),
            disk: DiskStore(folder: "NotificationSymbolFill-\(UUID().uuidString)")
        )
        store.activate(userId: "user-1")
        store.symbolFilter = "NVDA"
        await store.refresh(userId: "user-1")
        XCTAssertEqual(store.visibleItems(volumeThreshold: 0).map(\.id), ["nvda-1", "nvda-2"])
        XCTAssertEqual(http.requests.filter { $0.path == "v1/notifications/history" }.count, 3)
    }

    func testFilteredPaginationContinuesPastNonMatchingPage() async {
        let http = ScriptedHTTP()
        let breakouts = (0..<20).map {
            #"{"id":"b\#($0)","title":"T","body":"","sentAt":\#(200 - $0),"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)","symbols":"AMD,NVDA"}}"#
        }.joined(separator: ",")
        let page2 = (20..<40).map {
            #"{"id":"b\#($0)","title":"T","body":"","sentAt":\#(80 - ($0 - 20)),"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)","symbols":"AMD,NVDA"}}"#
        }.joined(separator: ",")
        let match = #"{"id":"trend","title":"T","body":"","sentAt":1,"data":{"type":"\#(NotificationKind.marketTrendUpReversal.rawValue)","symbols":"AMD,NVDA"}}"#
        http.rawResults = [
            .success(Data("[\(breakouts)]".utf8)),
            .success(Data("[\(page2)]".utf8)),
            .success(Data("[\(match)]".utf8)),
        ]
        let store = NotificationStore(
            api: PushAPI(client: http),
            disk: DiskStore(folder: "NotificationFilterPages-\(UUID().uuidString)")
        )
        store.activate(userId: "user-1")
        store.selectedType = .marketTrendUpReversal
        await store.refresh(userId: "user-1")
        XCTAssertEqual(store.visibleItems(volumeThreshold: 0).map(\.id), ["trend"])
        let history = http.requests.filter { $0.path == "v1/notifications/history" }
        XCTAssertTrue(history.count >= 3)
        XCTAssertTrue(history.allSatisfy { $0.query["type"] == NotificationKind.marketTrendUpReversal.rawValue })
    }

    func testTypeFilterIsSentOnHistoryRefreshAndTypeChangeRefetches() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data("[]".utf8)),
            .success(Data("[]".utf8)),
            .success(Data("[]".utf8)),
        ]
        let store = NotificationStore(
            api: PushAPI(client: http),
            disk: DiskStore(folder: "NotificationTypeQuery-\(UUID().uuidString)")
        )
        store.activate(userId: "user-1")
        await store.refresh(userId: "user-1")
        XCTAssertNil(http.requests.last?.query["type"])

        store.selectedType = .intradayBreakout
        await store.refreshOnFocus(userId: "user-1")
        XCTAssertEqual(http.requests.last?.query["type"], NotificationKind.intradayBreakout.rawValue)
        XCTAssertEqual(http.requests.filter { $0.path == "v1/notifications/history" }.count, 2)

        await store.refreshOnFocus(userId: "user-1")
        XCTAssertEqual(http.requests.filter { $0.path == "v1/notifications/history" }.count, 2)
    }

    func testSymbolFilterContinuesPastNonMatchingPage() async {
        let http = ScriptedHTTP()
        let amdPage = (0..<20).map {
            #"{"id":"a\#($0)","title":"T","body":"","sentAt":\#(200 - $0),"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)","symbols":"AMD"}}"#
        }.joined(separator: ",")
        let match = #"{"id":"nvda","title":"T","body":"","sentAt":1,"data":{"type":"\#(NotificationKind.intradayBreakout.rawValue)","symbols":"NVDA"}}"#
        http.rawResults = [
            .success(Data("[\(amdPage)]".utf8)),
            .success(Data("[\(match)]".utf8)),
        ]
        let store = NotificationStore(
            api: PushAPI(client: http),
            disk: DiskStore(folder: "NotificationSymbolPages-\(UUID().uuidString)")
        )
        store.activate(userId: "user-1")
        store.symbolFilter = "NVDA"
        await store.refresh(userId: "user-1")
        XCTAssertEqual(store.visibleItems(volumeThreshold: 0).map(\.id), ["nvda"])
        XCTAssertEqual(http.requests.filter { $0.path == "v1/notifications/history" }.count, 2)
        XCTAssertNil(http.requests.first?.query["type"])
    }

    func testTypeFilterEmptyResultKeepsFilteredEmptyState() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data("[]".utf8)),
        ]
        let store = NotificationStore(
            api: PushAPI(client: http),
            disk: DiskStore(folder: "NotificationTypeEmpty-\(UUID().uuidString)")
        )
        store.activate(userId: "user-1")
        store.selectedType = .intradayBreakout
        await store.refresh(userId: "user-1")
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.visibleItems(volumeThreshold: 0).isEmpty)
        XCTAssertTrue(store.hasActiveFilters(volumeThreshold: 0))
        XCTAssertEqual(http.requests.last?.query["type"], NotificationKind.intradayBreakout.rawValue)
    }

    func testHistoryNotificationsDestinationDoesNotOpenOverlay() {
        let router = AppRouter()
        let notification = makeNotification(
            type: .intradayBreakout,
            data: [
                "type": NotificationKind.intradayBreakout.rawValue,
                "symbols": "AMD,NVDA",
                "screen": "Markets",
            ]
        )
        router.handleNotification(
            notification,
            versionPassed: true,
            signedIn: true,
            alreadyShowingHistory: true
        )
        XCTAssertNil(router.overlay)

        router.handleNotification(notification, versionPassed: true, signedIn: true)
        XCTAssertEqual(router.overlay, .notifications)

        router.dismissOverlay()
        router.setViewingNotifications(true)
        router.handleNotification(
            notification,
            versionPassed: true,
            signedIn: true
        )
        XCTAssertNil(router.overlay)
    }

    func testSignedInWithoutUserIdDefersOwnedNotification() {
        let router = AppRouter()
        let notification = AppNotification(
            id: "owned",
            userId: "user-a",
            title: "T",
            body: "",
            sentAt: 1,
            data: ["type": NotificationKind.intradayBreakout.rawValue, "symbols": "AMD", "userId": "user-a"]
        )
        router.handleNotification(
            notification,
            versionPassed: true,
            signedIn: true,
            currentUserId: nil
        )
        XCTAssertNil(router.overlay)
        XCTAssertEqual(router.pendingNotification, .symbol("AMD"))
        XCTAssertEqual(router.pendingNotificationUserId, "user-a")

        router.consumePending(versionPassed: true, signedIn: true, currentUserId: nil)
        XCTAssertNil(router.overlay)

        router.consumePending(versionPassed: true, signedIn: true, currentUserId: "user-a")
        XCTAssertEqual(router.overlay, .symbol("AMD"))
    }

    func testMissingTitleUsesLocalizedFallback() {
        let item = NotificationHistory.normalize(["id": "n", "body": "", "sentAt": 1], index: 0)
        XCTAssertEqual(item?.title, "")
        XCTAssertEqual(NotificationParser.displayTitle(for: item!), L10n.Notifications.toastTitle)
    }

    func testRetryBeforeRegistrationAllowedDoesNotPromptOrRegister() async {
        let http = ScriptedHTTP()
        http.rawResultsByPath = [
            "v1/users/fcm-token": Data(#"{"success":true,"message":"ok"}"#.utf8),
        ]
        let credentials = MemoryCredentialStore()
        try? credentials.set(
            #"[{"token":"fcm-old","accessToken":"access-a","userId":"user-a"}]"#,
            account: "push.pendingDeletes"
        )
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "push_notifications_enabled")
        let auth = FakeNotificationAuthorization(status: .notDetermined, requestGranted: true)
        let preference = PushPreferenceStore(defaults: defaults, authorization: auth)
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc"),
            credentials: credentials
        )
        push.allowsRegistration = false
        push.isSessionActive = { true }
        push.currentUserId = { "user-a" }

        await push.retryPendingDeletes()
        await push.retryIfNeeded()
        await push.registerIfNeeded()
        XCTAssertEqual(http.requests.filter { $0.method == .delete }.count, 1)
        XCTAssertTrue(http.requests.filter { $0.method == .post }.isEmpty)
        XCTAssertEqual(auth.requestCount, 0)
        XCTAssertFalse(push.isRegistered)

        push.allowsRegistration = true
        await push.registerIfNeeded()
        XCTAssertEqual(auth.requestCount, 1)
        XCTAssertEqual(http.requests.filter { $0.method == .post }.count, 1)
        XCTAssertTrue(push.isRegistered)
    }

    func testFailedRegisterIsRetriedOnNetworkRecovery() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .failure(AppError.network),
            .success(Data(#"{"success":true,"message":"ok"}"#.utf8)),
        ]
        let (preference, _) = makeEnabledPushPreference()
        let push = PushRegistration(
            api: PushAPI(client: http),
            publicClient: http,
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc")
        )
        await push.registerIfNeeded()
        XCTAssertFalse(push.isRegistered)
        await push.retryIfNeeded()
        XCTAssertTrue(push.isRegistered)
        XCTAssertEqual(http.requests.filter { $0.method == .post && $0.path == "v1/users/fcm-token" }.count, 2)
    }

    func testUnavailableFirebaseDoesNotPrompt() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "push_notifications_enabled")
        let auth = FakeNotificationAuthorization(status: .notDetermined, requestGranted: true)
        auth.isRemoteRegistrationAvailable = false
        let preference = PushPreferenceStore(defaults: defaults, authorization: auth)
        let allowed = await preference.prepareForPush()
        XCTAssertFalse(allowed)
        XCTAssertEqual(auth.requestCount, 0)
        XCTAssertTrue(preference.isEnabled)

        await preference.setEnabled(true)
        XCTAssertEqual(auth.requestCount, 0)
        XCTAssertEqual(auth.registerCount, 0)
        XCTAssertTrue(preference.isEnabled)
    }

    func testRegisterDoesNotPromptAfterSessionEnds() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "push_notifications_enabled")
        let auth = FakeNotificationAuthorization(status: .notDetermined, requestGranted: true)
        auth.pauseRequests = true
        let preference = PushPreferenceStore(defaults: defaults, authorization: auth)
        var signedIn = true
        let push = PushRegistration(
            api: PushAPI(client: ScriptedHTTP()),
            publicClient: ScriptedHTTP(),
            preference: preference,
            tokens: FakePushTokenProvider(token: "fcm-abc")
        )
        push.isSessionActive = { signedIn }
        let task = Task { await push.registerIfNeeded() }
        await waitUntil { auth.requestCount == 1 }
        signedIn = false
        auth.releaseRequests()
        await task.value
        XCTAssertEqual(auth.registerCount, 0)
        XCTAssertFalse(push.isRegistered)
    }

    func testFirebasePlistOnlyMatchesProductionBundle() {
        XCTAssertTrue(
            FirebaseAppIdentity.matches(
                appBundleID: "com.byteknows.moneyknows",
                plistBundleID: "com.byteknows.moneyknows"
            )
        )
        XCTAssertFalse(
            FirebaseAppIdentity.matches(
                appBundleID: "com.byteknows.moneyknows.dev",
                plistBundleID: "com.byteknows.moneyknows"
            )
        )
        XCTAssertFalse(
            FirebaseAppIdentity.matches(
                appBundleID: "com.byteknows.moneyknows.staging",
                plistBundleID: "com.byteknows.moneyknows"
            )
        )
        XCTAssertTrue(
            FirebaseAppIdentity.shouldConfigure(
                appBundleID: "com.byteknows.moneyknows",
                plistBundleID: "com.byteknows.moneyknows",
                runningTests: false
            )
        )
        XCTAssertFalse(
            FirebaseAppIdentity.shouldConfigure(
                appBundleID: "com.byteknows.moneyknows.dev",
                plistBundleID: "com.byteknows.moneyknows",
                runningTests: false
            )
        )
        XCTAssertFalse(
            FirebaseAppIdentity.shouldConfigure(
                appBundleID: "com.byteknows.moneyknows",
                plistBundleID: "com.byteknows.moneyknows",
                runningTests: true
            )
        )
    }
}

@MainActor
final class VersionGateModelTests: XCTestCase {
    func testStalePassedResultDoesNotOverrideNewerForceUpgrade() async {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"{"forceUpgrade":false}"#.utf8)),
            .success(Data(#"{"forceUpgrade":true,"upgradeMessage":"Update","storeUrl":"https://example.com/app"}"#.utf8)),
        ]
        let gate = VersionGateModel(api: VersionAPI(client: http))
        http.pauseSends = true
        let first = Task { await gate.check() }
        await waitUntil { http.requests.count == 1 }
        let second = Task { await gate.check() }
        await waitUntil { http.requests.count == 2 }
        http.releaseLast()
        await second.value
        XCTAssertEqual(
            gate.state,
            .blocked(message: "Update", storeURL: URL(string: "https://example.com/app")!)
        )
        http.releasePaused()
        await first.value
        XCTAssertEqual(
            gate.state,
            .blocked(message: "Update", storeURL: URL(string: "https://example.com/app")!)
        )
    }
}

@MainActor
private func makeEnabledPushPreference() -> (PushPreferenceStore, FakeNotificationAuthorization) {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    defaults.set(true, forKey: "push_notifications_enabled")
    let auth = FakeNotificationAuthorization(status: .authorized, requestGranted: true)
    return (PushPreferenceStore(defaults: defaults, authorization: auth), auth)
}

private func makeNotification(
    id: String = "id",
    type: NotificationKind? = nil,
    sentAt: Int64 = 1,
    data: [String: String]? = nil
) -> AppNotification {
    AppNotification(
        id: id,
        notificationType: type?.rawValue,
        title: id,
        body: "",
        sentAt: sentAt,
        data: data
    )
}

private final class FailingSetCredentialStore: CredentialStoring {
    var failSet = false
    private var values: [String: String] = [:]

    func set(_ value: String, account: String) throws {
        if failSet {
            throw AppError.decoding
        }
        values[account] = value
    }

    func string(account: String) -> String? {
        values[account]
    }

    func delete(account: String) {
        values.removeValue(forKey: account)
    }

    func accounts() -> [String] {
        Array(values.keys)
    }
}
