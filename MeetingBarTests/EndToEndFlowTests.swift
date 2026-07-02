//
//  EndToEndFlowTests.swift
//  MeetingBarTests
//
//  End-to-end tests for the full data flow behind the status bar UI:
//  FakeEventStore → CalendarSync → AppModel → StatusBarMenuState →
//  MenuBuilder/NSMenu, StatusBarPresenter → attributed title, and
//  NotificationScheduler → pending notification requests.
//
//  The NSStatusItem itself is intentionally out of scope: the menu is built
//  through the production `StatusBarItemController.updateMenu()` path and
//  inspected as an `NSMenu`, menu actions are dispatched through the real
//  target/action wiring, and the title is asserted on the
//  `StatusBarPresentation` / `StatusBarTitleRenderer` output that the
//  status bar button would render.
//

import AppKit
import Combine
import Defaults
import SwiftUI
import UserNotifications
import XCTest

@testable import MeetingBar

// MARK: - Harness

/// Wires a real `CalendarSync` + `AppModel` + `NotificationScheduler` +
/// `StatusBarItemController` chain on top of `FakeEventStore`, mirroring
/// `AppEnvironment.live` for calendar and notification flows while recording
/// outward side effects (opening meetings, snoozes, window routing) instead
/// of executing them. Provider changes run through the real `CalendarSync`
/// switch and are recorded as well.
@MainActor
private final class EndToEndHarness {
    let store: FakeEventStore
    let sync: CalendarSync
    let controller: StatusBarItemController
    let notificationSink = FakeNotificationRequestSink()
    let scheduler: NotificationScheduler
    private(set) var model: AppModel!

    private(set) var openedMeetingIDs: [String] = []
    private(set) var snoozedEvents: [(eventID: String, action: NotificationEventTimeAction)] = []
    private(set) var providerChanges: [(provider: EventStoreProvider, signOut: Bool)] = []
    private(set) var openPreferencesCallCount = 0

    convenience init(store: FakeEventStore) {
        self.init(sync: CalendarSync(provider: store, refreshInterval: 0), store: store)
    }

    init(sync: CalendarSync, store: FakeEventStore) {
        self.store = store
        self.sync = sync
        controller = StatusBarItemController()
        scheduler = NotificationScheduler(sink: notificationSink)

        let environment = AppEnvironment(
            eventsPublisher: sync.$events.eraseToAnyPublisher(),
            calendarsPublisher: sync.$calendars
                .map { ($0, sync.repository.activeProviderName) }
                .eraseToAnyPublisher(),
            providerHealthPublisher: sync.$providerHealth.eraseToAnyPublisher(),
            selectedCalendarIDsPublisher: Defaults.publisher(
                .selectedCalendarIDs,
                options: [.initial]
            )
            .map(\.newValue)
            .eraseToAnyPublisher(),
            triggerRefresh: {
                sync.refreshSubject.send()
            },
            reconcileNotifications: { [weak self] events in
                await self?.scheduler.reconcile(events: events, settings: .currentForScheduler)
            },
            changeProvider: { [weak self] provider, signOut in
                guard let self else { return .failed("Harness unavailable") }
                self.providerChanges.append((provider, signOut))
                return await self.sync.changeEventStoreProvider(provider, withSignOut: signOut)
            },
            currentCalendarSnapshot: {
                (sync.calendars, sync.repository.activeProviderName)
            },
            toggleCalendarSelection: { id, selected in
                AppSettings.setCalendarSelection(id: id, selected: selected)
            },
            openMeeting: { [weak self] event in
                self?.openedMeetingIDs.append(event.id)
            },
            dismissEvent: { AppSettings.dismissEvent($0) },
            undismissEvent: { AppSettings.undismissEvent(id: $0) },
            clearDismissedEvents: { AppSettings.clearDismissedEvents() },
            toggleMeetingTitleVisibility: { AppSettings.toggleMeetingTitleVisibility() },
            snoozeEvent: { [weak self] event, action in
                self?.snoozedEvents.append((event.id, action))
            },
            completeOnboarding: { _ in .success },
            openPreferences: { [weak self] in
                self?.openPreferencesCallCount += 1
            },
            resumeOAuthFlow: { _ in },
            clock: .live
        )
        model = AppModel(environment: environment)

        controller.configure(dependencies: StatusBarDependencies(
            appState: { [weak self] in self?.model.state ?? AppState() },
            events: { [weak self] in self?.model.state.events ?? [] },
            send: { [weak self] action in self?.model.send(action) },
            openPreferences: { [weak self] in self?.openPreferencesCallCount += 1 }
        ))
    }

