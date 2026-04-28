//
//  NotificationSchedulerTests.swift
//  MeetingBarTests
//

import XCTest
import UserNotifications
import Defaults

@testable import MeetingBar

/// In-memory `NotificationRequestSink` that records every call so reconcile
/// behaviour can be verified without touching the real notification center.
/// Calls are serialised by the test's `@MainActor` runner; no locking needed.
final class FakeNotificationRequestSink: NotificationRequestSink, @unchecked Sendable {
    private var pending: [UNNotificationRequest] = []
    private(set) var addedIdentifiers: [String] = []
    private(set) var removedBatches: [[String]] = []

    init(initialPending: [UNNotificationRequest] = []) {
        self.pending = initialPending
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        pending
    }

    func add(_ request: UNNotificationRequest) async throws {
        pending.append(request)
        addedIdentifiers.append(request.identifier)
    }

    func removePending(identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
        removedBatches.append(identifiers)
    }

    func currentPendingIdentifiers() -> [String] {
        pending.map(\.identifier)
    }

    func currentPendingRequests() -> [UNNotificationRequest] {
        pending
    }
}

@MainActor
final class NotificationSchedulerTests: BaseTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(id: String, startsIn: TimeInterval, duration: TimeInterval = 1800) -> MBEvent {
        makeFakeEvent(
            id: id,
            start: now.addingTimeInterval(startsIn),
            end: now.addingTimeInterval(startsIn + duration),
            withLink: true,
            lastModifiedDate: Date(timeIntervalSinceReferenceDate: 700_000_000)
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

    private func startOnlySettings(offset: TimeInterval = 60) -> NotificationPlanningSettings {
        NotificationPlanningSettings(
            eventStart: .init(enabled: true, offset: offset),
            eventEnd: .disabled,
            fullscreen: .disabled,
            autoJoin: .disabled,
            scriptOnStart: .disabled,
            dismissedEventIDs: []
        )
    }

    func testReconcileSchedulesStartAndEndForFutureEvent() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)

        await scheduler.reconcile(events: [event(id: "A", startsIn: 600)], settings: allEnabled, now: now)

        XCTAssertEqual(sink.addedIdentifiers.count, 2,
                       "one start + one end notification expected for one event")
        XCTAssertTrue(sink.addedIdentifiers.allSatisfy { $0.hasPrefix(NotificationScheduler.identifierPrefix) })
    }

    func testReconcileEmitsNothingWhenAllDisabled() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)

        let allDisabled = NotificationPlanningSettings(
            eventStart: .disabled, eventEnd: .disabled,
            fullscreen: .disabled, autoJoin: .disabled, scriptOnStart: .disabled,
            dismissedEventIDs: []
        )

        await scheduler.reconcile(events: [event(id: "A", startsIn: 600)], settings: allDisabled, now: now)
        XCTAssertEqual(sink.addedIdentifiers, [])
    }

    func testReconcileSchedulesForBackToBackEvents() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)

        let first = event(id: "A", startsIn: 600, duration: 1800)
        let second = event(id: "B", startsIn: 2400, duration: 1800) // starts where A ends

        await scheduler.reconcile(events: [first, second], settings: allEnabled, now: now)

        // Two events × (start + end) = 4 reminders.
        XCTAssertEqual(sink.addedIdentifiers.count, 4)
        let prefix = NotificationScheduler.identifierPrefix
        let containsA = sink.addedIdentifiers.contains(where: { $0.hasPrefix(prefix + "A|") })
        let containsB = sink.addedIdentifiers.contains(where: { $0.hasPrefix(prefix + "B|") })
        XCTAssertTrue(containsA && containsB,
                      "back-to-back events both planned; legacy single-id scheduler suppressed one of them")
    }

    func testReconcileIsIdempotent() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)
        let evts = [event(id: "A", startsIn: 600)]

        await scheduler.reconcile(events: evts, settings: allEnabled, now: now)
        let countAfterFirst = sink.addedIdentifiers.count

        await scheduler.reconcile(events: evts, settings: allEnabled, now: now)
        XCTAssertEqual(sink.addedIdentifiers.count, countAfterFirst,
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

        XCTAssertEqual(sink.removedBatches.flatMap { $0 },
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

        XCTAssertTrue(sink.currentPendingIdentifiers().contains("NEXT_EVENT"),
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

        XCTAssertNotEqual(identifiersAfterFirst, identifiersAfterReschedule,
                          "lastModifiedDate change must produce new identities and remove old ones")
        XCTAssertFalse(sink.removedBatches.flatMap { $0 }.isEmpty,
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
        let startPlan = NotificationPlanningPolicy
            .plan(events: [evt], settings: settings, now: now)
            .first { $0.kind == .eventStart }
        let staleID = NotificationScheduler.identifierPrefix + (startPlan?.identity ?? "")

        let staleContent = UNMutableNotificationContent()
        staleContent.title = "Old title"
        staleContent.body = "Old body"
        let staleRequest = UNNotificationRequest(identifier: staleID, content: staleContent, trigger: nil)
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
        let settings = startOnlySettings()

        Defaults[.hideMeetingTitle] = false
        await scheduler.reconcile(events: [evt], settings: settings, now: now)
        let requestID = sink.currentPendingIdentifiers().first
        XCTAssertEqual(sink.currentPendingRequests().first?.content.title, evt.title)

        Defaults[.hideMeetingTitle] = true
        await scheduler.reconcile(events: [evt], settings: settings, now: now)

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

        let trigger = sink.currentPendingRequests().first?.trigger as? UNTimeIntervalNotificationTrigger
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
}
