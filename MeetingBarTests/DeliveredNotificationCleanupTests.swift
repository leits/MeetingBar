import Defaults
import XCTest

@testable import MeetingBar

/// AppClock is Sendable; the lock protects mutable time shared with its closure.
private final class CleanupTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date = date.addingTimeInterval(interval)
    }
}

@MainActor
final class DeliveredNotificationCleanupTests: BaseTestCase {
    private enum WaitError: Error { case timeout }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Delivered-notification cleanup did not observe the state change", file: file, line: line)
                throw WaitError.timeout
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func configure(_ harness: AppModelTestHarness) {
        var settings = AppSettings.current.events
        settings.personalEventsAppearance = .show_active
        settings.showEventsForPeriod = .today_n_tomorrow
        settings.ongoingEventVisibility = .hideImmediateAfter
        harness.selectionSettings = EventSelectionSettings(settings)
    }

    func testMinuteTickClearsAfterTimePassesWithoutFetchingOrReplanning() async throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let clock = CleanupTestClock(now)
        let harness = AppModelTestHarness(now: now, clock: AppClock(now: { clock.now() }))
        defer { harness.model.handleWillTerminate() }
        configure(harness)
        harness.joinNotificationsEnabled = true
        let event = makeFakeEvent(
            id: "next", start: now.addingTimeInterval(300), end: now.addingTimeInterval(600)
        )
        _ = harness.model
        harness.publishEvents([event])
        harness.publishSelectedCalendarIDs(["calendar"])
        try await waitUntil {
            harness.model.state.selectedCalendarIDs == ["calendar"] && harness.reconciledEventIDs.count == 1
        }
        XCTAssertEqual(harness.deliveredClearCount, 0)
        let reconcilesBeforeTick = harness.reconciledEventIDs.count

        clock.advance(by: 1200)
        harness.model.handleMinuteTick()
        try await waitUntil { harness.deliveredClearCount > 0 }

        XCTAssertEqual(harness.model.state.events.map(\.id), ["next"])
        XCTAssertEqual(harness.model.state.timeContextRevision, 1)
        XCTAssertEqual(harness.refreshCallCount, 0)
        XCTAssertEqual(harness.reconciledEventIDs.count, reconcilesBeforeTick)
    }

    func testIdleDisabledAndFarFutureEventPreserveDeliveredNotifications() async throws {
        let harness = AppModelTestHarness()
        defer { harness.model.handleWillTerminate() }
        configure(harness)
        harness.joinNotificationsEnabled = true
        harness.model.handleMinuteTick()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(harness.deliveredClearCount, 0, "No selected calendars is idle, not no-upcoming")

        harness.joinNotificationsEnabled = false
        harness.publishSelectedCalendarIDs(["calendar"])
        try await waitUntil { !harness.model.state.selectedCalendarIDs.isEmpty }
        harness.model.handleMinuteTick()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(harness.deliveredClearCount, 0, "Disabled join notifications must not clear")

        let event = makeFakeEvent(
            id: "far", start: harness.fixedNow.addingTimeInterval(3600),
            end: harness.fixedNow.addingTimeInterval(5400)
        )
        harness.model.send(.eventsLoaded([event]))
        harness.joinNotificationsEnabled = true
        Defaults[.showEventMaxTimeUntilEventEnabled] = true
        Defaults[.showEventMaxTimeUntilEventThreshold] = 1
        harness.model.handleMinuteTick()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(harness.deliveredClearCount, 0, "A hidden far-future title is still an upcoming event")
    }

    func testQueuedEmptyStateCannotClearAfterNewerEventsArrive() async throws {
        let harness = AppModelTestHarness()
        defer { harness.model.handleWillTerminate() }
        configure(harness)
        let event = makeFakeEvent(
            id: "next", start: harness.fixedNow.addingTimeInterval(300),
            end: harness.fixedNow.addingTimeInterval(600)
        )
        _ = harness.model
        harness.publishSelectedCalendarIDs(["calendar"])
        try await waitUntil { !harness.model.state.selectedCalendarIDs.isEmpty }
        harness.model.send(.eventsLoaded([]))
        harness.model.send(.eventsLoaded([event]))
        harness.joinNotificationsEnabled = true

        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(harness.deliveredClearCount, 0)
    }

    func testSchedulerCleanupPreservesPendingRequestsAndStopsOnTermination() async {
        let sink = FakeNotificationRequestSink()
        let scheduler = NotificationScheduler(sink: sink)
        let now = Date()
        let event = makeFakeEvent(
            id: "future", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1800)
        )
        Defaults[.joinEventNotification] = true
        await scheduler.reconcile(events: [event], settings: .currentForScheduler, now: now)
        let pending = sink.currentPendingIdentifiers()
        XCTAssertFalse(pending.isEmpty)

        scheduler.clearDeliveredNotifications()
        XCTAssertEqual(sink.deliveredClearCount, 1)
        XCTAssertEqual(sink.currentPendingIdentifiers(), pending)

        scheduler.stop()
        scheduler.clearDeliveredNotifications()
        XCTAssertEqual(sink.deliveredClearCount, 1)
    }
}