    func stop() {
        NSStatusBar.system.removeStatusItem(controller.statusItem)
        scheduler.stop()
        sync.stop()
    }
}

// MARK: - Shared helpers

@MainActor
class EndToEndFlowTestCase: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    fileprivate let sharedCalendar = MBCalendar(
        title: "E2E Calendar",
        id: "e2e-calendar",
        source: nil,
        email: nil,
        color: .black
    )

    fileprivate func configureDisplayDefaults() {
        Defaults[.selectedCalendarIDs] = [sharedCalendar.id]
        Defaults[.showEventsForPeriod] = .today_n_tomorrow
        Defaults[.eventTitleFormat] = .show
        Defaults[.eventTimeFormat] = .show
        Defaults[.eventTitleIconFormat] = .none
        Defaults[.statusbarEventTitleLength] = statusbarEventTitleLengthLimits.max
        Defaults[.personalEventsAppereance] = .show_active
        Defaults[.nonAllDayEvents] = .show
    }

    fileprivate func makeHarness(
        events: [MBEvent] = [],
        configureStore: ((FakeEventStore) -> Void)? = nil
    ) -> EndToEndHarness {
        let store = FakeEventStore(calendars: [sharedCalendar], events: events)
        configureStore?(store)
        return EndToEndHarness(store: store)
    }

    fileprivate func makeEvent(
        id: String,
        startingIn startOffset: TimeInterval,
        duration: TimeInterval = 1800,
        withLink: Bool = true,
        isAllDay: Bool = false,
        participation: MBEventAttendeeStatus = .accepted,
        calendar: MBCalendar? = nil,
        now: Date = Date()
    ) -> MBEvent {
        var event = MBEvent(
            id: id,
            lastModifiedDate: now,
            title: "Event \(id)",
            status: .confirmed,
            notes: nil,
            location: nil,
            url: withLink ? URL(string: "https://zoom.us/j/5551112222") : nil,
            organizer: nil,
            startDate: now.addingTimeInterval(startOffset),
            endDate: now.addingTimeInterval(startOffset + duration),
            isAllDay: isAllDay,
            recurrent: false,
            calendar: calendar ?? sharedCalendar
        )
        event.participationStatus = participation
        return event
    }

    fileprivate func waitForState(
        of harness: EndToEndHarness,
        timeout: TimeInterval = 3,
        description: String,
        predicate: @escaping (AppState) -> Bool
    ) async {
        let exp = expectation(description: description)
        harness.model.$state
            .filter(predicate)
            .first()
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [exp], timeout: timeout)
    }

    fileprivate func waitUntil(
        _ description: String,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for: \(description)", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Rebuilds the status bar menu through the production
    /// `StatusBarItemController.updateMenu()` path and returns its items.
    fileprivate func rebuildMenu(_ harness: EndToEndHarness) -> [NSMenuItem] {
        harness.controller.updateMenu()
        return harness.controller.statusItemMenu.items
    }

    fileprivate func flatten(_ items: [NSMenuItem]) -> [NSMenuItem] {
        items.flatMap { [$0] + flatten($0.submenu?.items ?? []) }
    }

    fileprivate func menuTitles(_ harness: EndToEndHarness) -> [String] {
        MenuBuilder.plainTitles(of: flatten(rebuildMenu(harness)))
    }

    /// Dispatches the item's action to its target — the same target/action
    /// path AppKit uses when the user clicks the menu item.
    fileprivate func performClick(
        _ item: NSMenuItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let action = item.action, let target = item.target else {
            XCTFail("Menu item '\(item.title)' has no actionable target", file: file, line: line)
            return
        }
        XCTAssertTrue(
            NSApp.sendAction(action, to: target, from: item),
            "Menu action \(action) was not handled",
            file: file,
            line: line
        )
    }

    /// Computes the status bar title exactly like
    /// `StatusBarItemController.updateTitle()` does, stopping short of the
    /// NSStatusItem button it would be rendered into.
    fileprivate func currentTitle(
        _ harness: EndToEndHarness,
        now: Date = Date()
    ) -> (presentation: StatusBarPresentation, rendered: NSAttributedString) {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: harness.model.state.events
                .nextEvent(now: now)
                .map(StatusBarEventPresentationInput.init),
            settings: .current,
            now: now,
            calendar: Calendar.current
        )
        return (presentation, StatusBarTitleRenderer.attributedTitle(for: presentation))
    }
}

