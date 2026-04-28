//
//  NotificationSchedulerTests.swift
//  MeetingBarTests
//

import XCTest
import UserNotifications

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
