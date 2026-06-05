//
//  NextEventTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class NextEventTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func settings(
        period: EventSelectionPeriod = .todayAndTomorrow,
        includesPersonalEvents: Bool = true,
        dismissedEvents: Set<EventSelectionDismissal> = [],
        requiresMeetingLinkForNonAllDayEvents: Bool = false,
        hidesPendingEvents: Bool = false,
        hidesTentativeEvents: Bool = false,
        ongoingEventVisibility: EventSelectionOngoingVisibility = .showTenMinBeforeNext
    ) -> EventSelectionSettings {
        EventSelectionSettings(
            period: period,
            includesPersonalEvents: includesPersonalEvents,
            dismissedEvents: dismissedEvents,
            requiresMeetingLinkForNonAllDayEvents: requiresMeetingLinkForNonAllDayEvents,
            hidesPendingEvents: hidesPendingEvents,
            hidesTentativeEvents: hidesTentativeEvents,
            ongoingEventVisibility: ongoingEventVisibility
        )
    }

    private func event(
        id: String,
        startsIn: TimeInterval,
        duration: TimeInterval = 3600,
        sourceIndex: Int = 0,
        lastModifiedDate: Date? = nil,
        isAllDay: Bool = false,
        hasMeetingLink: Bool = true,
        hasAttendees: Bool = true,
        status: EventSelectionEvent.Status = .active,
        participationStatus: EventSelectionEvent.ParticipationStatus = .active
    ) -> EventSelectionEvent {
        EventSelectionEvent(
            sourceIndex: sourceIndex,
            id: id,
            lastModifiedDate: lastModifiedDate,
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(startsIn + duration),
            isAllDay: isAllDay,
            hasMeetingLink: hasMeetingLink,
            hasAttendees: hasAttendees,
            status: status,
            participationStatus: participationStatus
        )
    }

    private func event(
        id: String,
        startDate: Date,
        duration: TimeInterval = 3600,
        hasMeetingLink: Bool = true,
        hasAttendees: Bool = true
    ) -> EventSelectionEvent {
        EventSelectionEvent(
            sourceIndex: 0,
            id: id,
            lastModifiedDate: nil,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            isAllDay: false,
            hasMeetingLink: hasMeetingLink,
            hasAttendees: hasAttendees,
            status: .active,
            participationStatus: .active
        )
    }

    private func nextEvent(
        _ events: [EventSelectionEvent],
        linkRequired: Bool = false,
        settings: EventSelectionSettings? = nil
    ) -> EventSelectionEvent? {
        EventSelection.nextEvent(
            from: events,
            linkRequired: linkRequired,
            settings: settings ?? self.settings(),
            now: now
        )
    }

    func testPicksSoonestFutureEvent() {
        let e1 = event(id: "1", startsIn: 300)
        let e2 = event(id: "2", startsIn: 100)
        XCTAssertEqual(nextEvent([e1, e2]), e2)
    }

    func testTodayPeriodExcludesTomorrowEvents() throws {
        let startOfToday = Calendar.current.startOfDay(for: now)
        let startOfTomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: startOfToday))
        let tomorrow = event(id: "TOMORROW", startDate: startOfTomorrow.addingTimeInterval(3600))

        XCTAssertNil(nextEvent([tomorrow], settings: settings(period: .today)))
        XCTAssertEqual(nextEvent([tomorrow], settings: settings(period: .todayAndTomorrow)), tomorrow)
    }

    func testSkipsEventsEndingInsideRefreshGraceWindow() {
        let almostEnded = event(id: "ALMOST_DONE", startsIn: -300, duration: 330)
        let future = event(id: "FUTURE", startsIn: 300)

        XCTAssertEqual(nextEvent([almostEnded, future]), future)
    }

    func testSkipsPersonalEventsWhenDisabled() {
        let personal = event(id: "PERSONAL", startsIn: 100, hasAttendees: false)
        let meeting = event(id: "MEETING", startsIn: 200, hasAttendees: true)

        XCTAssertEqual(nextEvent([personal, meeting], settings: settings(includesPersonalEvents: false)), meeting)
    }

    func testSkipsEventsWithoutLinkWhenLinkRequired() {
        let noLink = event(id: "A", startsIn: 50, hasMeetingLink: false)
        let withLink = event(id: "B", startsIn: 150, hasMeetingLink: true)
        XCTAssertEqual(nextEvent([noLink, withLink], linkRequired: true), withLink)
    }

    func testSkipsEventsWithoutLinkWhenRequiredBySettings() {
        let noLink = event(id: "A", startsIn: 50, hasMeetingLink: false)
        let withLink = event(id: "B", startsIn: 150, hasMeetingLink: true)

        XCTAssertEqual(
            nextEvent([noLink, withLink], settings: settings(requiresMeetingLinkForNonAllDayEvents: true)),
            withLink
        )
    }

    func testReturnsNilIfAllCandidatesLackLinkAndLinkRequired() {
        let first = event(id: "X", startsIn: 100, hasMeetingLink: false)
        let second = event(id: "Y", startsIn: 200, hasMeetingLink: false)
        XCTAssertNil(nextEvent([first, second], linkRequired: true))
    }

    func testSkipsCanceledEvent() {
        let canceled = event(id: "C", startsIn: 50, status: .canceled)
        let good = event(id: "G", startsIn: 100)
        XCTAssertEqual(nextEvent([canceled, good]), good)
    }

    func testSkipsDeclinedEvent() {
        let declined = event(id: "D", startsIn: 50, participationStatus: .declined)
        let good = event(id: "G", startsIn: 100)
        XCTAssertEqual(nextEvent([declined, good]), good)
    }

    func testSkipsDismissedEvent() {
        let lastModifiedDate = now.addingTimeInterval(-60)
        let dismissed = event(
            id: "DISMISSED",
            startsIn: 100,
            lastModifiedDate: lastModifiedDate
        )
        let good = event(id: "GOOD", startsIn: 200)
        let dismissal = EventSelectionDismissal(
            id: dismissed.id,
            lastModifiedDate: lastModifiedDate
        )

        XCTAssertEqual(
            nextEvent([dismissed, good], settings: settings(dismissedEvents: [dismissal])),
            good
        )
    }

    func testModifiedDismissedEventBecomesVisibleAgain() {
        let dismissal = EventSelectionDismissal(
            id: "DISMISSED",
            lastModifiedDate: now.addingTimeInterval(-120)
        )
        let modified = event(
            id: dismissal.id,
            startsIn: 100,
            lastModifiedDate: now.addingTimeInterval(-60)
        )

        XCTAssertEqual(
            nextEvent([modified], settings: settings(dismissedEvents: [dismissal])),
            modified
        )
    }

    func testSkipsAllDayEvent() {
        let allDay = event(id: "ALLDAY", startsIn: 100, duration: 86_500, isAllDay: true)
        let timed = event(id: "TIMED", startsIn: 200)
        XCTAssertEqual(nextEvent([allDay, timed]), timed)
    }

    func testSkipsPendingEventWhenPendingSetToHide() {
        let pending = event(id: "PENDING", startsIn: 100, participationStatus: .pending)
        let accepted = event(id: "ACCEPTED", startsIn: 200)
        XCTAssertEqual(nextEvent([pending, accepted], settings: settings(hidesPendingEvents: true)), accepted)
    }

    func testKeepsPendingEventWhenSettingAllowsPending() {
        let pending = event(id: "PENDING", startsIn: 100, participationStatus: .pending)

        XCTAssertEqual(nextEvent([pending], settings: settings(hidesPendingEvents: false)), pending)
    }

    func testSkipsTentativeEventWhenTentativeSetToHide() {
        let tentative = event(id: "TENTATIVE", startsIn: 100, participationStatus: .tentative)
        let accepted = event(id: "ACCEPTED", startsIn: 200)
        XCTAssertEqual(nextEvent([tentative, accepted], settings: settings(hidesTentativeEvents: true)), accepted)
    }

    func testKeepsTentativeEventWhenSettingAllowsTentative() {
        let tentative = event(id: "TENTATIVE", startsIn: 100, participationStatus: .tentative)

        XCTAssertEqual(nextEvent([tentative], settings: settings(hidesTentativeEvents: false)), tentative)
    }

    func testHideImmediateAfterSkipsStartedEvent() {
        let running = event(id: "RUNNING", startsIn: -60)
        let future = event(id: "FUTURE", startsIn: 300)
        XCTAssertEqual(
            nextEvent([running, future], settings: settings(ongoingEventVisibility: .hideImmediateAfter)),
            future
        )
    }

    func testShowTenMinAfterShowsEventBefore10MinMark() {
        let running = event(id: "RUNNING", startsIn: -300)
        XCTAssertEqual(
            nextEvent([running], settings: settings(ongoingEventVisibility: .showTenMinAfter)),
            running
        )
    }

    func testShowTenMinAfterHidesEventAfter10MinMark() {
        let running = event(id: "RUNNING", startsIn: -660)
        let future = event(id: "FUTURE", startsIn: 300)
        XCTAssertEqual(
            nextEvent([running, future], settings: settings(ongoingEventVisibility: .showTenMinAfter)),
            future
        )
    }

    func testShowTenMinBeforeNextSwitchesToNextEvent() {
        let running = event(id: "RUNNING", startsIn: -300)
        let next = event(id: "NEXT", startsIn: 300)
        XCTAssertEqual(
            nextEvent([running, next], settings: settings(ongoingEventVisibility: .showTenMinBeforeNext)),
            next
        )
    }

    func testShowTenMinBeforeNextKeepsRunningEventWhenNextIsFar() {
        let running = event(id: "RUNNING", startsIn: -300)
        let far = event(id: "FAR", startsIn: 700)
        XCTAssertEqual(
            nextEvent([running, far], settings: settings(ongoingEventVisibility: .showTenMinBeforeNext)),
            running
        )
    }
}
