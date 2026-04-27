//
//  NotificationPlanningPolicyTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class NotificationPlanningPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(
        id: String = "evt",
        startsIn: TimeInterval,
        duration: TimeInterval = 1800,
        status: MBEventStatus = .confirmed,
        participation: MBEventAttendeeStatus = .accepted,
        allDay: Bool = false
    ) -> MBEvent {
        makeFakeEvent(
            id: id,
            start: now.addingTimeInterval(startsIn),
            end: now.addingTimeInterval(startsIn + duration),
            isAllDay: allDay,
            status: status,
            withLink: true,
            participationStatus: participation
        )
    }

    private let allEnabled = NotificationPlanningSettings(
        eventStart: .init(enabled: true, offset: 60),       // 1 min before start
        eventEnd: .init(enabled: true, offset: 300),        // 5 min before end
        fullscreen: .init(enabled: true, offset: 5),        // at start
        autoJoin: .init(enabled: true, offset: 5),          // at start
        scriptOnStart: .init(enabled: true, offset: 60),    // 1 min before start
        dismissedEventIDs: []
    )

    private let allDisabled = NotificationPlanningSettings(
        eventStart: .disabled,
        eventEnd: .disabled,
        fullscreen: .disabled,
        autoJoin: .disabled,
        scriptOnStart: .disabled,
        dismissedEventIDs: []
    )

    func testEmptyEventListProducesNothing() {
        XCTAssertEqual(
            NotificationPlanningPolicy.plan(events: [], settings: allEnabled, now: now),
            []
        )
    }

    func testNothingPlannedWhenAllDisabled() {
        let plans = NotificationPlanningPolicy.plan(
            events: [event(startsIn: 600)],
            settings: allDisabled,
            now: now
        )
        XCTAssertEqual(plans, [])
    }

    func testAllFiveKindsForOneFutureEvent() {
        let plans = NotificationPlanningPolicy.plan(
            events: [event(startsIn: 600)],
            settings: allEnabled,
            now: now
        )
        XCTAssertEqual(Set(plans.map(\.kind)), Set(NotificationKind.allCases))
    }

    func testFireDateIsAnchorMinusOffset() {
        let evt = event(startsIn: 600, duration: 1800)
        let plans = NotificationPlanningPolicy.plan(events: [evt], settings: allEnabled, now: now)

        let plansByKind = Dictionary(uniqueKeysWithValues: plans.map { ($0.kind, $0) })
        XCTAssertEqual(plansByKind[.eventStart]?.fireDate, evt.startDate.addingTimeInterval(-60))
        XCTAssertEqual(plansByKind[.eventEnd]?.fireDate, evt.endDate.addingTimeInterval(-300))
        XCTAssertEqual(plansByKind[.fullscreen]?.fireDate, evt.startDate.addingTimeInterval(-5))
        XCTAssertEqual(plansByKind[.autoJoin]?.fireDate, evt.startDate.addingTimeInterval(-5))
        XCTAssertEqual(plansByKind[.scriptOnStart]?.fireDate, evt.startDate.addingTimeInterval(-60))
    }

    func testCancelledEventProducesNothing() {
        let plans = NotificationPlanningPolicy.plan(
            events: [event(startsIn: 600, status: .canceled)],
            settings: allEnabled,
            now: now
        )
        XCTAssertEqual(plans, [])
    }

    func testDeclinedEventProducesNothing() {
        let plans = NotificationPlanningPolicy.plan(
            events: [event(startsIn: 600, participation: .declined)],
            settings: allEnabled,
            now: now
        )
        XCTAssertEqual(plans, [])
    }

    func testDismissedEventProducesNothing() {
        var settings = allEnabled
        settings = NotificationPlanningSettings(
            eventStart: settings.eventStart,
            eventEnd: settings.eventEnd,
            fullscreen: settings.fullscreen,
            autoJoin: settings.autoJoin,
            scriptOnStart: settings.scriptOnStart,
            dismissedEventIDs: ["evt"]
        )
        let plans = NotificationPlanningPolicy.plan(
            events: [event(startsIn: 600)],
            settings: settings,
            now: now
        )
        XCTAssertEqual(plans, [])
    }

    func testAllDayEventProducesNothing() {
        let plans = NotificationPlanningPolicy.plan(
            events: [event(startsIn: 600, allDay: true)],
            settings: allEnabled,
            now: now
        )
        XCTAssertEqual(plans, [])
    }

    func testFireDateInPastIsSkipped() {
        // Event started 30 s ago; eventStart offset 60 s would fire 90 s ago.
        let plans = NotificationPlanningPolicy.plan(
            events: [event(startsIn: -30, duration: 600)],
            settings: allEnabled,
            now: now
        )
        // eventStart, fullscreen (offset 5), autoJoin (offset 5), scriptOnStart
        // all anchor at startDate which is in the past — every plan target is
        // earlier than now. Only eventEnd remains (5 min before endDate = 270 s
        // from now).
        XCTAssertEqual(plans.map(\.kind), [.eventEnd])
    }

    func testBackToBackEventsBothPlanned() {
        let first = event(id: "A", startsIn: 600, duration: 1800)
        let second = event(id: "B", startsIn: 2400, duration: 1800)
        let plans = NotificationPlanningPolicy.plan(
            events: [first, second],
            settings: allEnabled,
            now: now
        )
        let eventIDs = Set(plans.map(\.eventID))
        XCTAssertEqual(eventIDs, Set(["A", "B"]),
                       "scheduler must plan for every visible event, not only the next one")
    }

    func testOutputSortedAscendingByFireDate() {
        let near = event(id: "near", startsIn: 600)
        let far = event(id: "far", startsIn: 7200)
        let plans = NotificationPlanningPolicy.plan(
            events: [far, near],
            settings: allEnabled,
            now: now
        )
        let dates = plans.map(\.fireDate)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testIdentityIsStableForSameEventAndKind() {
        let evt = event(startsIn: 600)
        let first = NotificationPlanningPolicy.plan(events: [evt], settings: allEnabled, now: now)
        let second = NotificationPlanningPolicy.plan(events: [evt], settings: allEnabled, now: now)
        XCTAssertEqual(first.map(\.identity), second.map(\.identity))
    }

    func testIdentityChangesWhenEventLastModifiedChanges() {
        let originalModified = Date(timeIntervalSince1970: 1_000_000)
        let rescheduledModified = Date(timeIntervalSince1970: 1_000_060) // one minute later

        let original = makeFakeEvent(
            id: "evt",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(2400),
            withLink: true,
            lastModifiedDate: originalModified
        )
        let rescheduled = makeFakeEvent(
            id: "evt",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(2400),
            withLink: true,
            lastModifiedDate: rescheduledModified
        )

        let plansBefore = NotificationPlanningPolicy.plan(
            events: [original], settings: allEnabled, now: now
        )
        let plansAfter = NotificationPlanningPolicy.plan(
            events: [rescheduled], settings: allEnabled, now: now
        )
        XCTAssertNotEqual(plansBefore.first?.identity, plansAfter.first?.identity)
    }

    func testIdentityIncludesKindAndOffset() {
        let evt = event(startsIn: 600)
        let plans = NotificationPlanningPolicy.plan(events: [evt], settings: allEnabled, now: now)
        let identities = plans.map(\.identity)
        XCTAssertEqual(Set(identities).count, identities.count,
                       "every (kind, offset) pair must produce a distinct identity")
    }
}
