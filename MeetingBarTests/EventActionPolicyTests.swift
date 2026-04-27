//
//  EventActionPolicyTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class EventActionPolicyTests: BaseTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func eventStartingIn(_ secondsFromNow: TimeInterval, withLink: Bool = true, allDay: Bool = false) -> MBEvent {
        makeFakeEvent(
            id: "evt-1",
            start: now.addingTimeInterval(secondsFromNow),
            end: now.addingTimeInterval(secondsFromNow + 1800),
            isAllDay: allDay,
            withLink: withLink
        )
    }

    private let fullscreenLikeConfig = EventActionConfig(
        actionTime: 60,
        allowsRecentlyStarted: true,
        requiresMeetingLink: true
    )

    private let scriptLikeConfig = EventActionConfig(
        actionTime: 60,
        allowsRecentlyStarted: false,
        requiresMeetingLink: false
    )

    func testCleanupExpiredDropsEndedEntries() {
        let processed = [
            ProcessedEvent(id: "ended", lastModifiedDate: nil, eventEndDate: now.addingTimeInterval(-1)),
            ProcessedEvent(id: "active", lastModifiedDate: nil, eventEndDate: now.addingTimeInterval(60))
        ]
        let kept = EventActionPolicy.cleanupExpired(processed, now: now)
        XCTAssertEqual(kept.map(\.id), ["active"])
    }

    func testEvaluateReturnsNilOutsideWindow() {
        let event = eventStartingIn(120)
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: [], now: now
        )
        XCTAssertNil(decision)
    }

    func testEvaluateFiresInsideWindow() {
        let event = eventStartingIn(30)
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision)
        XCTAssertTrue(decision?.shouldFireSideEffect ?? false)
        XCTAssertEqual(decision?.updatedProcessed.map(\.id), ["evt-1"])
    }

    func testEvaluateAllowsRecentlyStartedWhenConfigured() {
        let event = eventStartingIn(-10)
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision, "fullscreen-like config should still fire 10s after start")
    }

    func testEvaluateRejectsRecentlyStartedForScriptConfig() {
        let event = eventStartingIn(-10)
        let decision = EventActionPolicy.evaluate(
            event: event, config: scriptLikeConfig, processed: [], now: now
        )
        XCTAssertNil(decision, "script-like config does not fire after the event has started")
    }

    func testEvaluateAllDayEventActiveDuringRange() {
        let allDay = makeFakeEvent(
            id: "all-day",
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(3600),
            isAllDay: true,
            withLink: true
        )
        let decision = EventActionPolicy.evaluate(
            event: allDay, config: fullscreenLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision)
    }

    func testEvaluateSkipsAlreadyProcessedEvent() {
        let event = eventStartingIn(30)
        let processed = [ProcessedEvent(id: event.id, lastModifiedDate: event.lastModifiedDate, eventEndDate: event.endDate)]
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: processed, now: now
        )
        XCTAssertNil(decision)
    }

    func testEvaluateReprocessesAfterReschedule() {
        let event = eventStartingIn(30)
        let stale = ProcessedEvent(
            id: event.id,
            lastModifiedDate: event.lastModifiedDate?.addingTimeInterval(-3600),
            eventEndDate: event.endDate
        )
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: [stale], now: now
        )
        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.updatedProcessed.count, 1, "stale entry replaced, not duplicated")
        XCTAssertEqual(decision?.updatedProcessed.first?.lastModifiedDate, event.lastModifiedDate)
    }

    func testEvaluateUpdatesProcessedEvenWhenLinkMissing() {
        let event = eventStartingIn(30, withLink: false)
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision)
        XCTAssertFalse(decision?.shouldFireSideEffect ?? true,
                       "no meeting link → side effect skipped")
        XCTAssertEqual(decision?.updatedProcessed.map(\.id), ["evt-1"],
                       "entry still recorded so the event is not retried each tick")
    }

    func testEvaluateScriptConfigFiresWithoutLink() {
        let event = eventStartingIn(30, withLink: false)
        let decision = EventActionPolicy.evaluate(
            event: event, config: scriptLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision)
        XCTAssertTrue(decision?.shouldFireSideEffect ?? false)
    }
}