// MARK: - Status bar flows

@MainActor
final class StatusBarEndToEndFlowTests: EndToEndFlowTestCase {

    // MARK: Events → menu

    func testEventsFlowFromStoreIntoMenu() async {
        configureDisplayDefaults()
        let now = Date()
        let harness = makeHarness(events: [
            makeEvent(id: "E1", startingIn: 300, now: now),
            makeEvent(id: "E2", startingIn: 3600, now: now)
        ])
        defer { harness.stop() }

        await waitForState(of: harness, description: "events reach AppModel") {
            $0.events.count == 2
        }

        let items = flatten(rebuildMenu(harness))
        let titles = MenuBuilder.plainTitles(of: items)

        XCTAssertTrue(titles.contains { $0.contains("Event E1") })
        XCTAssertTrue(titles.contains { $0.contains("Event E2") })
        XCTAssertTrue(titles.contains { $0.hasPrefix("status_bar_section_today".loco()) })

        let summary = items.first {
            $0.identifier == MenuBuilder.meetingSummaryItemIdentifier
        }
        XCTAssertEqual((summary?.representedObject as? MBEvent)?.id, "E1")
    }

    // MARK: Events → title

    func testStatusBarTitleShowsNextEventEndToEnd() async {
        configureDisplayDefaults()
        let now = Date()
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 300, now: now)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "event reaches AppModel") {
            $0.events.count == 1
        }

        let (presentation, rendered) = currentTitle(harness, now: now)

        XCTAssertEqual(presentation.mode, .nextEvent)
        XCTAssertEqual(presentation.title, "Event E1")
        XCTAssertFalse(presentation.time.isEmpty)
        XCTAssertEqual(presentation.tooltip, "Event E1")
        XCTAssertTrue(rendered.string.hasPrefix("Event E1"))
    }

    // MARK: Menu click → AppModel → side effect

    func testMenuClickJoinsMeetingThroughAppModel() async throws {
        configureDisplayDefaults()
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 300)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "event reaches AppModel") {
            $0.events.count == 1
        }

        let summary = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.identifier == MenuBuilder.meetingSummaryItemIdentifier
        })
        // The summary card joins via a SwiftUI tap closure instead of
        // target/action — trigger it through the hosted view, like a click.
        let hosting = try XCTUnwrap(summary.view as? NSHostingView<MeetingSummaryView>)
        let onJoin = try XCTUnwrap(hosting.rootView.onJoin)
        onJoin()

        XCTAssertEqual(harness.openedMeetingIDs, ["E1"])
    }

    func testDismissFromMenuMovesTitleAndMenuToFollowingEvent() async throws {
        configureDisplayDefaults()
        let now = Date()
        let harness = makeHarness(events: [
            makeEvent(id: "E1", startingIn: 300, now: now),
            makeEvent(id: "E2", startingIn: 3600, now: now)
        ])
        defer { harness.stop() }

        await waitForState(of: harness, description: "events reach AppModel") {
            $0.events.count == 2
        }
        XCTAssertEqual(currentTitle(harness, now: now).presentation.title, "Event E1")

        let dismissItem = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.dismissNextMeetingAction)
        })
        performClick(dismissItem)

        XCTAssertEqual(Defaults[.dismissedEvents].map(\.id), ["E1"])
        XCTAssertEqual(currentTitle(harness, now: now).presentation.title, "Event E2")

        let summary = flatten(rebuildMenu(harness)).first {
            $0.identifier == MenuBuilder.meetingSummaryItemIdentifier
        }
        XCTAssertEqual((summary?.representedObject as? MBEvent)?.id, "E2")
    }

    func testToggleTitleVisibilityFromMenuSwitchesToGenericTitle() async throws {
        configureDisplayDefaults()
        let now = Date()
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 300, now: now)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "event reaches AppModel") {
            $0.events.count == 1
        }
        XCTAssertEqual(currentTitle(harness, now: now).presentation.title, "Event E1")

        let toggleItem = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.toggleMeetingTitleVisibility)
        })
        performClick(toggleItem)

        XCTAssertEqual(Defaults[.eventTitleFormat], .generic)
        XCTAssertEqual(
            currentTitle(harness, now: now).presentation.title,
            "general_meeting".loco()
        )
    }

    // MARK: Refresh loop

    func testManualRefreshFromMenuLoadsNewEventsIntoMenu() async throws {
        configureDisplayDefaults()
        let now = Date()
        let first = makeEvent(id: "E1", startingIn: 300, now: now)
        let harness = makeHarness(events: [first])
        defer { harness.stop() }

        await waitForState(of: harness, description: "initial event reaches AppModel") {
            $0.events.count == 1
        }

        harness.store.stubbedEvents = [first, makeEvent(id: "E2", startingIn: 3600, now: now)]
        // Let CalendarSync's 200ms trigger-throttle window pass so the manual
        // refresh is not coalesced into the initial load.
        try await Task.sleep(nanoseconds: 300_000_000)

        let refreshItem = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.handleManualRefresh)
        })
        performClick(refreshItem)

        await waitForState(of: harness, description: "refreshed events reach AppModel") {
            $0.events.count == 2
        }
        XCTAssertTrue(menuTitles(harness).contains { $0.contains("Event E2") })
    }

    // MARK: Provider health → menu

    func testAuthErrorSurfacesReconnectPathInMenu() async throws {
        configureDisplayDefaults()
        let harness = makeHarness { store in
            store.stubbedEventsError = AuthError.notSignedIn
        }
        defer { harness.stop() }

        await waitForState(of: harness, description: "auth failure reaches AppModel") {
            $0.providerHealth.authRequired
        }

        let items = flatten(rebuildMenu(harness))
        XCTAssertTrue(MenuBuilder.plainTitles(of: items).contains {
            $0.contains("status_bar_control_auth_required".loco())
        })

        let reconnectItem = try XCTUnwrap(items.first {
            $0.action == #selector(StatusBarItemController.reconnectProviderAction)
        })
        performClick(reconnectItem)

        try await waitUntil("provider change dispatched") {
            harness.providerChanges.count == 1
        }
        XCTAssertEqual(harness.providerChanges.first?.provider, .macOSEventKit)
        XCTAssertEqual(harness.providerChanges.first?.signOut, true)
    }

    // MARK: Empty states

    func testNoCalendarsSelectedOffersPreferencesAndIdleTitle() async throws {
        configureDisplayDefaults()
        Defaults[.selectedCalendarIDs] = []
        let harness = makeHarness()
        defer { harness.stop() }

        await waitForState(of: harness, description: "calendars reach AppModel") {
            !$0.calendars.isEmpty
        }

        let preferencesItem = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.openPreferencesAction)
        })
        performClick(preferencesItem)
        XCTAssertEqual(harness.openPreferencesCallCount, 1)

        let (presentation, rendered) = currentTitle(harness)
        XCTAssertEqual(presentation.mode, .idle)
        XCTAssertEqual(presentation.icon, .asset(MenuStyleConstants.appIconName))
        XCTAssertEqual(rendered.string, "")
    }
}

