import Foundation
import XCTest

@testable import MeetingBar

final class CalendarDateRangeTests: XCTestCase {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso8601)!
    }

    func testTodayUsesCalendarDayRatherThanNextTwentyFourHours() {
        let c = calendar("Europe/Kyiv")
        let interval = calendarDateRange(
            for: .today,
            now: date("2026-10-18T23:30:00+03:00"),
            calendar: c
        )

        XCTAssertEqual(interval.from, date("2026-10-17T21:00:00Z"))
        XCTAssertEqual(interval.to, date("2026-10-18T21:00:00Z"))
    }

    func testTomorrowPeriodCoversSpringDSTTransition() {
        let c = calendar("Europe/Kyiv")
        let interval = calendarDateRange(
            for: .today_n_tomorrow,
            now: date("2026-03-28T12:00:00+02:00"),
            calendar: c
        )

        XCTAssertEqual(interval.from, date("2026-03-27T22:00:00Z"))
        XCTAssertEqual(interval.to, date("2026-03-29T21:00:00Z"))
        XCTAssertEqual(interval.to.timeIntervalSince(interval.from), 47 * 3600)
    }

    func testTodayCoversAutumnDSTTransition() {
        let c = calendar("Europe/Kyiv")
        let interval = calendarDateRange(
            for: .today,
            now: date("2026-10-25T12:00:00+02:00"),
            calendar: c
        )

        XCTAssertEqual(interval.from, date("2026-10-24T21:00:00Z"))
        XCTAssertEqual(interval.to, date("2026-10-25T22:00:00Z"))
        XCTAssertEqual(interval.to.timeIntervalSince(interval.from), 25 * 3600)
    }

    func testSameInstantUsesInjectedTimezoneForCalendarBoundaries() {
        let now = date("2026-10-18T23:30:00Z")
        let kyiv = calendarDateRange(for: .today, now: now, calendar: calendar("Europe/Kyiv"))
        let losAngeles = calendarDateRange(for: .today, now: now, calendar: calendar("America/Los_Angeles"))

        XCTAssertNotEqual(kyiv.from, losAngeles.from)
        XCTAssertTrue(kyiv.from <= now && now < kyiv.to)
        XCTAssertTrue(losAngeles.from <= now && now < losAngeles.to)
    }

    func testBoundaryAtMidnightBelongsToNextDay() {
        let c = calendar("Europe/Kyiv")
        let before = calendarDateRange(
            for: .today,
            now: date("2026-10-18T20:59:59Z"),
            calendar: c
        )
        let after = calendarDateRange(
            for: .today,
            now: date("2026-10-18T21:00:00Z"),
            calendar: c
        )

        XCTAssertEqual(before.to, after.from)
    }
}
