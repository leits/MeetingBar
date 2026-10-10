import Defaults
import XCTest

@testable import MeetingBar

/// Uses production settings observation and wiring, deliberately without a status bar controller.
@MainActor
private final class NotificationSettingsHarness {
    let event: MBEvent
    let store: FakeEventStore
    let sync: CalendarSync
    let sink = FakeNotificationRequestSink()
    let actions = FakeNotificationActionSink()
    let scheduler: NotificationScheduler
    let model: AppModel

    init(startsIn: TimeInterval = 600) {
        let now = Date()
        event = makeFakeEvent(
            id: "settings-flow", start: now.addingTimeInterval(startsIn),
            end: now.addingTimeInterval(startsIn + 1800), withLink: true
        )
        Defaults[.selectedCalendarIDs] = [event.calendar.id]
        Defaults[.personalEventsAppereance] = .show_active
        Defaults[.showEventsForPeriod] = .today_n_tomorrow
        store = FakeEventStore(calendars: [event.calendar], events: [event])
        sync = CalendarSync(provider: store, refreshInterval: 0)
        scheduler = NotificationScheduler(sink: sink, actionSink: actions)
        model = AppModel(environment: .live(
            calendarSync: sync, notificationScheduler: scheduler,
            snoozeService: SnoozeService(sink: sink)
        ))
    }

    func stop() {
        model.handleWillTerminate()
        scheduler.stop()
        sync.stop()
    }
}

@MainActor
final class NotificationSettingsFlowTests: BaseTestCase {
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Settings did not propagate through AppModel and NotificationScheduler")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testSettingsReplaceAndDisablePendingRequestsWithoutStatusBarOrRefresh() async throws {
        Defaults[.joinEventNotification] = true
        Defaults[.joinEventNotificationTime] = .minuteBefore
        Defaults[.endOfEventNotification] = false
        let harness = NotificationSettingsHarness()
        defer { harness.stop() }
        try await waitUntil { harness.sink.currentPendingRequests().count == 1 }
        let originalID = try XCTUnwrap(harness.sink.currentPendingIdentifiers().first)
        let fetchCount = harness.store.fetchCallCount

        Defaults[.joinEventNotificationTime] = .threeMinuteBefore
        try await waitUntil {
            let ids = harness.sink.currentPendingIdentifiers()
            return ids.count == 1 && !ids.contains(originalID)
        }

        Defaults[.eventTitleFormat] = .generic
        try await waitUntil {
            harness.sink.currentPendingRequests().first?.content.title == "general_meeting".loco()
        }

        Defaults[.joinEventNotification] = false
        try await waitUntil { harness.sink.currentPendingRequests().isEmpty }
        Defaults[.joinEventNotification] = true
        Defaults[.joinEventNotificationTime] = .fiveMinuteBefore
        Defaults[.joinEventNotification] = false
        Defaults[.joinEventNotification] = true
        try await waitUntil {
            let requests = harness.sink.currentPendingRequests()
            return requests.count == 1 && requests[0].content.body == "notifications_event_start_five_minutes_body".loco()
        }
        XCTAssertEqual(harness.store.fetchCallCount, fetchCount)
    }

    func testDismissAndRestoreFromNonMenuActionsAutomaticallyReconcile() async throws {
        Defaults[.joinEventNotification] = true
        Defaults[.endOfEventNotification] = false
        let harness = NotificationSettingsHarness()
        defer { harness.stop() }
        try await waitUntil { harness.sink.currentPendingRequests().count == 1 }

        harness.model.send(.notificationResponse(.dismiss(eventID: harness.event.id)))
        try await waitUntil { harness.sink.currentPendingRequests().isEmpty }
        XCTAssertNil(harness.model.nextEvent())

        harness.model.send(.undismissMeeting(eventID: harness.event.id))
        try await waitUntil { harness.sink.currentPendingRequests().count == 1 }
        harness.model.send(.dismissNearestMeeting)
        try await waitUntil { harness.sink.currentPendingRequests().isEmpty }
        harness.model.send(.clearDismissedMeetings)
        try await waitUntil { harness.sink.currentPendingRequests().count == 1 }
        XCTAssertEqual(harness.model.nextEvent()?.id, harness.event.id)
    }

    func testDisablingActionsCancelsAlreadyScheduledWorkWithoutStatusBar() async throws {
        Defaults[.joinEventNotification] = true
        Defaults[.joinEventNotificationTime] = .atStart
        Defaults[.endOfEventNotification] = false
        Defaults[.fullscreenNotification] = true
        Defaults[.fullscreenNotificationTime] = .atStart
        Defaults[.automaticEventJoin] = true
        Defaults[.automaticEventJoinTime] = .atStart
        Defaults[.runEventStartScript] = true
        Defaults[.eventStartScriptTime] = .atStart
        Defaults[.eventStartScriptLocation] = URL(fileURLWithPath: "/tmp/meetingbar-settings-test.scpt")
        let harness = NotificationSettingsHarness(startsIn: 2)
        defer { harness.stop() }
        // A system request is added after the same reconcile schedules the in-app tasks.
        try await waitUntil { harness.sink.currentPendingRequests().count == 1 }

        Defaults[.fullscreenNotification] = false
        Defaults[.automaticEventJoin] = false
        Defaults[.eventStartScriptLocation] = nil
        Defaults[.joinEventNotification] = false
        try await waitUntil { harness.sink.currentPendingRequests().isEmpty }
        let delay = max(harness.event.startDate.timeIntervalSinceNow + 0.2, 0)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        XCTAssertTrue(harness.actions.attempts.isEmpty)
    }

    func testLanguageUpdatesNotificationContentWithoutStatusBar() async throws {
        let oldLanguage = Defaults[.preferredLanguage]
        defer { I18N.instance.changeLanguage(to: oldLanguage) }
        Defaults[.preferredLanguage] = .english
        Defaults[.joinEventNotification] = true
        Defaults[.joinEventNotificationTime] = .minuteBefore
        Defaults[.endOfEventNotification] = false
        let harness = NotificationSettingsHarness()
        defer { harness.stop() }
        try await waitUntil { harness.sink.currentPendingRequests().count == 1 }
        let englishBody = try XCTUnwrap(harness.sink.currentPendingRequests().first?.content.body)

        Defaults[.preferredLanguage] = .french
        try await waitUntil {
            let body = harness.sink.currentPendingRequests().first?.content.body
            return I18N.instance.locale.identifier == "fr" && body != englishBody
                && body == "notifications_event_start_one_minute_body".loco()
        }
    }
}