// MARK: - Notification flows

@MainActor
final class NotificationEndToEndFlowTests: EndToEndFlowTestCase {

    func testEventsLoadedScheduleStartAndEndNotifications() async throws {
        configureDisplayDefaults()
        Defaults[.joinEventNotification] = true
        Defaults[.endOfEventNotification] = true
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 1800)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "event reaches AppModel") {
            $0.events.count == 1
        }
        try await waitUntil("start and end notifications scheduled") {
            harness.notificationSink.currentPendingIdentifiers().count == 2
        }

        let requests = harness.notificationSink.currentPendingRequests()
        XCTAssertTrue(requests.allSatisfy {
            $0.identifier.hasPrefix(NotificationScheduler.identifierPrefix)
        })
        XCTAssertTrue(requests.allSatisfy {
            ($0.content.userInfo["eventID"] as? String) == "E1"
        })
        let startRequest = try XCTUnwrap(requests.first {
            $0.identifier.contains("|\(NotificationKind.eventStart.rawValue)|")
        })
        let endRequest = try XCTUnwrap(requests.first {
            $0.identifier.contains("|\(NotificationKind.eventEnd.rawValue)|")
        })
        XCTAssertEqual(startRequest.content.categoryIdentifier, EventNotificationIdentifiers.eventCategory)
        XCTAssertEqual(endRequest.content.categoryIdentifier, "")
        XCTAssertTrue(requests.allSatisfy { $0.trigger is UNTimeIntervalNotificationTrigger })
    }

    func testDismissFromMenuRemovesPendingNotifications() async throws {
        configureDisplayDefaults()
        Defaults[.joinEventNotification] = true
        Defaults[.endOfEventNotification] = true
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 1800)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "event reaches AppModel") {
            $0.events.count == 1
        }
        try await waitUntil("notifications scheduled") {
            harness.notificationSink.currentPendingIdentifiers().count == 2
        }

        let dismissItem = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.dismissNextMeetingAction)
        })
        performClick(dismissItem)

        try await waitUntil("pending notifications removed") {
            harness.notificationSink.currentPendingIdentifiers().isEmpty
        }
    }

    func testScheduledNotificationActionsRouteJoinAndSnoozeToAppModel() async throws {
        configureDisplayDefaults()
        Defaults[.joinEventNotification] = true
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 1800)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "event reaches AppModel") {
            $0.events.count == 1
        }
        try await waitUntil("notification scheduled") {
            !harness.notificationSink.currentPendingIdentifiers().isEmpty
        }

        // Take the notification the scheduler actually produced and parse it
        // exactly like `NotificationCenterDelegate.didReceive` does — the
        // `UNNotificationResponse` wrapper itself cannot be constructed in
        // tests.
        let content = try XCTUnwrap(
            harness.notificationSink.currentPendingRequests().first
        ).content

        let join = try XCTUnwrap(NotificationResponseAction(
            categoryIdentifier: content.categoryIdentifier,
            actionIdentifier: EventNotificationIdentifiers.joinAction,
            eventID: content.userInfo["eventID"] as? String,
            defaultActionIdentifier: UNNotificationDefaultActionIdentifier
        ))
        harness.model.send(.notificationResponse(join))
        XCTAssertEqual(harness.openedMeetingIDs, ["E1"])

        let snooze = try XCTUnwrap(NotificationResponseAction(
            categoryIdentifier: content.categoryIdentifier,
            actionIdentifier: NotificationEventTimeAction.fiveMinuteLater.rawValue,
            eventID: content.userInfo["eventID"] as? String,
            defaultActionIdentifier: UNNotificationDefaultActionIdentifier
        ))
        harness.model.send(.notificationResponse(snooze))
        try await waitUntil("snooze routed to environment") {
            harness.snoozedEvents.count == 1
        }
        XCTAssertEqual(harness.snoozedEvents.first?.eventID, "E1")
        XCTAssertEqual(harness.snoozedEvents.first?.action, .fiveMinuteLater)
    }
}

