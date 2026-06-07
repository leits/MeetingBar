//
//  EventActionPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class EventActionPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func eventStartingIn(
        _ secondsFromNow: TimeInterval,
        withLink: Bool = true,
        allDay: Bool = false,
        lastModifiedDate: Date? = Date(timeIntervalSinceReferenceDate: 700_000_000)
    ) -> EventActionEvent {
        EventActionEvent(
            id: "evt-1",
            lastModifiedDate: lastModifiedDate,
            startDate: now.addingTimeInterval(secondsFromNow),
            endDate: now.addingTimeInterval(secondsFromNow + 1800),
            isAllDay: allDay,
            hasMeetingLink: withLink
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
        requiresMeetingLink: true
    )

    func testJoinableEventIsEligibleForFullscreenNotification() {
        XCTAssertTrue(
            FullscreenNotificationEligibilityPolicy.isEligible(
                hasMeetingLink: true,
                isAllDay: false,
                fullscreenNotificationsEnabled: true,
                includesEventsWithoutMeetingLink: false
            )
        )
    }

    func testNoLinkEventIsNotEligibleForFullscreenNotificationByDefault() {
        XCTAssertFalse(
            FullscreenNotificationEligibilityPolicy.isEligible(
                hasMeetingLink: false,
                isAllDay: false,
                fullscreenNotificationsEnabled: true,
                includesEventsWithoutMeetingLink: false
            )
        )
    }

    func testNoLinkEventIsEligibleForFullscreenNotificationWhenEnabled() {
        XCTAssertTrue(
            FullscreenNotificationEligibilityPolicy.isEligible(
                hasMeetingLink: false,
                isAllDay: false,
                fullscreenNotificationsEnabled: true,
                includesEventsWithoutMeetingLink: true
            )
        )
    }

    func testNoLinkAllDayEventRemainsIneligibleForFullscreenNotification() {
        XCTAssertFalse(
            FullscreenNotificationEligibilityPolicy.isEligible(
                hasMeetingLink: false,
                isAllDay: true,
                fullscreenNotificationsEnabled: true,
                includesEventsWithoutMeetingLink: true
            )
        )
    }

    func testCleanupExpiredDropsEndedEntries() {
        let processed = [
            EventActionProcessedEvent(id: "ended", lastModifiedDate: nil, eventEndDate: now.addingTimeInterval(-1)),
            EventActionProcessedEvent(id: "active", lastModifiedDate: nil, eventEndDate: now.addingTimeInterval(60))
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

    func testEvaluateFiresAtActionBoundary() {
        let event = eventStartingIn(60)
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision)
    }

    func testEvaluateAllowsRecentlyStartedWhenConfigured() {
        let event = eventStartingIn(-10)
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision)
    }

    func testEvaluateRejectsRecentlyStartedForScriptConfig() {
        let event = eventStartingIn(-10)
        let decision = EventActionPolicy.evaluate(
            event: event, config: scriptLikeConfig, processed: [], now: now
        )
        XCTAssertNil(decision)
    }

    func testEvaluateAllDayEventActiveDuringRange() {
        let allDay = EventActionEvent(
            id: "all-day",
            lastModifiedDate: nil,
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(3600),
            isAllDay: true,
            hasMeetingLink: true
        )
        let decision = EventActionPolicy.evaluate(
            event: allDay, config: fullscreenLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision)
    }

    func testEvaluateSkipsAlreadyProcessedEvent() {
        let event = eventStartingIn(30)
        let processed = [
            EventActionProcessedEvent(
                id: event.id,
                lastModifiedDate: event.lastModifiedDate,
                eventEndDate: event.endDate
            )
        ]
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: processed, now: now
        )
        XCTAssertNil(decision)
    }

    func testEvaluateReprocessesAfterReschedule() {
        let event = eventStartingIn(30)
        let stale = EventActionProcessedEvent(
            id: event.id,
            lastModifiedDate: event.lastModifiedDate?.addingTimeInterval(-3600),
            eventEndDate: event.endDate
        )
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: [stale], now: now
        )
        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.updatedProcessed.count, 1)
        XCTAssertEqual(decision?.updatedProcessed.first?.lastModifiedDate, event.lastModifiedDate)
    }

    func testEvaluateUpdatesProcessedEvenWhenLinkMissing() {
        let event = eventStartingIn(30, withLink: false)
        let decision = EventActionPolicy.evaluate(
            event: event, config: fullscreenLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision)
        XCTAssertFalse(decision?.shouldFireSideEffect ?? true)
        XCTAssertEqual(decision?.updatedProcessed.map(\.id), ["evt-1"])
    }

    func testEvaluateScriptConfigDoesNotFireWithoutLink() {
        let event = eventStartingIn(30, withLink: false)
        let decision = EventActionPolicy.evaluate(
            event: event, config: scriptLikeConfig, processed: [], now: now
        )
        XCTAssertNotNil(decision)
        XCTAssertFalse(decision?.shouldFireSideEffect ?? true)
    }
}
