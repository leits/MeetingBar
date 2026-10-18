import EventKit
import XCTest

@testable import MeetingBar

final class EventKitReadContractTests: XCTestCase {
    private let calendar = MBCalendar(
        title: "Calendar A", id: "cal-a", source: nil, email: nil, color: .black
    )

    private func rawEvent(id: String, date: Date) -> EKEvent {
        let event = EKEvent(eventStore: EKEventStore())
        event.title = id
        event.startDate = date
        event.endDate = date.addingTimeInterval(1800)
        return event
    }

    func testReadPassesSelectedIDsAndDateRangeThenMapsOccurrences() {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let to = from.addingTimeInterval(24 * 3600)
        let raw = rawEvent(id: "Standup", date: from.addingTimeInterval(3600))
        var requestedIDs: [String] = []
        var requestedFrom: Date?
        var requestedTo: Date?

        let results = mapEventKitRead(
            knownCalendars: [calendar],
            dateFrom: from,
            dateTo: to,
            customRegexes: []
        ) { calendarIDs, start, end in
            requestedIDs = calendarIDs
            requestedFrom = start
            requestedTo = end
            return [EventKitRawOccurrence(calendarID: "cal-a", event: raw)]
        }

        XCTAssertEqual(requestedIDs, ["cal-a"])
        XCTAssertEqual(requestedFrom, from)
        XCTAssertEqual(requestedTo, to)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Standup")
        XCTAssertEqual(results.first?.calendar.id, "cal-a")
        XCTAssertEqual(results.first?.scriptIdentifier, raw.calendarItemIdentifier)
    }

    func testUnknownCalendarOccurrencesAreIgnoredAndDuplicatesCollapsed() {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let event = rawEvent(id: "Standup", date: from)
        let results = mapEventKitRead(
            knownCalendars: [calendar],
            dateFrom: from,
            dateTo: from.addingTimeInterval(86_400),
            customRegexes: []
        ) { _, _, _ in
            [
                EventKitRawOccurrence(calendarID: "cal-a", event: event),
                EventKitRawOccurrence(calendarID: "cal-a", event: event),
                EventKitRawOccurrence(calendarID: "not-selected", event: event)
            ]
        }
        XCTAssertEqual(results.count, 1)
    }

    func testEmptySelectionSkipsEventKitQuery() {
        var readWasCalled = false
        let results = mapEventKitRead(
            knownCalendars: [],
            dateFrom: Date(timeIntervalSince1970: 0),
            dateTo: Date(timeIntervalSince1970: 100),
            customRegexes: []
        ) { _, _, _ in
            readWasCalled = true
            return []
        }
        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(readWasCalled)
    }

    func testRecurringOccurrencesKeepSeparateIdentities() {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let raw = rawEvent(id: "Recurring", date: from)
        raw.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)]
        let next = rawEvent(id: "Recurring", date: from.addingTimeInterval(86_400))
        next.recurrenceRules = raw.recurrenceRules

        let results = mapEventKitRead(
            knownCalendars: [calendar],
            dateFrom: from,
            dateTo: from.addingTimeInterval(2 * 86_400),
            customRegexes: []
        ) { _, _, _ in
            [
                EventKitRawOccurrence(calendarID: "cal-a", event: raw),
                EventKitRawOccurrence(calendarID: "cal-a", event: next)
            ]
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertNotEqual(results[0].id, results[1].id)
    }
}