// MARK: - Provider, filters and calendar selection flows

@MainActor
final class CalendarSettingsEndToEndFlowTests: EndToEndFlowTestCase {

    func testProviderSwitchShowsNewProviderEventsAndRestoresSelections() async throws {
        configureDisplayDefaults()
        let eventKitCalendar = MBCalendar(
            title: "EventKit Cal", id: "ek-cal", source: nil, email: nil, color: .black
        )
        let googleCalendar = MBCalendar(
            title: "Google Cal", id: "g-cal", source: nil, email: nil, color: .black
        )
        Defaults[.eventStoreProvider] = .macOSEventKit
        Defaults[.selectedCalendarIDs] = [eventKitCalendar.id]
        Defaults[.selectedCalendarIDsByProvider] = [
            EventStoreProvider.macOSEventKit.rawValue: [eventKitCalendar.id],
            EventStoreProvider.googleCalendar.rawValue: [googleCalendar.id]
        ]
        Defaults[.selectedCalendarIDsByProviderMigrated] = true

        let eventKitStore = FakeEventStore(
            calendars: [eventKitCalendar],
            events: [makeEvent(id: "EK", startingIn: 300, calendar: eventKitCalendar)]
        )
        let googleStore = FakeEventStore(
            calendars: [googleCalendar],
            events: [makeEvent(id: "G", startingIn: 600, calendar: googleCalendar)]
        )
        let repository = CalendarRepository(providerName: .macOSEventKit) { provider in
            provider == .macOSEventKit ? eventKitStore : googleStore
        }
        let harness = EndToEndHarness(
            sync: CalendarSync(repository: repository, refreshInterval: 0),
            store: eventKitStore
        )
        defer { harness.stop() }

        await waitForState(of: harness, description: "EventKit events reach AppModel") {
            $0.events.map(\.id) == ["EK"]
        }
        XCTAssertTrue(menuTitles(harness).contains { $0.contains("Event EK") })

        // Escape the trigger-throttle window before the switch-driven refresh.
        try await Task.sleep(nanoseconds: 300_000_000)
        harness.model.send(.changeProvider(.googleCalendar, signOut: false))

        await waitForState(of: harness, description: "Google events reach AppModel") {
            $0.activeProvider == .googleCalendar && $0.events.map(\.id) == ["G"]
        }

        let titles = menuTitles(harness)
        XCTAssertTrue(titles.contains { $0.contains("Event G") })
        XCTAssertFalse(titles.contains { $0.contains("Event EK") })
        XCTAssertEqual(currentTitle(harness).presentation.title, "Event G")
        XCTAssertEqual(Defaults[.selectedCalendarIDs], [googleCalendar.id])
        XCTAssertEqual(harness.providerChanges.map(\.provider), [.googleCalendar])
    }

