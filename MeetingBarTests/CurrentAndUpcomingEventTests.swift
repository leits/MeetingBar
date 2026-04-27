//
//  CurrentAndUpcomingEventTests.swift
//  MeetingBar
//
//  Tests for the currentAndUpcomingEvent() method and flip activation logic.
//

@testable import MeetingBar
import Defaults
import XCTest

// MARK: - currentAndUpcomingEvent() Tests

class CurrentAndUpcomingEventTests: BaseTestCase {
    private let now = Date()

    override func setUp() {
        super.setUp()
        Defaults[.allDayEvents] = .show
        Defaults[.nonAllDayEvents] = .show
        Defaults[.showPendingEvents] = .show
        Defaults[.showTentativeEvents] = .show
        Defaults[.declinedEventsAppereance] = .show_inactive
        Defaults[.personalEventsAppereance] = .show_active
        Defaults[.filterEventRegexes] = []
        Defaults[.dismissedEvents] = []
        Defaults[.showEventsForPeriod] = .today_n_tomorrow
    }

    // MARK: - Basic pairing

    func test_returnsNilWhenNoEvents() {
        let events: [MBEvent] = []
        let pair = events.currentAndUpcomingEvent()
        XCTAssertNil(pair.current)
        XCTAssertNil(pair.upcoming)
    }

    func test_returnsNilWhenNoCurrentEvent() {
        // Only a future event, nothing ongoing
        let future = makeFakeEvent(
            id: "F1",
            start: now.addingTimeInterval(1800),
            end: now.addingTimeInterval(3600)
        )
        let pair = [future].currentAndUpcomingEvent()
        XCTAssertNil(pair.current)
        XCTAssertNil(pair.upcoming)
    }

    func test_returnsCurrentButNoUpcoming_whenNoNextEvent() {
        // Ongoing event, no next event
        let current = makeFakeEvent(
            id: "C1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800)
        )
        let pair = [current].currentAndUpcomingEvent()
        XCTAssertEqual(pair.current?.id, "C1")
        XCTAssertNil(pair.upcoming)
    }

    func test_returnsBoth_whenNextStartsWithinGap() {
        // Current meeting: started 30 min ago, ends in 30 min
        let current = makeFakeEvent(
            id: "C1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800)
        )
        // Next meeting: starts in 35 min (5 min after current ends)
        // which is within the default 15-min gap threshold
        let upcoming = makeFakeEvent(
            id: "U1",
            start: now.addingTimeInterval(2100),
            end: now.addingTimeInterval(3900)
        )
        let pair = [current, upcoming].currentAndUpcomingEvent()
        XCTAssertEqual(pair.current?.id, "C1")
        XCTAssertEqual(pair.upcoming?.id, "U1")
    }

    func test_returnsNoUpcoming_whenNextStartsBeyondGap() {
        // Current meeting: started 30 min ago, ends in 30 min
        let current = makeFakeEvent(
            id: "C1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800)
        )
        // Next meeting: starts in 60 min (30 min after current ends)
        // which is beyond the default 15-min gap threshold
        let farAway = makeFakeEvent(
            id: "F1",
            start: now.addingTimeInterval(3600),
            end: now.addingTimeInterval(5400)
        )
        let pair = [current, farAway].currentAndUpcomingEvent()
        XCTAssertEqual(pair.current?.id, "C1")
        XCTAssertNil(pair.upcoming)
    }

    func test_customGapThreshold() {
        let current = makeFakeEvent(
            id: "C1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800)
        )
        // Next meeting starts 25 min after current ends (beyond 15-min default)
        let upcoming = makeFakeEvent(
            id: "U1",
            start: now.addingTimeInterval(3300),
            end: now.addingTimeInterval(5100)
        )

        // Default threshold (15 min = 900s): should NOT find upcoming
        let pair1 = [current, upcoming].currentAndUpcomingEvent(gapThreshold: 900)
        XCTAssertNil(pair1.upcoming)

        // Custom threshold (30 min = 1800s): SHOULD find upcoming
        let pair2 = [current, upcoming].currentAndUpcomingEvent(gapThreshold: 1800)
        XCTAssertEqual(pair2.upcoming?.id, "U1")
    }

    // MARK: - Filtering (declined, canceled, all-day)

    func test_skipsDeclinedCurrentEvent() {
        let declined = makeFakeEvent(
            id: "D1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800),
            participationStatus: .declined
        )
        let pair = [declined].currentAndUpcomingEvent()
        XCTAssertNil(pair.current)
    }

    func test_skipsCanceledCurrentEvent() {
        let canceled = makeFakeEvent(
            id: "X1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800),
            status: .canceled
        )
        let pair = [canceled].currentAndUpcomingEvent()
        XCTAssertNil(pair.current)
    }

