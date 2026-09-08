import XCTest
@testable import Moneyknows

final class ChartEasternTimeTests: XCTestCase {
    func testBusinessDayKeepsCalendarDateNotEasternPreviousEvening() {
        let day = ChartEasternTime.CalendarDay(year: 2026, month: 9, day: 4)
        var utcParts = DateComponents()
        utcParts.calendar = Calendar(identifier: .gregorian)
        utcParts.timeZone = TimeZone(secondsFromGMT: 0)
        utcParts.year = 2026
        utcParts.month = 9
        utcParts.day = 4
        let utcMidnight = utcParts.date!
        XCTAssertEqual(MarketClock.usTimeString(from: utcMidnight), "20:00")
        XCTAssertEqual(ChartEasternTime.tickLabel(utc: utcMidnight, calendarDay: day, kind: .dayOfMonth), "4")
        XCTAssertEqual(ChartEasternTime.tickLabel(utc: utcMidnight, calendarDay: day, kind: .year), "2026")
        XCTAssertEqual(ChartEasternTime.tickLabel(utc: utcMidnight, calendarDay: day, kind: .month), "Sep")
        XCTAssertEqual(ChartEasternTime.tickLabel(utc: utcMidnight, calendarDay: day, kind: .time), "2026-09-04")
        XCTAssertEqual(ChartEasternTime.crosshairLabel(utc: utcMidnight, calendarDay: day), "2026-09-04")
        XCTAssertEqual(MarketClock.usDateString(from: ChartEasternTime.date(calendarDay: day)!), "2026-09-04")
        XCTAssertEqual(MarketClock.usTimeString(from: ChartEasternTime.date(calendarDay: day)!), "00:00")
    }

    func testDateOnlyStringIsCalendarDay() {
        let parsed = ChartEasternTime.parse("2026-09-04")
        XCTAssertNil(parsed.instant)
        XCTAssertEqual(parsed.calendarDay, ChartEasternTime.CalendarDay(year: 2026, month: 9, day: 4))
        XCTAssertEqual(
            ChartEasternTime.crosshairLabel(utc: parsed.instant, calendarDay: parsed.calendarDay),
            "2026-09-04"
        )
    }

    func testUtcTimestampFormatsInEasternTime() {
        var parts = DateComponents()
        parts.calendar = Calendar(identifier: .gregorian)
        parts.timeZone = MarketClock.easternTimeZone
        parts.year = 2026
        parts.month = 9
        parts.day = 4
        parts.hour = 16
        parts.minute = 0
        let date = parts.date!
        XCTAssertEqual(ChartEasternTime.tickLabel(utc: date, calendarDay: nil, kind: .time), "16:00")
        XCTAssertEqual(ChartEasternTime.crosshairLabel(utc: date, calendarDay: nil), "16:00")
        XCTAssertEqual(ChartEasternTime.tickLabel(utc: date, calendarDay: nil, kind: .dayOfMonth), "4")
    }

    func testCalendarDayFromEasternDateKeepsThatCalendarDate() {
        var parts = DateComponents()
        parts.calendar = Calendar(identifier: .gregorian)
        parts.timeZone = MarketClock.easternTimeZone
        parts.year = 2026
        parts.month = 9
        parts.day = 4
        parts.hour = 16
        let date = parts.date!
        XCTAssertEqual(ChartEasternTime.calendarDay(for: date), ChartEasternTime.CalendarDay(year: 2026, month: 9, day: 4))
        XCTAssertEqual(MarketClock.addingCalendarDays(-100, to: "2026-09-04"), "2026-05-27")
    }
}