    func testShowEventsPeriodSettingControlsTomorrowSection() async {
        configureDisplayDefaults()
        Defaults[.showEventsForPeriod] = .today
        let now = Date()
        let tomorrowOffset = Calendar.current
            .date(byAdding: .day, value: 1, to: now)!
            .timeIntervalSince(now)
        let harness = makeHarness(events: [
            makeEvent(id: "TODAY", startingIn: 300, now: now),
            makeEvent(id: "TMRW", startingIn: tomorrowOffset, now: now)
        ])
        defer { harness.stop() }

        await waitForState(of: harness, description: "events reach AppModel") {
            $0.events.count == 2
        }

        let todayOnly = menuTitles(harness)
        XCTAssertTrue(todayOnly.contains { $0.contains("Event TODAY") })
        XCTAssertFalse(todayOnly.contains { $0.contains("Event TMRW") })
        XCTAssertFalse(todayOnly.contains {
            $0.hasPrefix("status_bar_section_tomorrow".loco())
        })

        Defaults[.showEventsForPeriod] = .today_n_tomorrow

        let bothDays = menuTitles(harness)
        XCTAssertTrue(bothDays.contains { $0.contains("Event TODAY") })
        XCTAssertTrue(bothDays.contains { $0.contains("Event TMRW") })
        XCTAssertTrue(bothDays.contains {
            $0.hasPrefix("status_bar_section_tomorrow".loco())
        })
    }

    func testDeclinedEventsHiddenBySettingEndToEnd() async {
        configureDisplayDefaults()
        Defaults[.declinedEventsAppereance] = .hide
        let now = Date()
        let harness = makeHarness(events: [
            makeEvent(id: "DECLINED", startingIn: 300, participation: .declined, now: now),
            makeEvent(id: "KEPT", startingIn: 600, now: now)
        ])
        defer { harness.stop() }

        // The declined event is filtered inside CalendarSync before
        // publication, so it must never reach AppModel, menu, or title.
        await waitForState(of: harness, description: "filtered events reach AppModel") {
            $0.events.map(\.id) == ["KEPT"]
        }

        let titles = menuTitles(harness)
        XCTAssertTrue(titles.contains { $0.contains("Event KEPT") })
        XCTAssertFalse(titles.contains { $0.contains("Event DECLINED") })
        XCTAssertEqual(currentTitle(harness, now: now).presentation.title, "Event KEPT")
    }

