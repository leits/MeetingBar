//
//  NotificationPlannerTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class NotificationPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(
        id: String = "evt",
        startsIn: TimeInterval,
        duration: TimeInterval = 1800,
        status: NotificationPlanningEvent.Status = .active,
        participation: NotificationPlanningEvent.ParticipationStatus = .active,
        allDay: Bool = false,
        hasMeetingLink: Bool = true
    ) -> NotificationPlanningEvent {
        NotificationPlanningEvent(
            id: id,
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(startsIn + duration),
            status: status,
            participationStatus: participation,
            isAllDay: allDay,
            hasMeetingLink: hasMeetingLink
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
            NotificationPlanner.plan(events: [], settings: allEnabled, now: now),
            []
        )
    }

    func testNothingPlannedWhenAllDisabled() {
        let plans = NotificationPlanner.plan(
            events: [event(startsIn: 600)],
            settings: allDisabled,
            now: now
        )
        XCTAssertEqual(plans, [])
    }

    func testAllFiveKindsForOneFutureEvent() {
        let plans = NotificationPlanner.plan(
            events: [event(startsIn: 600)],
            settings: allEnabled,
            now: now
        )
        XCTAssertEqual(Set(plans.map(\.kind)), Set(NotificationKind.allCases))
    }

    func testNoLinkEventDoesNotPlanFullscreenNotificationByDefault() {
        let plans = NotificationPlanner.plan(
            events: [event(startsIn: 600, hasMeetingLink: false)],
            settings: allEnabled,
            now: now
        )

        XCTAssertFalse(plans.map(\.kind).contains(.fullscreen))
    }

    func testNoLinkEventPlansFullscreenNotificationWhenEnabled() {
        let settings = NotificationPlanningSettings(
            eventStart: .disabled,
            eventEnd: .disabled,
            fullscreen: .init(enabled: true, offset: 5),
            autoJoin: .disabled,
            scriptOnStart: .disabled,
            dismissedEventIDs: [],
            fullscreenNotificationsForEventsWithoutMeetingLink: true
        )

        let plans = NotificationPlanner.plan(
            events: [event(startsIn: 600, hasMeetingLink: false)],
            settings: settings,
            now: now
        )

        XCTAssertEqual(plans.map(\.kind), [.fullscreen])
    }

    func testNoLinkEventDoesNotPlanScriptOnStart() {
        let settings = NotificationPlanningSettings(
            eventStart: .disabled,
            eventEnd: .disabled,
            fullscreen: .disabled,
            autoJoin: .disabled,
            scriptOnStart: .init(enabled: true, offset: 60),
            dismissedEventIDs: []
        )

        let plans = NotificationPlanner.plan(
            events: [event(startsIn: 600, hasMeetingLink: false)],
            settings: settings,
            now: now
        )

        XCTAssertTrue(plans.isEmpty)
    }

    func testJoinableEventPlansScriptOnStart() {
        let settings = NotificationPlanningSettings(
            eventStart: .disabled,
            eventEnd: .disabled,
            fullscreen: .disabled,
            autoJoin: .disabled,
            scriptOnStart: .init(enabled: true, offset: 60),
            dismissedEventIDs: []
        )

        let plans = NotificationPlanner.plan(
            events: [event(startsIn: 600, hasMeetingLink: true)],
            settings: settings,
            now: now
        )

        XCTAssertEqual(plans.map(\.kind), [.scriptOnStart])
    }

    func testFireDateIsAnchorMinusOffset() {
        let evt = event(startsIn: 600, duration: 1800)
        let plans = NotificationPlanner.plan(events: [evt], settings: allEnabled, now: now)

        let plansByKind = Dictionary(uniqueKeysWithValues: plans.map { ($0.kind, $0) })
        XCTAssertEqual(plansByKind[.eventStart]?.fireDate, evt.startDate.addingTimeInterval(-60))
        XCTAssertEqual(plansByKind[.eventEnd]?.fireDate, evt.endDate.addingTimeInterval(-300))
        XCTAssertEqual(plansByKind[.fullscreen]?.fireDate, evt.startDate.addingTimeInterval(-5))
        XCTAssertEqual(plansByKind[.autoJoin]?.fireDate, evt.startDate.addingTimeInterval(-5))
        XCTAssertEqual(plansByKind[.scriptOnStart]?.fireDate, evt.startDate.addingTimeInterval(-60))
    }

    func testCancelledEventProducesNothing() {
        let plans = NotificationPlanner.plan(
            events: [event(startsIn: 600, status: .canceled)],
            settings: allEnabled,
            now: now
        )
        XCTAssertEqual(plans, [])
    }

    func testDeclinedEventProducesNothing() {
        let plans = NotificationPlanner.plan(
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
        let plans = NotificationPlanner.plan(
            events: [event(startsIn: 600)],
            settings: settings,
            now: now
        )
        XCTAssertEqual(plans, [])
    }

    func testAllDayEventProducesNothing() {
        let plans = NotificationPlanner.plan(
            events: [event(startsIn: 600, allDay: true)],
            settings: allEnabled,
            now: now
        )
        XCTAssertEqual(plans, [])
    }

    func testFireDateInPastIsSkipped() {
        let plans = NotificationPlanner.plan(
            events: [event(startsIn: -30, duration: 600)],
            settings: allEnabled,
            now: now
        )

        XCTAssertEqual(plans.map(\.kind), [.eventEnd])
    }

    func testBackToBackEventsBothPlanned() {
        let first = event(id: "A", startsIn: 600, duration: 1800)
        let second = event(id: "B", startsIn: 2400, duration: 1800)
        let plans = NotificationPlanner.plan(
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
        let plans = NotificationPlanner.plan(
            events: [far, near],
            settings: allEnabled,
            now: now
        )
        let dates = plans.map(\.fireDate)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testIdentityIsStableForSameEventAndKind() {
        let evt = event(startsIn: 600)
        let first = NotificationPlanner.plan(events: [evt], settings: allEnabled, now: now)
        let second = NotificationPlanner.plan(events: [evt], settings: allEnabled, now: now)
        XCTAssertEqual(first.map(\.identity), second.map(\.identity))
    }

    func testIdentityChangesWhenEventStartDateChanges() {
        let original = event(startsIn: 600)
        let rescheduled = event(startsIn: 900)

        let plansBefore = NotificationPlanner.plan(
            events: [original], settings: allEnabled, now: now
        )
        let plansAfter = NotificationPlanner.plan(
            events: [rescheduled], settings: allEnabled, now: now
        )
        XCTAssertNotEqual(plansBefore.first?.identity, plansAfter.first?.identity)
    }

    func testIdentityIsStableWhenOnlyLastModifiedChanges() {
        let original = event(startsIn: 600)
        let sameTimeNewModified = NotificationPlanningEvent(
            id: original.id,
            startDate: original.startDate,
            endDate: original.endDate,
            status: original.status,
            participationStatus: original.participationStatus,
            isAllDay: original.isAllDay,
            hasMeetingLink: original.hasMeetingLink
        )

        let plansBefore = NotificationPlanner.plan(
            events: [original], settings: allEnabled, now: now
        )
        let plansAfter = NotificationPlanner.plan(
            events: [sameTimeNewModified], settings: allEnabled, now: now
        )
        XCTAssertEqual(plansBefore.map(\.identity), plansAfter.map(\.identity))
    }

    func testIdentityIncludesKindAndOffset() {
        let evt = event(startsIn: 600)
        let plans = NotificationPlanner.plan(events: [evt], settings: allEnabled, now: now)
        let identities = plans.map(\.identity)
        XCTAssertEqual(Set(identities).count, identities.count)
    }
}
