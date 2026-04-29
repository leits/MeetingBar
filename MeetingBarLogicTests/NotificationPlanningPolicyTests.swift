//
//  NotificationPlanningPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class NotificationPlanningPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(
        id: String = "evt",
        startsIn: TimeInterval,
        duration: TimeInterval = 1800,
        status: NotificationPlanningEvent.Status = .active,
        participation: NotificationPlanningEvent.ParticipationStatus = .active,
        allDay: Bool = false,
        lastModifiedDate: Date? = Date(timeIntervalSince1970: 1_000_000)
    ) -> NotificationPlanningEvent {
        NotificationPlanningEvent(
            id: id,
            lastModifiedDate: lastModifiedDate,
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(startsIn + duration),
            status: status,
            participationStatus: participation,
            isAllDay: allDay
        )
    }

    private let allEnabled = NotificationPlanningSettings(
        eventStart: .init(enabled: true, offset: 60),
        eventEnd: .init(enabled: true, offset: 300),
        fullscreen: .init(enabled: true, offset: 5),
        autoJoin: .init(enabled: true, offset: 5),
        scriptOnStart: .init(enabled: true, offset: 60),
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
        let plans = NotificationPlanningPolicy.plan(
            events: [event(startsIn: -30, duration: 600)],
            settings: allEnabled,
            now: now
        )

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
        XCTAssertEqual(eventIDs, Set(["A", "B"]))
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
        let original = event(
            startsIn: 600,
            lastModifiedDate: Date(timeIntervalSince1970: 1_000_000)
        )
        let rescheduled = event(
            startsIn: 600,
            lastModifiedDate: Date(timeIntervalSince1970: 1_000_060)
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
        XCTAssertEqual(Set(identities).count, identities.count)
    }

    func testIdentityUsesZeroWhenLastModifiedDateIsMissing() {
        let evt = event(startsIn: 600, lastModifiedDate: nil)
        let plans = NotificationPlanningPolicy.plan(events: [evt], settings: allEnabled, now: now)

        XCTAssertTrue(plans.allSatisfy { $0.identity.contains("evt|0|") })
    }
}
