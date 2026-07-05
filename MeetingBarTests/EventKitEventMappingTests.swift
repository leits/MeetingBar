//
//  EventKitEventMappingTests.swift
//  MeetingBarTests
//
//  Contract tests for mbEvent(from:calendar:customRegexes:) id semantics.
//  EventKit shares calendarItemIdentifier across all occurrences of a
//  recurring event, so the mapped MBEvent.id must be occurrence-unique or
//  the downstream id-keyed dedup drops every occurrence but the first.
//

import EventKit
import XCTest

@testable import MeetingBar

final class EventKitEventMappingTests: XCTestCase {
    private let calendar = MBCalendar(
        title: "Test Calendar",
        id: "test-calendar",
        source: nil,
        email: nil,
        color: .black
    )

    private func makeRawEvent(start: Date, duration: TimeInterval = 1800) -> EKEvent {
        let rawEvent = EKEvent(eventStore: EKEventStore())
        rawEvent.title = "Standup"
        rawEvent.startDate = start
        rawEvent.endDate = start.addingTimeInterval(duration)
        return rawEvent
    }

    private func map(_ rawEvent: EKEvent) -> MBEvent {
        mbEvent(from: rawEvent, calendar: calendar, customRegexes: [])
    }

    func testOccurrencesOfSameRecurringEventMapToDistinctIds() {
        let firstStart = Date(timeIntervalSince1970: 1_751_610_600)
        let rawEvent = makeRawEvent(start: firstStart)
        rawEvent.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]

        let firstOccurrence = map(rawEvent)

        rawEvent.startDate = firstStart.addingTimeInterval(7 * 24 * 3600)
        rawEvent.endDate = rawEvent.startDate.addingTimeInterval(1800)
        let secondOccurrence = map(rawEvent)

        XCTAssertNotEqual(
            firstOccurrence.id,
            secondOccurrence.id,
            "Occurrences of a recurring event share calendarItemIdentifier; ids must differ per start date or id-keyed dedup drops all but the first occurrence"
        )
    }

    func testSameEventAtSameStartMapsToIdenticalIds() {
        let rawEvent = makeRawEvent(start: Date(timeIntervalSince1970: 1_751_610_600))

        let first = map(rawEvent)
        let second = map(rawEvent)

        XCTAssertEqual(
            first.id,
            second.id,
            "True duplicates (same event, same start) must keep identical ids so dedup still collapses them"
        )
    }

    func testDistinctEventsAtSameStartMapToDistinctIds() throws {
        let start = Date(timeIntervalSince1970: 1_751_610_600)
        let firstRawEvent = makeRawEvent(start: start)
        let secondRawEvent = makeRawEvent(start: start)

        try XCTSkipIf(
            firstRawEvent.calendarItemIdentifier == secondRawEvent.calendarItemIdentifier,
            "EventKit assigned no distinct identifiers to unsaved events in this environment; cannot exercise distinct-item id mapping"
        )

        let first = map(firstRawEvent)
        let second = map(secondRawEvent)

        XCTAssertNotEqual(
            first.id,
            second.id,
            "Different calendar items starting at the same time must keep distinct ids"
        )
    }

    func testCalendarOpenURLUsesRawCalendarItemIdentifier() {
        let rawEvent = makeRawEvent(start: Date(timeIntervalSince1970: 1_751_610_600))

        let event = map(rawEvent)

        XCTAssertEqual(
            event.calendarOpenURL?.absoluteString,
            "ical://ekevent/\(rawEvent.calendarItemIdentifier)",
            "Open-in-calendar URL must use the raw calendarItemIdentifier, not the occurrence-composed id"
        )
    }
}