    func test_skipsAllDayCurrentEvent() {
        let allDay = makeFakeEvent(
            id: "AD1",
            start: now.addingTimeInterval(-43200),
            end: now.addingTimeInterval(43200),
            isAllDay: true
        )
        let pair = [allDay].currentAndUpcomingEvent()
        XCTAssertNil(pair.current)
    }

    func test_skipsDeclinedUpcomingEvent() {
        let current = makeFakeEvent(
            id: "C1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800)
        )
        let declined = makeFakeEvent(
            id: "D1",
            start: now.addingTimeInterval(2100),
            end: now.addingTimeInterval(3900),
            participationStatus: .declined
        )
        let pair = [current, declined].currentAndUpcomingEvent()
        XCTAssertEqual(pair.current?.id, "C1")
        XCTAssertNil(pair.upcoming)
    }

    func test_skipsCanceledUpcomingEvent() {
        let current = makeFakeEvent(
            id: "C1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800)
        )
        let canceled = makeFakeEvent(
            id: "X1",
            start: now.addingTimeInterval(2100),
            end: now.addingTimeInterval(3900),
            status: .canceled
        )
        let pair = [current, canceled].currentAndUpcomingEvent()
        XCTAssertEqual(pair.current?.id, "C1")
        XCTAssertNil(pair.upcoming)
    }

    // MARK: - Back-to-back meetings (next starts at or before current ends)

    func test_backToBackMeetings() {
        let current = makeFakeEvent(
            id: "C1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(600)
        )
        // Next meeting starts exactly when current ends
        let upcoming = makeFakeEvent(
            id: "U1",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(2400)
        )
        let pair = [current, upcoming].currentAndUpcomingEvent()
        XCTAssertEqual(pair.current?.id, "C1")
        XCTAssertEqual(pair.upcoming?.id, "U1")
    }

    // MARK: - Picks first valid upcoming (not a later one)

    func test_picksFirstValidUpcoming() {
        let current = makeFakeEvent(
            id: "C1",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800)
        )
        let soon = makeFakeEvent(
            id: "U1",
            start: now.addingTimeInterval(2100),
            end: now.addingTimeInterval(3900)
        )
        let later = makeFakeEvent(
            id: "U2",
            start: now.addingTimeInterval(2400),
            end: now.addingTimeInterval(4200)
        )
        let pair = [current, soon, later].currentAndUpcomingEvent()
        XCTAssertEqual(pair.upcoming?.id, "U1")
    }
}

// MARK: - Flip Activation Logic Tests

class FlipActivationTests: BaseTestCase {
    private let now = Date()

    /// Simulates the flip activation guard from StatusBarItemController.
    /// Returns true if the flip should be active for the given mode.
    private func shouldFlip(mode: NextEventFlipMode, currentStart: Date) -> Bool {
        guard mode != .disabled else { return false }
        let minutesIntoCurrent = now.timeIntervalSince(currentStart) / 60
        let minMinutesIn: Double = (mode == .showAfterTenMin) ? 10.0 : 0.0
        return minutesIntoCurrent >= minMinutesIn
    }

    // MARK: - Disabled mode

    func test_noFlip_whenDisabled() {
        let currentStart = now.addingTimeInterval(-900) // 15 min in
        XCTAssertFalse(shouldFlip(mode: .disabled, currentStart: currentStart))
    }

    // MARK: - Show after start

    func test_showAfterStart_flipsImmediately() {
        // Just started, 1 minute in
        let currentStart = now.addingTimeInterval(-60)
        XCTAssertTrue(shouldFlip(mode: .showAfterStart, currentStart: currentStart))
    }

    func test_showAfterStart_flipsAtZero() {
        let currentStart = now
        XCTAssertTrue(shouldFlip(mode: .showAfterStart, currentStart: currentStart))
    }

    // MARK: - Show after 10 min

    func test_showAfterTenMin_noFlipEarlyInMeeting() {
        // 2 minutes into current
        let currentStart = now.addingTimeInterval(-120)
        XCTAssertFalse(shouldFlip(mode: .showAfterTenMin, currentStart: currentStart))
    }

    func test_showAfterTenMin_flipsAfterTenMin() {
        // 12 minutes into current
        let currentStart = now.addingTimeInterval(-720)
        XCTAssertTrue(shouldFlip(mode: .showAfterTenMin, currentStart: currentStart))
    }

    func test_showAfterTenMin_flipsAtExactlyTenMin() {
        // Exactly 10 minutes into current
        let currentStart = now.addingTimeInterval(-600)
        XCTAssertTrue(shouldFlip(mode: .showAfterTenMin, currentStart: currentStart))
    }

    func test_showAfterTenMin_noFlipAt9Min() {
        // 9 minutes into current
        let currentStart = now.addingTimeInterval(-540)
        XCTAssertFalse(shouldFlip(mode: .showAfterTenMin, currentStart: currentStart))
    }
}
