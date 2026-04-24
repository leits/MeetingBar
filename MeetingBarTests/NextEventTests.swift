//
//  NextEventTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

@testable import MeetingBar
import XCTest

class NextEventTests: XCTestCase {
    // Fixed point in time — all events are created relative to this, and the same
    // value is passed to EventSelectionPolicy, so tests never depend on a real clock.
    private let now = Date()

    // Builds permissive settings with individual overrides per test.
    private func settings(
        showEventsForPeriod: ShowEventsForPeriod = .today_n_tomorrow,
        personalEventsAppereance: PastEventsAppereance = .show_active,
        dismissedEvents: [ProcessedEvent] = [],
        nonAllDayEvents: NonAlldayEventsAppereance = .show,
        showPendingEvents: PendingEventsAppereance = .show,
        showTentativeEvents: TentativeEventsAppereance = .show,
        ongoingEventVisibility: OngoingEventVisibility = .showTenMinBeforeNext
    ) -> EventSelectionSettings {
        EventSelectionSettings(
            showEventsForPeriod: showEventsForPeriod,
            personalEventsAppereance: personalEventsAppereance,
            dismissedEvents: dismissedEvents,
            nonAllDayEvents: nonAllDayEvents,
            showPendingEvents: showPendingEvents,
            showTentativeEvents: showTentativeEvents,
            ongoingEventVisibility: ongoingEventVisibility
        )
    }

    private func nextEvent(_ events: [MBEvent], linkRequired: Bool = false, settings: EventSelectionSettings? = nil) -> MBEvent? {
        EventSelectionPolicy.nextEvent(
            from: events,
            linkRequired: linkRequired,
            settings: settings ?? self.settings(),
            now: now
        )
    }

    // MARK: - Basic selection

    func test_picksSoonestFutureEvent() {
        let e1 = makeFakeEvent(id: "1", start: now.addingTimeInterval(300), end: now.addingTimeInterval(3600), withLink: true)
        let e2 = makeFakeEvent(id: "2", start: now.addingTimeInterval(100), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([e1, e2]), e2)
    }

    func test_skipsEventsWithoutLink_whenLinkRequired() {
        let noLink  = makeFakeEvent(id: "A", start: now.addingTimeInterval(50), end: now.addingTimeInterval(3600), withLink: false)
        let withLink = makeFakeEvent(id: "B", start: now.addingTimeInterval(150), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([noLink, withLink], linkRequired: true), withLink)
    }

    func test_returnsNil_ifAllCandidatesLackLink_andLinkRequired() {
        let a = makeFakeEvent(id: "X", start: now.addingTimeInterval(100), end: now.addingTimeInterval(3600), withLink: false)
        let b = makeFakeEvent(id: "Y", start: now.addingTimeInterval(200), end: now.addingTimeInterval(3600), withLink: false)
        XCTAssertNil(nextEvent([a, b], linkRequired: true))
    }

    // MARK: - Status filters

    func test_skipsCanceledEvent() {
        let canceled = makeFakeEvent(id: "C", start: now.addingTimeInterval(50), end: now.addingTimeInterval(3600), status: .canceled, withLink: true)
        let good     = makeFakeEvent(id: "G", start: now.addingTimeInterval(100), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([canceled, good]), good)
    }

    func test_skipsDeclinedEvent() {
        let declined = makeFakeEvent(id: "D", start: now.addingTimeInterval(50), end: now.addingTimeInterval(3600), withLink: true, participationStatus: .declined)
        let good     = makeFakeEvent(id: "G", start: now.addingTimeInterval(100), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([declined, good]), good)
    }

    func test_skipsDismissedEvent() {
        let dismissed = makeFakeEvent(id: "DISMISSED", start: now.addingTimeInterval(100), end: now.addingTimeInterval(3600), withLink: true)
        let good      = makeFakeEvent(id: "GOOD", start: now.addingTimeInterval(200), end: now.addingTimeInterval(3600), withLink: true)
        let dismissedSettings = settings(dismissedEvents: [ProcessedEvent(id: "DISMISSED", lastModifiedDate: nil, eventEndDate: now.addingTimeInterval(3600))])
        XCTAssertEqual(nextEvent([dismissed, good], settings: dismissedSettings), good)
    }

    func test_skipsAllDayEvent() {
        let allDay = makeFakeEvent(id: "ALLDAY", start: now.addingTimeInterval(100), end: now.addingTimeInterval(86_500), isAllDay: true, withLink: true)
        let timed  = makeFakeEvent(id: "TIMED", start: now.addingTimeInterval(200), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([allDay, timed]), timed)
    }

    func test_skipsPendingEvent_whenPendingSetToHide() {
        let pending  = makeFakeEvent(id: "PENDING", start: now.addingTimeInterval(100), end: now.addingTimeInterval(3600), withLink: true, participationStatus: .pending)
        let accepted = makeFakeEvent(id: "ACCEPTED", start: now.addingTimeInterval(200), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([pending, accepted], settings: settings(showPendingEvents: .hide)), accepted)
    }

    func test_skipsTentativeEvent_whenTentativeSetToHide() {
        let tentative = makeFakeEvent(id: "TENTATIVE", start: now.addingTimeInterval(100), end: now.addingTimeInterval(3600), withLink: true, participationStatus: .tentative)
        let accepted  = makeFakeEvent(id: "ACCEPTED", start: now.addingTimeInterval(200), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([tentative, accepted], settings: settings(showTentativeEvents: .hide)), accepted)
    }

    // MARK: - Ongoing event visibility

    func test_hideImmediateAfter_skipsStartedEvent() {
        let running = makeFakeEvent(id: "RUNNING", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(3600), withLink: true)
        let future  = makeFakeEvent(id: "FUTURE", start: now.addingTimeInterval(300), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([running, future], settings: settings(ongoingEventVisibility: .hideImmediateAfter)), future)
    }

    func test_showTenMinAfter_showsEventBefore10MinMark() {
        let running = makeFakeEvent(id: "RUNNING", start: now.addingTimeInterval(-300), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([running], settings: settings(ongoingEventVisibility: .showTenMinAfter)), running)
    }

    func test_showTenMinAfter_hidesEventAfter10MinMark() {
        let running = makeFakeEvent(id: "RUNNING", start: now.addingTimeInterval(-660), end: now.addingTimeInterval(3600), withLink: true)
        let future  = makeFakeEvent(id: "FUTURE", start: now.addingTimeInterval(300), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([running, future], settings: settings(ongoingEventVisibility: .showTenMinAfter)), future)
    }

    func test_showTenMinBeforeNext_switchesToNextEvent() {
        // running event is the first candidate; next starts within 10 min so we switch
        let running = makeFakeEvent(id: "RUNNING", start: now.addingTimeInterval(-300), end: now.addingTimeInterval(3600), withLink: true)
        let next    = makeFakeEvent(id: "NEXT", start: now.addingTimeInterval(300), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([running, next], settings: settings(ongoingEventVisibility: .showTenMinBeforeNext)), next)
    }

    func test_showTenMinBeforeNext_keepsRunningEvent_whenNextIsFar() {
        let running = makeFakeEvent(id: "RUNNING", start: now.addingTimeInterval(-300), end: now.addingTimeInterval(3600), withLink: true)
        let far     = makeFakeEvent(id: "FAR", start: now.addingTimeInterval(700), end: now.addingTimeInterval(3600), withLink: true)
        XCTAssertEqual(nextEvent([running, far], settings: settings(ongoingEventVisibility: .showTenMinBeforeNext)), running)
    }
}