    func testAllDayEventAppearsInMenuButNotInTitle() async {
        configureDisplayDefaults()
        let now = Date()
        let harness = makeHarness(events: [
            makeEvent(
                id: "ALLDAY", startingIn: 0, duration: 86_400,
                withLink: false, isAllDay: true, now: now
            ),
            makeEvent(id: "TIMED", startingIn: 600, now: now)
        ])
        defer { harness.stop() }

        await waitForState(of: harness, description: "events reach AppModel") {
            $0.events.count == 2
        }

        let titles = menuTitles(harness)
        XCTAssertTrue(titles.contains { $0.contains("Event ALLDAY") })
        XCTAssertTrue(titles.contains { $0.contains("Event TIMED") })
        XCTAssertEqual(currentTitle(harness, now: now).presentation.title, "Event TIMED")
    }

    func testInactivePersonalEventStaysInMenuButNotInTitle() async {
        configureDisplayDefaults()
        Defaults[.personalEventsAppereance] = .show_inactive
        let now = Date()
        // No attendees → a "personal" event.
        let harness = makeHarness(events: [
            makeEvent(id: "PERSONAL", startingIn: 300, now: now)
        ])
        defer { harness.stop() }

        await waitForState(of: harness, description: "event reaches AppModel") {
            $0.events.count == 1
        }

        XCTAssertTrue(menuTitles(harness).contains { $0.contains("Event PERSONAL") })
        XCTAssertEqual(currentTitle(harness, now: now).presentation.mode, .noUpcoming)
    }

    func testNetworkLossKeepsCachedEventsAndShowsStaleWarning() async throws {
        configureDisplayDefaults()
        let now = Date()
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 300, now: now)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "initial refresh succeeds") {
            $0.events.count == 1 && $0.providerHealth.lastSuccessfulRefresh != nil
        }

        harness.store.stubbedError = NSError(domain: "network", code: -1009)
        try await Task.sleep(nanoseconds: 300_000_000)

        let refreshItem = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.handleManualRefresh)
        })
        performClick(refreshItem)

        await waitForState(of: harness, description: "stale health reaches AppModel") {
            $0.providerHealth.isStale && !$0.providerHealth.authRequired
        }
        XCTAssertEqual(harness.model.state.events.map(\.id), ["E1"])

        let items = flatten(rebuildMenu(harness))
        let titles = MenuBuilder.plainTitles(of: items)
        XCTAssertTrue(titles.contains { $0.contains("status_bar_control_stale".loco()) })
        XCTAssertTrue(titles.contains { $0.contains("Event E1") })
        XCTAssertEqual(
            (items.first {
                $0.identifier == MenuBuilder.meetingSummaryItemIdentifier
            }?.representedObject as? MBEvent)?.id,
            "E1"
        )
        XCTAssertEqual(currentTitle(harness, now: now).presentation.title, "Event E1")
    }

    func testSelectingCalendarLoadsItsEventsIntoMenu() async throws {
        configureDisplayDefaults()
        let calendarA = MBCalendar(
            title: "Cal A", id: "cal-a", source: nil, email: nil, color: .black
        )
        let calendarB = MBCalendar(
            title: "Cal B", id: "cal-b", source: nil, email: nil, color: .black
        )
        Defaults[.selectedCalendarIDs] = [calendarA.id]

        let store = FakeEventStore(
            calendars: [calendarA, calendarB],
            events: [
                makeEvent(id: "A", startingIn: 300, calendar: calendarA),
                makeEvent(id: "B", startingIn: 600, calendar: calendarB)
            ]
        )
        store.respectsCalendarFilter = true
        let harness = EndToEndHarness(store: store)
        defer { harness.stop() }

        await waitForState(of: harness, description: "selected calendar's events load") {
            $0.events.map(\.id) == ["A"]
        }
        XCTAssertFalse(menuTitles(harness).contains { $0.contains("Event B") })

        // Escape the trigger-throttle window before the selection-driven refresh.
        try await Task.sleep(nanoseconds: 300_000_000)
        harness.model.toggleCalendarSelection(id: calendarB.id, selected: true)

        await waitForState(of: harness, description: "newly selected calendar's events load") {
            $0.events.map(\.id).sorted() == ["A", "B"]
        }
        let titles = menuTitles(harness)
        XCTAssertTrue(titles.contains { $0.contains("Event A") })
        XCTAssertTrue(titles.contains { $0.contains("Event B") })
    }
}
