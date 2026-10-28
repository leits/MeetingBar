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

    func testReadPassesSelectedIDsAndDateRangeThenMapsOccurrences() throws {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let to = from.addingTimeInterval(24 * 3600)
        let raw = rawEvent(id: "Standup", date: from.addingTimeInterval(3600))
        var requestedIDs: [String] = []
        var requestedFrom: Date?
        var requestedTo: Date?

        let results = try mapEventKitRead(
            knownCalendars: [calendar],
            dateFrom: from,
            dateTo: to,
            customRegexes: []
        ) { calendarIDs, start, end in
            requestedIDs = calendarIDs
            requestedFrom = start
            requestedTo = end
            return EventKitReadSnapshot(
                availableCalendarIDs: ["cal-a"],
                occurrences: [EventKitRawOccurrence(calendarID: "cal-a", event: raw)]
            )
        }

        XCTAssertEqual(requestedIDs, ["cal-a"])
        XCTAssertEqual(requestedFrom, from)
        XCTAssertEqual(requestedTo, to)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Standup")
        XCTAssertEqual(results.first?.calendar.id, "cal-a")
        XCTAssertEqual(results.first?.scriptIdentifier, raw.calendarItemIdentifier)
    }

    func testUnknownCalendarOccurrenceIsExcludedEvenWithDistinctEventID() throws {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let allowed = rawEvent(id: "Allowed meeting", date: from)
        // A different start guarantees a different composed event ID even if
        // EventKit gives unsaved test events identical calendarItemIdentifiers.
        let unknown = rawEvent(id: "Must not appear", date: from.addingTimeInterval(3600))
        let results = try mapEventKitRead(
            knownCalendars: [calendar],
            dateFrom: from,
            dateTo: from.addingTimeInterval(86_400),
            customRegexes: []
        ) { _, _, _ in
            EventKitReadSnapshot(
                availableCalendarIDs: ["cal-a"],
                occurrences: [
                    EventKitRawOccurrence(calendarID: "cal-a", event: allowed),
                    EventKitRawOccurrence(calendarID: "not-selected", event: unknown)
                ]
            )
        }

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.map(\.title), ["Allowed meeting"])
        XCTAssertEqual(results.first?.calendar.id, "cal-a")
        XCTAssertEqual(results.first?.scriptIdentifier, allowed.calendarItemIdentifier)
        XCTAssertFalse(results.contains { $0.title == "Must not appear" })
    }

    func testDuplicateOccurrencesOfSameEventCollapseToOne() throws {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let raw = rawEvent(id: "One meeting", date: from)
        let results = try mapEventKitRead(
            knownCalendars: [calendar],
            dateFrom: from,
            dateTo: from.addingTimeInterval(86_400),
            customRegexes: []
        ) { _, _, _ in
            EventKitReadSnapshot(
                availableCalendarIDs: ["cal-a"],
                occurrences: [
                    EventKitRawOccurrence(calendarID: "cal-a", event: raw),
                    EventKitRawOccurrence(calendarID: "cal-a", event: raw)
                ]
            )
        }

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "One meeting")
        XCTAssertEqual(results.first?.scriptIdentifier, raw.calendarItemIdentifier)
    }

    func testUnavailableSelectedCalendarIsNotMistakenForEmptyEvents() {
        XCTAssertThrowsError(
            try requireAvailableEventKitSelection(
                selectedIDs: ["removed-calendar"],
                availableIDs: ["different-calendar"]
            )
        ) { error in
            XCTAssertEqual(
                error as? EventKitCalendarSelectionError,
                .selectedCalendarsUnavailable
            )
        }
    }

    func testEmptySelectionAndFullyAvailableSelectionStayValid() throws {
        XCTAssertNoThrow(try requireAvailableEventKitSelection(selectedIDs: [], availableIDs: []))
        XCTAssertNoThrow(try requireAvailableEventKitSelection(
            selectedIDs: ["selected", "other"],
            availableIDs: ["selected", "other"]
        ))
    }

    func testPartiallyMissingSelectionFailsRatherThanPublishingPartialEvents() {
        XCTAssertThrowsError(try requireAvailableEventKitSelection(
            selectedIDs: ["available", "lost"],
            availableIDs: ["available"]
        )) { error in
            XCTAssertEqual(
                error as? EventKitCalendarSelectionError,
                .selectedCalendarsUnavailable
            )
        }
    }

    func testCalendarDisappearingBetweenEnumerationAndQueryThrows() {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        var readWasCalled = false
        XCTAssertThrowsError(try mapEventKitRead(
            knownCalendars: [calendar],
            dateFrom: from,
            dateTo: from.addingTimeInterval(86_400),
            customRegexes: []
        ) { requestedIDs, _, _ in
            readWasCalled = true
            XCTAssertEqual(requestedIDs, ["cal-a"])
            // Calendar was present at the initial enumeration (above),
            // but EventKit returns no matching calendar just before query.
            return EventKitReadSnapshot(availableCalendarIDs: [], occurrences: [])
        }) { error in
            XCTAssertEqual(
                error as? EventKitCalendarSelectionError,
                .selectedCalendarsUnavailable
            )
        }
        XCTAssertTrue(readWasCalled)
    }

    func testSecondEnumerationPartiallyMissingCalendarAlsoThrows() {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let other = MBCalendar(
            title: "Other", id: "cal-b", source: nil, email: nil, color: .black
        )
        XCTAssertThrowsError(try mapEventKitRead(
            knownCalendars: [calendar, other],
            dateFrom: from,
            dateTo: from.addingTimeInterval(86_400),
            customRegexes: []
        ) { _, _, _ in
            EventKitReadSnapshot(availableCalendarIDs: ["cal-a"], occurrences: [])
        }) { error in
            XCTAssertEqual(error as? EventKitCalendarSelectionError, .selectedCalendarsUnavailable)
        }
    }

    func testEmptySelectionSkipsEventKitQuery() throws {
        var readWasCalled = false
        let results = try mapEventKitRead(
            knownCalendars: [],
            dateFrom: Date(timeIntervalSince1970: 0),
            dateTo: Date(timeIntervalSince1970: 100),
            customRegexes: []
        ) { _, _, _ in
            readWasCalled = true
            return EventKitReadSnapshot(availableCalendarIDs: [], occurrences: [])
        }
        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(readWasCalled)
    }

}
