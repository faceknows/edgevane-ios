import XCTest
@testable import Moneyknows

final class BarsAPIDecodingTests: XCTestCase {
    func testDecodesBareArrayNumericAndISOTimestamps() throws {
        let json = Data(#"""
        [
          {"d":1693827000,"o":"1","h":2,"l":0.5,"c":1.5,"v":10},
          {"t":"2026-09-04T13:31:00Z","o":1.5,"h":2.5,"l":1.4,"c":2,"v":4}
        ]
        """#.utf8)
        let bars = MinuteBars.fromDTOs(try BarsAPI.decodeBars(from: json), date: "2023-09-04")
        XCTAssertEqual(bars.count, 2)
        XCTAssertEqual(bars[0].open, 1)
        XCTAssertEqual(bars[0].volume, 10)
        XCTAssertEqual(bars[1].close, 2)
    }

    func testDecodesEnvelopeAndBarsObject() throws {
        let envelope = Data(#"{"data":[{"d":"1693827000","o":1,"h":1,"l":1,"c":1,"v":1}]}"#.utf8)
        XCTAssertEqual(try BarsAPI.decodeBars(from: envelope).count, 1)

        let wrapped = Data(#"{"symbol":"AAPL","bars":[{"d":"1693827000","o":1,"h":1,"l":1,"c":1,"v":1}]}"#.utf8)
        XCTAssertEqual(try BarsAPI.decodeBars(from: wrapped).count, 1)

        let nested = Data(#"{"data":{"bars":[{"d":"1693827000","o":1,"h":1,"l":1,"c":1,"v":1}]}}"#.utf8)
        XCTAssertEqual(try BarsAPI.decodeBars(from: nested).count, 1)
        XCTAssertTrue(try BarsAPI.decodeBars(from: Data(#"{"bars":null}"#.utf8)).isEmpty)
        XCTAssertTrue(try BarsAPI.decodeBars(from: Data(#"{"symbol":"AAPL","bars":null}"#.utf8)).isEmpty)
    }

    func testDropsIncompleteAndNonFiniteBars() throws {
        let json = Data(#"""
        [
          {"d":"1693827000","o":1,"h":1,"l":1,"c":1,"v":1},
          {"d":"1693827060","o":"NaN","h":1,"l":1,"c":1,"v":1},
          {"o":1,"h":1,"l":1,"c":1,"v":1}
        ]
        """#.utf8)
        XCTAssertEqual(MinuteBars.fromDTOs(try BarsAPI.decodeBars(from: json), date: "2023-09-04").count, 1)
    }

    func testParsesEasternClockDWithRequestDate() throws {
        let json = Data(#"[{"d":"09:30","o":1,"h":2,"l":0.5,"c":1.5,"v":10}]"#.utf8)
        let bars = MinuteBars.fromDTOs(try BarsAPI.decodeBars(from: json), date: "2026-09-04")
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(MarketClock.usDateString(from: bars[0].time), "2026-09-04")
        XCTAssertEqual(MarketClock.usTimeString(from: bars[0].time), "09:30")
        XCTAssertEqual(bars[0].open, 1)
        XCTAssertEqual(bars[0].volume, 10)
    }

    func testHugeNumericTimestampIsDropped() throws {
        let json = Data(#"""
        [
          {"d":1e20,"o":1,"h":1,"l":1,"c":1,"v":1},
          {"d":"09:30","o":2,"h":2,"l":2,"c":2,"v":2}
        ]
        """#.utf8)
        XCTAssertNoThrow(try BarsAPI.decodeBars(from: json))
        let bars = MinuteBars.fromDTOs(try BarsAPI.decodeBars(from: json), date: "2026-09-04")
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(bars[0].close, 2)
        XCTAssertEqual(MarketClock.usTimeString(from: bars[0].time), "09:30")
    }
}

@MainActor
final class BarStoreTests: XCTestCase {
    func testLoadsAndCachesRegularSession() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[{"d":"09:31","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let first = try await store.load(symbol: " aapl ", date: "2026-09-04", session: .regular)
        XCTAssertEqual(first.first?.close, 1)
        XCTAssertEqual(MarketClock.usTimeString(from: first[0].time), "09:30")
        XCTAssertEqual(http.requests.first?.path, "alpaca/market/intraday-bars")
        XCTAssertEqual(http.requests.first?.query["symbol"], "AAPL")
        XCTAssertEqual(http.requests.first?.query["timeFrame"], "1Min")
        XCTAssertEqual(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular)?.first?.close, 1)
        let second = try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular)
        XCTAssertEqual(second.first?.close, 2)
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular)?.first?.close, 2)
    }

    func testEmptyCacheDoesNotSkipRefresh() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[]"#.utf8)),
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let empty = try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular)
        XCTAssertTrue(empty.isEmpty)
        let filled = try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular)
        XCTAssertEqual(filled.count, 1)
        XCTAssertEqual(http.requests.count, 2)
    }

    func testEmptyRefreshDoesNotReplaceNonEmptyCache() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        _ = try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular)
        let kept = try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular)
        XCTAssertEqual(kept.first?.close, 1)
        XCTAssertEqual(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular)?.first?.close, 1)
        XCTAssertEqual(http.requests.count, 2)
    }

    func testParallelSessionsDoNotCancelEachOther() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"d":"1693827000","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[{"d":"1693823400","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let regular = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        await waitUntil { http.requests.count == 1 }
        let pre = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .premarket) }
        await waitUntil { http.requests.count == 2 }
        http.releasePaused()
        let regularBars = try await regular.value
        let preBars = try await pre.value
        XCTAssertEqual(regularBars.first?.close, 1)
        XCTAssertEqual(preBars.first?.close, 2)
        XCTAssertEqual(http.requests.map(\.path).sorted(), [
            "alpaca/market/intraday-bars",
            "alpaca/market/intraday/pre/bars",
        ])
    }

    func testResetDiscardsInFlightResult() async {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"d":"1693827000","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[{"d":"1693827060","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let stale = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        await waitUntil { http.requests.count == 1 }
        store.reset()
        let next = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        await waitUntil { http.requests.count == 2 }
        http.releaseNext()
        do {
            _ = try await stale.value
            XCTFail("stale bars must not apply after reset")
        } catch {
            XCTAssertEqual(error as? AppError, .cancelled)
        }
        http.releaseNext()
        let bars = try? await next.value
        XCTAssertEqual(bars?.first?.close, 2)
        XCTAssertEqual(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular)?.first?.close, 2)
    }

    func testCoalescesInFlightForSameKey() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"d":"1693827000","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let first = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        let second = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        await waitUntil { http.requests.count == 1 }
        http.releasePaused()
        let left = try await first.value
        let right = try await second.value
        XCTAssertEqual(left, right)
        XCTAssertEqual(http.requests.count, 1)
    }

    func testCancelledWaiterKeepsInflightUntilTaskFinishes() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let first = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        await waitUntil { http.requests.count == 1 }
        first.cancel()
        let second = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(http.requests.count, 1)
        http.releasePaused()
        let bars = try await second.value
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(http.requests.count, 1)
        _ = try? await first.value
    }

    func testEphemeralLoadDoesNotWriteTodayCache() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":3,"h":3,"l":3,"c":3,"v":3}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let bars = try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular, caches: false)
        XCTAssertEqual(bars.first?.close, 3)
        XCTAssertNil(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular))
        XCTAssertEqual(http.requests.first?.path, "alpaca/market/intraday-bars")
    }

    func testIndexBarsUseIbkrCompPath() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let bars = try await store.load(symbol: "NASDAQ", date: "2026-09-04", session: .index)
        XCTAssertEqual(bars.first?.close, 1)
        XCTAssertEqual(http.requests.first?.path, "ibkr/market/intraday-bars")
        XCTAssertEqual(http.requests.first?.query["symbol"], "COMP")
        XCTAssertEqual(store.cached(symbol: "COMP", date: "2026-09-04", session: .index)?.first?.close, 1)
        XCTAssertNil(store.cached(symbol: "COMP", date: "2026-09-04", session: .regular))
    }
}
