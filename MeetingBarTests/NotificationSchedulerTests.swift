//
//  NotificationSchedulerTests.swift
//  MeetingBarTests
//

import Defaults
import UserNotifications
import XCTest

@testable import MeetingBar

@MainActor
final class NotificationSchedulerTests: BaseTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(id: String, startsIn: TimeInterval, duration: TimeInterval = 1800)
        -> MBEvent {
        makeFakeEvent(
            id: id,
            start: now.addingTimeInterval(startsIn),
            end: now.addingTimeInterval(startsIn + duration),
            withLink: true,
            lastModifiedDate: Date(timeIntervalSinceReferenceDate: 700_000_000)
        )
    }

    private func wallClockEvent(
        id: String,
        now: Date,
        startsIn: TimeInterval,
        duration: TimeInterval = 1800,
        withLink: Bool = true,
        lastModifiedDate: Date? = Date(timeIntervalSinceReferenceDate: 700_000_000)
    ) -> MBEvent {
        makeFakeEvent(
            id: id,
            start: now.addingTimeInterval(startsIn),
            end: now.addingTimeInterval(startsIn + duration),
            withLink: withLink,
            lastModifiedDate: lastModifiedDate
        )
    }

    private let allEnabled = NotificationPlanningSettings(
        eventStart: .init(enabled: true, offset: 60),
        eventEnd: .init(enabled: true, offset: 60),
        fullscreen: .disabled,
        autoJoin: .disabled,
        scriptOnStart: .disabled,
        dismissedEventIDs: []
    )

    private func settings(
        startOffset: TimeInterval = 60,
        endOffset: TimeInterval = 60,
        dismissedEventIDs: Set<String> = []
    ) -> NotificationPlanningSettings {
        NotificationPlanningSettings(
            eventStart: .init(enabled: true, offset: startOffset),
            eventEnd: .init(enabled: true, offset: endOffset),
            fullscreen: .disabled,
            autoJoin: .disabled,
            scriptOnStart: .disabled,
            dismissedEventIDs: dismissedEventIDs
        )
    }

    private func fullscreenOnlySettings(
        offset: TimeInterval = 0.25,
        dismissedEventIDs: Set<String> = []
    ) -> NotificationPlanningSettings {
        NotificationPlanningSettings(
            eventStart: .disabled,
            eventEnd: .disabled,
            fullscreen: .init(enabled: true, offset: offset),
            autoJoin: .disabled,
            scriptOnStart: .disabled,
            dismissedEventIDs: dismissedEventIDs
        )
    }

    private func actionOnlySettings(
        kind: NotificationKind,
        offset: TimeInterval = 0.25,
        dismissedEventIDs: Set<String> = []
    ) -> NotificationPlanningSettings {
        NotificationPlanningSettings(
            eventStart: .disabled,
            eventEnd: .disabled,
            fullscreen: kind == .fullscreen ? .init(enabled: true, offset: offset) : .disabled,
            autoJoin: kind == .autoJoin ? .init(enabled: true, offset: offset) : .disabled,
            scriptOnStart: kind == .scriptOnStart
                ? .init(enabled: true, offset: offset) : .disabled,
            dismissedEventIDs: dismissedEventIDs
        )
    }

    private func actionSettings(
        fullscreen: NotificationPlanningSettings.Action = .disabled,
        autoJoin: NotificationPlanningSettings.Action = .disabled,
        scriptOnStart: NotificationPlanningSettings.Action = .disabled,
        dismissedEventIDs: Set<String> = []
    ) -> NotificationPlanningSettings {
        NotificationPlanningSettings(
            eventStart: .disabled,
            eventEnd: .disabled,
            fullscreen: fullscreen,
            autoJoin: autoJoin,
            scriptOnStart: scriptOnStart,
            dismissedEventIDs: dismissedEventIDs
        )
    }

    private func startOnlySettings(offset: TimeInterval = 60, hideMeetingTitle: Bool = false)
        -> NotificationPlanningSettings {
        NotificationPlanningSettings(
            eventStart: .init(enabled: true, offset: offset),
            eventEnd: .disabled,
            fullscreen: .disabled,
            autoJoin: .disabled,
            scriptOnStart: .disabled,
            dismissedEventIDs: [],
            hideMeetingTitle: hideMeetingTitle
        )
    }

    private func waitUntil(timeout: TimeInterval = 1, condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testReconcileSchedulesStartAndEndForFutureEvent() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)

        await scheduler.reconcile(
            events: [event(id: "A", startsIn: 600)], settings: allEnabled, now: now)

        XCTAssertEqual(
            sink.addedIdentifiers.count, 2,
            "one start + one end notification expected for one event")
        XCTAssertTrue(
            sink.addedIdentifiers.allSatisfy {
                $0.hasPrefix(NotificationScheduler.identifierPrefix)
            })
    }

    func testReconcileEmitsNothingWhenAllDisabled() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)

        let allDisabled = NotificationPlanningSettings(
            eventStart: .disabled, eventEnd: .disabled,
            fullscreen: .disabled, autoJoin: .disabled, scriptOnStart: .disabled,
            dismissedEventIDs: []
        )

        await scheduler.reconcile(
            events: [event(id: "A", startsIn: 600)], settings: allDisabled, now: now)
        XCTAssertEqual(sink.addedIdentifiers, [])
    }

    func testReconcileSchedulesForBackToBackEvents() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)

        let first = event(id: "A", startsIn: 600, duration: 1800)
        let second = event(id: "B", startsIn: 2400, duration: 1800)  // starts where A ends

        await scheduler.reconcile(events: [first, second], settings: allEnabled, now: now)

        // Two events × (start + end) = 4 reminders.
        XCTAssertEqual(sink.addedIdentifiers.count, 4)
        let prefix = NotificationScheduler.identifierPrefix
        let containsA = sink.addedIdentifiers.contains(where: { $0.hasPrefix(prefix + "A|") })
        let containsB = sink.addedIdentifiers.contains(where: { $0.hasPrefix(prefix + "B|") })
        XCTAssertTrue(
            containsA && containsB,
            "back-to-back events both planned; legacy single-id scheduler suppressed one of them")
    }

    func testReconcileIsIdempotent() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)
        let evts = [event(id: "A", startsIn: 600)]

        await scheduler.reconcile(events: evts, settings: allEnabled, now: now)
        let countAfterFirst = sink.addedIdentifiers.count

        await scheduler.reconcile(events: evts, settings: allEnabled, now: now)
        XCTAssertEqual(
            sink.addedIdentifiers.count, countAfterFirst,
            "second reconcile with the same plan must not re-add anything")
    }

    func testReconcileRemovesStalePendingNoLongerInPlan() async {
        let stale = UNMutableNotificationContent()
        stale.title = "stale"
        let staleRequest = UNNotificationRequest(
            identifier: NotificationScheduler.identifierPrefix + "evt|111|eventStart|60",
            content: stale,
            trigger: nil
        )
        let sink = FakeNotificationRequestSink(initialPending: [staleRequest])
        let scheduler = NotificationScheduler(sink: sink)

        // No events to plan for → stale should be removed.
        await scheduler.reconcile(events: [], settings: allEnabled, now: now)

        XCTAssertEqual(
            sink.removedBatches.flatMap { $0 },
            [NotificationScheduler.identifierPrefix + "evt|111|eventStart|60"])
        XCTAssertTrue(sink.currentPendingIdentifiers().isEmpty)
    }

    func testReconcileLeavesNonOurPrefixIdentifiersUntouched() async {
        // Snooze flow stores notifications with the legacy "NEXT_EVENT" id.
        let snoozed = UNMutableNotificationContent()
        let snoozeRequest = UNNotificationRequest(
            identifier: "NEXT_EVENT", content: snoozed, trigger: nil
        )
        let sink = FakeNotificationRequestSink(initialPending: [snoozeRequest])
        let scheduler = NotificationScheduler(sink: sink)

        await scheduler.reconcile(events: [], settings: allEnabled, now: now)

        XCTAssertTrue(
            sink.currentPendingIdentifiers().contains("NEXT_EVENT"),
            "scheduler must not touch identifiers it does not own")
    }

    func testReconcileSwapsNotificationOnEventReschedule() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)

        let original = event(id: "A", startsIn: 600)
        await scheduler.reconcile(events: [original], settings: allEnabled, now: now)
        let identifiersAfterFirst = Set(sink.currentPendingIdentifiers())

        // Reschedule: same id, different lastModifiedDate.
        let rescheduled = makeFakeEvent(
            id: "A",
            start: original.startDate,
            end: original.endDate,
            withLink: true,
            lastModifiedDate: Date(timeIntervalSinceReferenceDate: 750_000_000)
        )
        await scheduler.reconcile(events: [rescheduled], settings: allEnabled, now: now)
        let identifiersAfterReschedule = Set(sink.currentPendingIdentifiers())

        XCTAssertNotEqual(
            identifiersAfterFirst, identifiersAfterReschedule,
            "lastModifiedDate change must produce new identities and remove old ones")
        XCTAssertFalse(
            sink.removedBatches.flatMap { $0 }.isEmpty,
            "old identifiers must be removed, not left dangling")
    }

    func testChangingJoinNotificationTimeReplacesPendingStartRequest() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)
        let evt = event(id: "A", startsIn: 600)

        await scheduler.reconcile(events: [evt], settings: settings(startOffset: 60), now: now)
        let firstStartID = sink.currentPendingIdentifiers().first { $0.contains("|eventStart|") }

        await scheduler.reconcile(events: [evt], settings: settings(startOffset: 300), now: now)
        let secondStartID = sink.currentPendingIdentifiers().first { $0.contains("|eventStart|") }

        XCTAssertNotEqual(firstStartID, secondStartID)
        XCTAssertTrue(sink.removedBatches.flatMap { $0 }.contains(firstStartID ?? ""))
        XCTAssertTrue(sink.currentPendingIdentifiers().contains(secondStartID ?? ""))
    }

    func testChangingEndNotificationTimeReplacesPendingEndRequest() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)
        let evt = event(id: "A", startsIn: 600)

        await scheduler.reconcile(events: [evt], settings: settings(endOffset: 60), now: now)
        let firstEndID = sink.currentPendingIdentifiers().first { $0.contains("|eventEnd|") }

        await scheduler.reconcile(events: [evt], settings: settings(endOffset: 300), now: now)
        let secondEndID = sink.currentPendingIdentifiers().first { $0.contains("|eventEnd|") }

        XCTAssertNotEqual(firstEndID, secondEndID)
        XCTAssertTrue(sink.removedBatches.flatMap { $0 }.contains(firstEndID ?? ""))
        XCTAssertTrue(sink.currentPendingIdentifiers().contains(secondEndID ?? ""))
    }

    func testReconcileRemovesPendingRequestsAfterEventIsDismissed() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)
        let evt = event(id: "A", startsIn: 600)

        await scheduler.reconcile(events: [evt], settings: allEnabled, now: now)
        XCTAssertEqual(sink.currentPendingIdentifiers().count, 2)

        await scheduler.reconcile(
            events: [evt],
            settings: settings(dismissedEventIDs: ["A"]),
            now: now
        )

        XCTAssertTrue(sink.currentPendingIdentifiers().isEmpty)
        XCTAssertEqual(sink.removedBatches.flatMap { $0 }.count, 2)
    }

    func testReconcileReplacesPendingRequestWhenContentIsStale() async {
        let evt = event(id: "A", startsIn: 600)
        let settings = startOnlySettings()
        let startPlan =
            NotificationPlanner
            .plan(events: [NotificationPlanningEvent(event: evt)], settings: settings, now: now)
            .first { $0.kind == .eventStart }
        let staleID = NotificationScheduler.identifierPrefix + (startPlan?.identity ?? "")

        let staleContent = UNMutableNotificationContent()
        staleContent.title = "Old title"
        staleContent.body = "Old body"
        let staleRequest = UNNotificationRequest(
            identifier: staleID, content: staleContent, trigger: nil)
        let sink = FakeNotificationRequestSink(initialPending: [staleRequest])
        let scheduler = NotificationScheduler(sink: sink)

        await scheduler.reconcile(events: [evt], settings: settings, now: now)

        let currentRequest = sink.currentPendingRequests().first { $0.identifier == staleID }
        XCTAssertEqual(currentRequest?.content.title, evt.title)
        XCTAssertNotEqual(currentRequest?.content.body, "Old body")
        XCTAssertTrue(sink.removedBatches.flatMap { $0 }.contains(staleID))
        XCTAssertTrue(sink.addedIdentifiers.contains(staleID))
    }

    func testReconcileUpdatesPendingTitleWhenHideMeetingTitleChanges() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)
        let evt = event(id: "A", startsIn: 600)
        let visibleSettings = startOnlySettings(hideMeetingTitle: false)
        let hiddenSettings = startOnlySettings(hideMeetingTitle: true)

        await scheduler.reconcile(events: [evt], settings: visibleSettings, now: now)
        let requestID = sink.currentPendingIdentifiers().first
        XCTAssertEqual(sink.currentPendingRequests().first?.content.title, evt.title)

        await scheduler.reconcile(events: [evt], settings: hiddenSettings, now: now)

        XCTAssertEqual(sink.currentPendingRequests().first?.content.title, "general_meeting".loco())
        XCTAssertTrue(sink.removedBatches.flatMap { $0 }.contains(requestID ?? ""))
    }

    func testBuildRequestUsesInjectedNowForTriggerInterval() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)
        let evt = event(id: "A", startsIn: 600)

        await scheduler.reconcile(
            events: [evt],
            settings: NotificationPlanningSettings(
                eventStart: .init(enabled: true, offset: 60),
                eventEnd: .disabled,
                fullscreen: .disabled,
                autoJoin: .disabled,
                scriptOnStart: .disabled,
                dismissedEventIDs: []
            ),
            now: now
        )

        let trigger =
            sink.currentPendingRequests().first?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertNotNil(trigger)
        XCTAssertEqual(trigger?.timeInterval ?? 0, 540, accuracy: 0.01)
    }

    func testReconcileSkipsEventsAlreadyStarted() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)

        // Event started 30 s ago. eventStart offset 60 s => fires 90 s ago (skipped).
        // eventEnd offset 60 s; event ends in 1770 s => fires in 1710 s (still future → planned).
        await scheduler.reconcile(
            events: [event(id: "A", startsIn: -30, duration: 1800)],
            settings: allEnabled,
            now: now
        )

        XCTAssertEqual(sink.addedIdentifiers.count, 1, "only the eventEnd reminder remains")
        XCTAssertTrue(sink.addedIdentifiers[0].contains("|eventEnd|"))
    }

    func testReconcileSchedulesFullscreenActionTask() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "A", now: scheduledNow, startsIn: 0.35)

        await scheduler.reconcile(
            events: [evt],
            settings: fullscreenOnlySettings(offset: 0.25),
            now: scheduledNow
        )

        await waitUntil { actionSink.actions.count == 1 }

        XCTAssertEqual(actionSink.actions.map(\.kind), [.fullscreen])
        XCTAssertEqual(actionSink.actions.map(\.eventID), ["A"])
        XCTAssertTrue(
            requestSink.addedIdentifiers.isEmpty,
            "fullscreen actions must not create system notification requests")
    }

    func testReconcileDoesNotDuplicateFullscreenActionTask() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "A", now: scheduledNow, startsIn: 0.35)
        let settings = fullscreenOnlySettings(offset: 0.25)

        await scheduler.reconcile(events: [evt], settings: settings, now: scheduledNow)
        await scheduler.reconcile(events: [evt], settings: settings, now: scheduledNow)

        await waitUntil { actionSink.actions.count == 1 }
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(actionSink.actions.map(\.eventID), ["A"])
    }

    func testReconcileCancelsFullscreenActionWhenEventIsDismissed() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "A", now: scheduledNow, startsIn: 0.35)

        await scheduler.reconcile(
            events: [evt],
            settings: fullscreenOnlySettings(offset: 0.25),
            now: scheduledNow
        )
        await scheduler.reconcile(
            events: [evt],
            settings: fullscreenOnlySettings(offset: 0.25, dismissedEventIDs: ["A"]),
            now: scheduledNow
        )

        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertTrue(actionSink.actions.isEmpty)
    }

    func testReconcileCancelsAutoJoinWhenEventIsDismissed() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "A", now: scheduledNow, startsIn: 0.35)

        await scheduler.reconcile(
            events: [evt],
            settings: actionOnlySettings(kind: .autoJoin, offset: 0.25),
            now: scheduledNow
        )
        await scheduler.reconcile(
            events: [evt],
            settings: actionOnlySettings(
                kind: .autoJoin,
                offset: 0.25,
                dismissedEventIDs: ["A"]
            ),
            now: scheduledNow
        )

        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertTrue(actionSink.actions.isEmpty)
    }

    func testFullscreenActionUsesProcessedListForDedup() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let lastModifiedDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let evt = wallClockEvent(
            id: "A",
            now: scheduledNow,
            startsIn: 0.35,
            lastModifiedDate: lastModifiedDate
        )
        Defaults[.processedEventsForFullscreenNotification] = [
            ProcessedEvent(
                id: evt.id,
                lastModifiedDate: lastModifiedDate,
                eventEndDate: evt.endDate
            )
        ]

        await scheduler.reconcile(
            events: [evt],
            settings: fullscreenOnlySettings(offset: 0.25),
            now: scheduledNow
        )

        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertTrue(actionSink.actions.isEmpty)
    }

    func testFullscreenActionDoesNotMarkProcessedWhenActionSinkRejects() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink(shouldPerform: false)
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "A", now: scheduledNow, startsIn: 0.35)

        await scheduler.reconcile(
            events: [evt],
            settings: fullscreenOnlySettings(offset: 0.25),
            now: scheduledNow
        )

        await waitUntil { actionSink.attempts.count == 1 }

        XCTAssertEqual(actionSink.attempts.map(\.eventID), ["A"])
        XCTAssertTrue(actionSink.actions.isEmpty)
        XCTAssertTrue(Defaults[.processedEventsForFullscreenNotification].isEmpty)
    }

    func testFullscreenActionWithoutMeetingLinkMarksProcessedWithoutOpening() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "NoLink", now: scheduledNow, startsIn: 0.35, withLink: false)

        await scheduler.reconcile(
            events: [evt],
            settings: fullscreenOnlySettings(offset: 0.25),
            now: scheduledNow
        )

        await waitUntil {
            Defaults[.processedEventsForFullscreenNotification].contains { $0.id == evt.id }
        }

        XCTAssertTrue(actionSink.attempts.isEmpty)
        XCTAssertTrue(actionSink.actions.isEmpty)
        XCTAssertEqual(Defaults[.processedEventsForFullscreenNotification].map(\.id), [evt.id])
    }

    func testRemovingActionSinkCancelsPendingFullscreenActionTask() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "A", now: scheduledNow, startsIn: 0.8)
        let settings = fullscreenOnlySettings(offset: 0.2)

        await scheduler.reconcile(events: [evt], settings: settings, now: scheduledNow)
        scheduler.setActionSink(nil)
        await scheduler.reconcile(events: [evt], settings: settings, now: scheduledNow)

        try? await Task.sleep(nanoseconds: 750_000_000)

        XCTAssertTrue(actionSink.attempts.isEmpty)
        XCTAssertTrue(actionSink.actions.isEmpty)
    }

    func testStopCancelsPendingActionTasks() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "A", now: scheduledNow, startsIn: 0.8)

        await scheduler.reconcile(
            events: [evt],
            settings: fullscreenOnlySettings(offset: 0.2),
            now: scheduledNow
        )
        scheduler.stop()

        try? await Task.sleep(nanoseconds: 750_000_000)

        XCTAssertTrue(actionSink.attempts.isEmpty)
        XCTAssertTrue(actionSink.actions.isEmpty)
    }

    func testReconcileSchedulesAutoJoinAndScriptActionTasks() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "A", now: scheduledNow, startsIn: 0.35)

        await scheduler.reconcile(
            events: [evt],
            settings: actionSettings(
                autoJoin: .init(enabled: true, offset: 0.25),
                scriptOnStart: .init(enabled: true, offset: 0.25)
            ),
            now: scheduledNow
        )

        await waitUntil { actionSink.actions.count == 2 }

        XCTAssertTrue(actionSink.actions.contains { $0.kind == .autoJoin && $0.eventID == "A" })
        XCTAssertTrue(
            actionSink.actions.contains { $0.kind == .scriptOnStart && $0.eventID == "A" })
        XCTAssertTrue(
            requestSink.addedIdentifiers.isEmpty,
            "in-app actions must not create system notification requests")
    }

    func testBackToBackEventsBothTriggerAutoJoin() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let first = wallClockEvent(id: "A", now: scheduledNow, startsIn: 0.35, duration: 0.2)
        let second = wallClockEvent(id: "B", now: scheduledNow, startsIn: 0.65, duration: 0.2)

        await scheduler.reconcile(
            events: [first, second],
            settings: actionOnlySettings(kind: .autoJoin, offset: 0.25),
            now: scheduledNow
        )

        await waitUntil { actionSink.actions.count == 2 }

        XCTAssertEqual(actionSink.actions.map(\.kind), [.autoJoin, .autoJoin])
        XCTAssertEqual(Set(actionSink.actions.map(\.eventID)), Set(["A", "B"]))
    }

    func testAutoJoinPastDueWithinWindowFiresImmediately() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "A", now: scheduledNow, startsIn: 2)

        await scheduler.reconcile(
            events: [evt],
            settings: actionOnlySettings(kind: .autoJoin, offset: 60),
            now: scheduledNow
        )

        XCTAssertEqual(actionSink.actions.map(\.kind), [.autoJoin])
        XCTAssertEqual(actionSink.actions.map(\.eventID), ["A"])
    }

    func testAllDayEventTriggersAutoJoinWhileActive() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = makeFakeEvent(
            id: "AllDay",
            start: scheduledNow.addingTimeInterval(-3600),
            end: scheduledNow.addingTimeInterval(3600),
            isAllDay: true,
            withLink: true
        )

        await scheduler.reconcile(
            events: [evt],
            settings: actionOnlySettings(kind: .autoJoin, offset: 60),
            now: scheduledNow
        )

        XCTAssertEqual(actionSink.actions.map(\.kind), [.autoJoin])
        XCTAssertEqual(actionSink.actions.map(\.eventID), ["AllDay"])
        XCTAssertEqual(Defaults[.processedEventsForAutoJoin].map(\.id), ["AllDay"])
    }

    func testAutoJoinWithoutMeetingLinkMarksProcessedWithoutOpening() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "NoLink", now: scheduledNow, startsIn: 0.35, withLink: false)

        await scheduler.reconcile(
            events: [evt],
            settings: actionOnlySettings(kind: .autoJoin, offset: 0.25),
            now: scheduledNow
        )

        await waitUntil {
            Defaults[.processedEventsForAutoJoin].contains { $0.id == evt.id }
        }

        XCTAssertTrue(actionSink.attempts.isEmpty)
        XCTAssertTrue(actionSink.actions.isEmpty)
        XCTAssertEqual(Defaults[.processedEventsForAutoJoin].map(\.id), [evt.id])
    }

    func testScriptActionWithoutMeetingLinkRunsAndMarksProcessed() async {
        let requestSink = FakeNotificationRequestSink()
        let actionSink = FakeNotificationActionSink()
        let scheduler = NotificationScheduler(sink: requestSink, actionSink: actionSink)
        let scheduledNow = Date()
        let evt = wallClockEvent(id: "Script", now: scheduledNow, startsIn: 0.35, withLink: false)

        await scheduler.reconcile(
            events: [evt],
            settings: actionOnlySettings(kind: .scriptOnStart, offset: 0.25),
            now: scheduledNow
        )

        await waitUntil { actionSink.actions.count == 1 }

        XCTAssertEqual(actionSink.actions.map(\.kind), [.scriptOnStart])
        XCTAssertEqual(actionSink.actions.map(\.eventID), ["Script"])
        XCTAssertEqual(Defaults[.processedEventsForRunScriptOnEventStart].map(\.id), ["Script"])
    }

    func testCurrentForSchedulerMapsDefaultsForMigratedActions() {
        let dismissed = ProcessedEvent(
            id: "dismissed",
            lastModifiedDate: Date(timeIntervalSinceReferenceDate: 700_000_000),
            eventEndDate: now.addingTimeInterval(3600)
        )
        Defaults[.joinEventNotification] = true
        Defaults[.joinEventNotificationTime] = .threeMinuteBefore
        Defaults[.endOfEventNotification] = false
        Defaults[.endOfEventNotificationTime] = .fiveMinuteBefore
        Defaults[.fullscreenNotification] = true
        Defaults[.fullscreenNotificationTime] = .minuteBefore
        Defaults[.automaticEventJoin] = true
        Defaults[.automaticEventJoinTime] = .threeMinuteBefore
        Defaults[.runEventStartScript] = true
        Defaults[.eventStartScriptTime] = .fiveMinuteBefore
        Defaults[.eventStartScriptLocation] = URL(fileURLWithPath: "/tmp/eventStartScript.scpt")
        Defaults[.dismissedEvents] = [dismissed]

        let settings = NotificationPlanningSettings.currentForScheduler

        XCTAssertEqual(settings.eventStart, .init(enabled: true, offset: 180))
        XCTAssertEqual(settings.eventEnd, .init(enabled: false, offset: 300))
        XCTAssertEqual(settings.fullscreen, .init(enabled: true, offset: 60))
        XCTAssertEqual(settings.autoJoin, .init(enabled: true, offset: 180))
        XCTAssertEqual(settings.scriptOnStart, .init(enabled: true, offset: 300))
        XCTAssertEqual(settings.dismissedEventIDs, Set(["dismissed"]))
    }

    func testCurrentForSchedulerDisablesScriptWhenLocationIsMissing() {
        Defaults[.runEventStartScript] = true
        Defaults[.eventStartScriptLocation] = nil

        let settings = NotificationPlanningSettings.currentForScheduler

        XCTAssertEqual(settings.scriptOnStart, .init(enabled: false, offset: 5))
    }
}
