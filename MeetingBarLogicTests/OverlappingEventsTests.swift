//
//  OverlappingEventsTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class OverlappingEventsTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func settings(
        dismissedEvents: Set<EventSelectionDismissal> = [],
        requiresMeetingLinkForNonAllDayEvents: Bool = false
    ) -> EventSelectionSettings {
        EventSelectionSettings(
            period: .todayAndTomorrow,
            includesPersonalEvents: true,
            dismissedEvents: dismissedEvents,
            requiresMeetingLinkForNonAllDayEvents: requiresMeetingLinkForNonAllDayEvents,
            hidesPendingEvents: false,
            hidesTentativeEvents: false,
            ongoingEventVisibility: .showTenMinBeforeNext
        )
    }

    /// `start`/`end` are minutes relative to `now`.
    private func event(
        _ id: String,
        start: Double,
        end: Double,
        isAllDay: Bool = false,
        hasMeetingLink: Bool = true,
        status: EventSelectionEvent.Status = .active,
        participationStatus: EventSelectionEvent.ParticipationStatus = .active
    ) -> EventSelectionEvent {
        EventSelectionEvent(
            sourceIndex: 0,
            id: id,
            lastModifiedDate: nil,
            startDate: now.addingTimeInterval(start * 60),
            endDate: now.addingTimeInterval(end * 60),
            isAllDay: isAllDay,
            hasMeetingLink: hasMeetingLink,
            hasAttendees: true,
            status: status,
            participationStatus: participationStatus
        )
    }

    private func overlapIDs(
        _ primary: EventSelectionEvent,
        _ others: [EventSelectionEvent],
        settings: EventSelectionSettings? = nil
    ) -> [String] {
        EventSelection.overlappingEvents(
            with: primary,
            from: [primary] + others,
            settings: settings ?? self.settings()
        ).map(\.id)
    }

    func testMeetingStartingMidwayThroughPrimaryOverlaps() {
        let primary = event("2:00-2:30", start: 0, end: 30)
        let later = event("2:05-2:30", start: 5, end: 30)

        XCTAssertEqual(overlapIDs(primary, [later]), ["2:05-2:30"])
    }

    func testMeetingAlreadyRunningWhenPrimaryStartsOverlaps() {
        let primary = event("primary", start: 0, end: 30)
        let running = event("running", start: -20, end: 10)

        XCTAssertEqual(overlapIDs(primary, [running]), ["running"])
    }

    func testBackToBackMeetingsDoNotOverlap() {
        let primary = event("primary", start: 0, end: 30)
        let next = event("next", start: 30, end: 60)
        let previous = event("previous", start: -30, end: 0)

        XCTAssertEqual(overlapIDs(primary, [next, previous]), [])
    }

    func testMeetingsTheMenuHidesAreNotOffered() {
        let primary = event("primary", start: 0, end: 30)
        let dismissed = event("dismissed", start: 0, end: 30)
        let declined = event("declined", start: 0, end: 30, participationStatus: .declined)
        let canceled = event("canceled", start: 0, end: 30, status: .canceled)
        let allDay = event("allday", start: -60, end: 600, isAllDay: true)
        let kept = event("kept", start: 0, end: 30)

        let result = overlapIDs(
            primary,
            [dismissed, declined, canceled, allDay, kept],
            settings: settings(dismissedEvents: [EventSelectionDismissal(id: "dismissed", lastModifiedDate: nil)])
        )

        XCTAssertEqual(result, ["kept"])
    }

    func testLinklessOverlapIsShownUnlessLinklessEventsAreHiddenEverywhere() {
        let primary = event("primary", start: 0, end: 30)
        let linkless = event("linkless", start: 0, end: 30, hasMeetingLink: false)

        XCTAssertEqual(overlapIDs(primary, [linkless]), ["linkless"])
        XCTAssertEqual(
            overlapIDs(primary, [linkless], settings: settings(requiresMeetingLinkForNonAllDayEvents: true)),
            []
        )
    }

    /// All-day events with a link alert while active; that alert must not list the whole day.
    func testAllDayTriggerListsNoOverlaps() {
        let primary = event("offsite", start: -540, end: 900, isAllDay: true)
        let standup = event("standup", start: 30, end: 45)

        XCTAssertEqual(overlapIDs(primary, [standup]), [])
    }
}
