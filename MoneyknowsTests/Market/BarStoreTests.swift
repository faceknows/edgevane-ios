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

    func testDecodesDailyBarsEnvelopeWithDateOnlyBars() throws {
        let payload = Data(#"""
        {"symbol":"AAPL","timeFrame":"1Day","startDate":"2026-05-27","bars":[
          {"d":"2026-09-04","o":1,"h":2,"l":0.5,"c":1.5,"v":10,"direction":"up"}
        ]}
        """#.utf8)
        let dtos = try BarsAPI.decodeBars(from: payload)
        XCTAssertEqual(dtos.count, 1)
        let bars = DailyBars.fromDTOs(dtos)
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(MarketClock.usDateString(from: bars[0].time), "2026-09-04")
        XCTAssertEqual(bars[0].close, 1.5)

        let nested = Data(#"""
        {"data":{"timeFrame":"1Day","startDate":"2026-05-27","bars":[{"d":"2026-09-03","o":1,"h":1,"l":1,"c":1,"v":1}]}}
        """#.utf8)
        XCTAssertEqual(try BarsAPI.decodeBars(from: nested).count, 1)
        XCTAssertTrue(try BarsAPI.decodeBars(from: Data(#"{"timeFrame":"1Day","startDate":"2026-05-27","bars":null}"#.utf8)).isEmpty)
    }

    func testDecodesDailyBarsSkippingNullSlotsAndSymbolKeyedMaps() throws {
        let withNulls = Data(#"""
        {"symbol":"IREN","timeFrame":"1Day","startDate":"2026-05-31","bars":[
          null,
          {"d":"2026-09-04","o":1,"h":2,"l":0.5,"c":1.5,"v":10,"direction":"up"},
          null
        ]}
        """#.utf8)
        let skipped = DailyBars.fromDTOs(try BarsAPI.decodeBars(from: withNulls))
        XCTAssertEqual(skipped.count, 1)
        XCTAssertEqual(skipped[0].close, 1.5)

        let keyed = Data(#"""
        {"data":{"symbol":"IREN","bars":{"IREN":[{"d":"2026-09-03","o":1,"h":1,"l":1,"c":1,"v":1}]}}}
        """#.utf8)
        XCTAssertEqual(try BarsAPI.decodeBars(from: keyed).count, 1)
    }

    func testDropsBooleanOHLCVAndKeepsNumericOne() throws {
        let json = Data(#"""
        [
          {"d":"1693827000","o":true,"h":1,"l":1,"c":1,"v":1},
          {"d":"1693827060","o":1,"h":false,"l":1,"c":1,"v":1},
          {"d":"1693827120","o":1,"h":1,"l":1,"c":1,"v":1}
        ]
        """#.utf8)
        let dtos = try BarsAPI.decodeBars(from: json)
        XCTAssertNil(dtos[0].o)
        XCTAssertEqual(dtos[0].h, 1)
        XCTAssertNil(dtos[1].h)
        XCTAssertEqual(dtos[2].o, 1)
        XCTAssertEqual(dtos[2].v, 1)
        XCTAssertEqual(MinuteBars.fromDTOs(dtos, date: "2023-09-04").count, 1)
        XCTAssertEqual(MinuteBars.fromDTOs(dtos, date: "2023-09-04").first?.close, 1)

        let zeros = try BarsAPI.decodeBars(from: Data(#"""
        [
          {"d":"1693827180","o":1,"h":1,"l":1,"c":1,"v":false},
          {"d":"1693827240","o":0,"h":0,"l":0,"c":0,"v":0}
        ]
        """#.utf8))
        XCTAssertNil(zeros[0].v)
        XCTAssertEqual(zeros[1].o, 0)
        XCTAssertEqual(zeros[1].v, 0)
        XCTAssertEqual(MinuteBars.fromDTOs(zeros, date: "2023-09-04").count, 1)
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
        let second = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(http.requests.count, 1)
        first.cancel()
        http.releasePaused()
        let bars = try await second.value
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular)?.count, 1)
        do {
            _ = try await first.value
            XCTFail("cancelled waiter should throw")
        } catch {
            XCTAssertTrue(error.isCancellation)
        }
    }

    func testCancelledLastWaiterDoesNotWriteCache() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let task = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        await waitUntil { http.requests.count == 1 }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled load should throw")
        } catch {
            XCTAssertTrue(error.isCancellation)
        }
        XCTAssertNil(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular))
    }

    func testLoadAfterCancelledInflightStartsNewRequest() async throws {
        let http = ScriptedHTTP()
        http.pauseSends = true
        http.rawResults = [
            .success(Data(#"[{"d":"09:30","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[{"d":"09:31","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let first = Task { try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular) }
        await waitUntil { http.requests.count == 1 }
        first.cancel()
        _ = try? await first.value
        http.pauseSends = false
        http.releasePaused()
        let bars = try await store.load(symbol: "AAPL", date: "2026-09-04", session: .regular)
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(bars.first?.close, 2)
        XCTAssertEqual(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular)?.first?.close, 2)
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

    func testLoadsAndMergesDailyBarsWithoutCappingOldest() async throws {
        let http = ScriptedHTTP()
        http.rawResults = [
            .success(Data(#"[{"d":"2026-09-03","o":1,"h":1,"l":1,"c":1,"v":1}]"#.utf8)),
            .success(Data(#"[{"d":"2026-09-04","o":2,"h":2,"l":2,"c":2,"v":2}]"#.utf8)),
            .success(Data(#"[]"#.utf8)),
        ]
        let store = BarStore(api: BarsAPI(client: http))
        let first = try await store.loadDaily(symbol: " aapl ", startDate: "2026-05-27")
        XCTAssertEqual(first.map(\.close), [1])
        XCTAssertEqual(http.requests.first?.path, "alpaca/market/daily-bars")
        XCTAssertEqual(http.requests.first?.query["symbol"], "AAPL")
        XCTAssertEqual(http.requests.first?.query["timeFrame"], "1Day")
        XCTAssertEqual(http.requests.first?.query["market"], "us")
        XCTAssertEqual(http.requests.first?.query["startDate"], "2026-05-27")
        XCTAssertEqual(store.cachedDaily(symbol: "AAPL")?.map(\.close), [1])
        XCTAssertNil(store.cached(symbol: "AAPL", date: "2026-09-04", session: .regular))

        let merged = try await store.loadDaily(symbol: "AAPL", startDate: "2026-09-03")
        XCTAssertEqual(merged.map { MarketClock.usDateString(from: $0.time) }, ["2026-09-03", "2026-09-04"])
        XCTAssertEqual(merged.map(\.close), [1, 2])

        let kept = try await store.loadDaily(symbol: "AAPL", startDate: "2026-06-01")
        XCTAssertEqual(kept.map(\.close), [1, 2])
        XCTAssertEqual(http.requests.count, 3)
    }
}
