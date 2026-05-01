//
//  StatusBarPresentationPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class StatusBarPresentationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func settings(
        hasSelectedCalendars: Bool = true,
        showEventMaxTimeUntilEventEnabled: Bool = false,
        threshold: Int = 30
    ) -> StatusBarPresentationSettings {
        StatusBarPresentationSettings(
            hasSelectedCalendars: hasSelectedCalendars,
            showEventMaxTimeUntilEventEnabled: showEventMaxTimeUntilEventEnabled,
            showEventMaxTimeUntilEventThreshold: threshold
        )
    }

    func testIdleWhenNoCalendarsSelected() {
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(60),
            settings: settings(hasSelectedCalendars: false),
            now: now
        )
        XCTAssertEqual(mode, .idle,
                       "no calendars selected → idle regardless of any next event")
    }

    func testNoUpcomingWhenSelectedButNoEvent() {
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: nil,
            settings: settings(),
            now: now
        )
        XCTAssertEqual(mode, .noUpcoming)
    }

    func testNextEventWhenThresholdDisabled() {
        // Even an event 12 hours away renders as "next" when the threshold
        // toggle is off — that is the legacy default behavior.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(43_200),
            settings: settings(showEventMaxTimeUntilEventEnabled: false),
            now: now
        )
        XCTAssertEqual(mode, .nextEvent)
    }

    func testNextEventWhenWithinThreshold() {
        // Threshold 30 min, event 10 min away → within threshold → render
        // as next event with title.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(600),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .nextEvent)
    }

    func testAfterThresholdWhenBeyondThreshold() {
        // Threshold 30 min, event 45 min away → past threshold → alarm hint.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(2700),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .afterThreshold)
    }

    func testOngoingEventCountsAsNextEvent() {
        // An event that started 5 min ago (timeUntilStart < 0) is below
        // any positive threshold and should render as the current next event.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(-300),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .nextEvent,
                       "negative timeUntilStart is always within any positive threshold")
    }

    func testThresholdBoundaryIsExclusive() {
        // Threshold 30 min, event exactly 30 min away → not strictly less
        // than the threshold → afterThreshold. Documents the existing
        // boundary semantics inherited from updateTitle().
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(1800),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .afterThreshold)
    }
}
