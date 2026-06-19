//
//  NotificationRoutingTests.swift
//  MeetingBarTests
//

import UserNotifications
import XCTest

@testable import MeetingBar

final class NotificationResponseActionTests: XCTestCase {
    private let defaultActionIdentifier = "DEFAULT_ACTION"

    func testParsesJoinDismissAndDefaultActions() {
        XCTAssertEqual(
            response(actionIdentifier: "JOIN_ACTION"),
            .join(eventID: "event")
        )
        XCTAssertEqual(
            response(actionIdentifier: "DISMISS_ACTION"),
            .dismiss(eventID: "event")
        )
        XCTAssertEqual(
            response(actionIdentifier: defaultActionIdentifier),
            .join(eventID: "event")
        )
    }

    func testParsesEverySnoozeAction() {
        let actions: [NotificationEventTimeAction] = [
            .untilStart,
            .fiveMinuteLater,
            .tenMinuteLater,
            .fifteenMinuteLater,
            .thirtyMinuteLater
        ]

        for action in actions {
            XCTAssertEqual(
                response(actionIdentifier: action.rawValue),
                .snooze(eventID: "event", action: action)
            )
        }
    }

    func testRejectsUnsupportedCategoryActionAndMissingEventID() {
        XCTAssertNil(response(categoryIdentifier: "OTHER", actionIdentifier: "JOIN_ACTION"))
        XCTAssertNil(response(actionIdentifier: "OTHER"))
        XCTAssertNil(response(actionIdentifier: "JOIN_ACTION", eventID: nil))
    }

    private func response(
        categoryIdentifier: String = "EVENT",
        actionIdentifier: String,
        eventID: String? = "event"
    ) -> NotificationResponseAction? {
        NotificationResponseAction(
            categoryIdentifier: categoryIdentifier,
            actionIdentifier: actionIdentifier,
            eventID: eventID,
            defaultActionIdentifier: defaultActionIdentifier
        )
    }
}

@MainActor
final class SnoozeServiceTests: BaseTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testFixedSnoozeActionsUseExpectedIntervals() throws {
        let event = makeFakeEvent(
            id: "event",
            start: now.addingTimeInterval(3600),
            end: now.addingTimeInterval(5400)
        )
        let cases: [(NotificationEventTimeAction, TimeInterval)] = [
            (.fiveMinuteLater, 300),
            (.tenMinuteLater, 600),
            (.fifteenMinuteLater, 900),
            (.thirtyMinuteLater, 1800)
        ]

        for (action, expectedInterval) in cases {
            let request = SnoozeNotificationRequestFactory.request(
                event: event,
                interval: action,
                hideMeetingTitle: false,
                now: now
            )
            let trigger = try XCTUnwrap(
                request.trigger as? UNTimeIntervalNotificationTrigger
            )

            XCTAssertEqual(trigger.timeInterval, expectedInterval, accuracy: 0.001)
        }
    }

    func testUntilStartUsesEventStartAndFloorsPastEvents() throws {
        let futureEvent = makeFakeEvent(
            id: "future",
            start: now.addingTimeInterval(900),
            end: now.addingTimeInterval(1800)
        )
        let pastEvent = makeFakeEvent(
            id: "past",
            start: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(1800)
        )

        let futureRequest = SnoozeNotificationRequestFactory.request(
            event: futureEvent,
            interval: .untilStart,
            hideMeetingTitle: false,
            now: now
        )
        let pastRequest = SnoozeNotificationRequestFactory.request(
            event: pastEvent,
            interval: .untilStart,
            hideMeetingTitle: false,
            now: now
        )

        let futureTrigger = try XCTUnwrap(
            futureRequest.trigger as? UNTimeIntervalNotificationTrigger
        )
        let pastTrigger = try XCTUnwrap(
            pastRequest.trigger as? UNTimeIntervalNotificationTrigger
        )
        XCTAssertEqual(futureTrigger.timeInterval, 900, accuracy: 0.001)
        XCTAssertEqual(pastTrigger.timeInterval, 0.5, accuracy: 0.001)
    }

    func testServiceReplacesPendingRequestUsingInjectedDependencies() async throws {
        let existing = UNNotificationRequest(
            identifier: notificationIDs.event_starts,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let sink = FakeNotificationRequestSink(initialPending: [existing])
        let event = makeFakeEvent(
            id: "event",
            start: now.addingTimeInterval(900),
            end: now.addingTimeInterval(1800)
        )
        let service = SnoozeService(
            sink: sink,
            clock: .fixed(now),
            hideMeetingTitle: { true }
        )

        await service.snooze(event: event, action: .tenMinuteLater)

        XCTAssertEqual(sink.removedBatches, [[notificationIDs.event_starts]])
        XCTAssertEqual(sink.addedIdentifiers, [notificationIDs.event_starts])
        let request = try XCTUnwrap(sink.currentPendingRequests().first)
        XCTAssertEqual(request.content.title, "general_meeting".loco())
        XCTAssertEqual(request.content.userInfo["eventID"] as? String, event.id)
    }
}

@MainActor
final class NotificationActionHandlerTests: XCTestCase {
    func testRoutesScheduledActionsToTheirOwners() {
        let event = makeEvent()
        var joinedEventIDs: [String] = []
        var fullscreenEventIDs: [String] = []
        var scriptedEventIDs: [String] = []
        let handler = NotificationActionHandler(
            isScreenLocked: { false },
            send: { action in
                if case .joinMeeting(let eventID) = action {
                    joinedEventIDs.append(eventID)
                }
            },
            showFullscreen: { fullscreenEventIDs.append($0.id) },
            runEventStartScript: { scriptedEventIDs.append($0.id) }
        )

        XCTAssertTrue(handler.performNotificationAction(.autoJoin, event: event))
        XCTAssertTrue(handler.performNotificationAction(.fullscreen, event: event))
        XCTAssertTrue(handler.performNotificationAction(.scriptOnStart, event: event))

        XCTAssertEqual(joinedEventIDs, [event.id])
        XCTAssertEqual(fullscreenEventIDs, [event.id])
        XCTAssertEqual(scriptedEventIDs, [event.id])
    }

    func testSkipsScheduledActionsWhileScreenIsLocked() {
        let event = makeEvent()
        var actionCount = 0
        let handler = NotificationActionHandler(
            isScreenLocked: { true },
            send: { _ in actionCount += 1 },
            showFullscreen: { _ in actionCount += 1 },
            runEventStartScript: { _ in actionCount += 1 }
        )

        XCTAssertFalse(handler.performNotificationAction(.autoJoin, event: event))
        XCTAssertEqual(actionCount, 0)
    }

    func testScriptOnStartRejectsEventWithoutMeetingLink() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "no-link",
            start: now,
            end: now.addingTimeInterval(1800),
            withLink: false
        )
        var scriptedEventIDs: [String] = []
        let handler = NotificationActionHandler(
            isScreenLocked: { false },
            send: { _ in },
            showFullscreen: { _ in },
            runEventStartScript: { scriptedEventIDs.append($0.id) }
        )

        XCTAssertFalse(handler.performNotificationAction(.scriptOnStart, event: event))
        XCTAssertTrue(scriptedEventIDs.isEmpty)
    }

    private func makeEvent() -> MBEvent {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return makeFakeEvent(
            id: "event",
            start: now,
            end: now.addingTimeInterval(1800),
            withLink: true
        )
    }
}
