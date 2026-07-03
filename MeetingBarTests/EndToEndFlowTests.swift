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
    private(set) var openChangelogCallCount = 0

    /// Strong reference to the installed in-app action sink. The scheduler's
    /// runner keeps only a weak reference, so the harness owns it for the test.
    private var actionSink: NotificationActionSink?

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
            openPreferences: { [weak self] in self?.openPreferencesCallCount += 1 },
            openChangelog: { [weak self] in self?.openChangelogCallCount += 1 }
        ))
    }

    /// Installs the real in-app action sink (`NotificationActionHandler`) wired
    /// to this harness's model, holding it strongly (the runner keeps only a
    /// weak reference). Used to exercise the fullscreen / auto-join / script
    /// action path and its screen-lock gating end to end.
    func installActionSink(
        showFullscreen: @escaping (MBEvent) -> Void = { _ in },
        runEventStartScript: @escaping (MBEvent) -> Void = { _ in }
    ) {
        let handler = NotificationActionHandler(
            isScreenLocked: { [weak self] in self?.model.state.screenIsLocked ?? false },
            send: { [weak self] action in self?.model.send(action) },
            showFullscreen: showFullscreen,
            runEventStartScript: runEventStartScript
        )
        actionSink = handler
        scheduler.setActionSink(handler)
    }

    func stop() {
        NSStatusBar.system.removeStatusItem(controller.statusItem)
        scheduler.stop()
        sync.stop()
        actionSink = nil
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

    /// Sorted, de-duplicated event IDs currently backing pending notification
    /// requests — lets a test assert *which* events have notifications, not
    /// just how many.
    fileprivate func scheduledEventIDs(_ harness: EndToEndHarness) -> [String] {
        Set(harness.notificationSink.currentPendingRequests()
            .compactMap { $0.content.userInfo["eventID"] as? String })
            .sorted()
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

    /// Renders the status bar title through the production
    /// `StatusBarItemController.updateTitle()` path and returns the button it
    /// drew into — the real end of the title pipeline, minus the NSStatusItem
    /// presentation which is out of scope. Assert on `attributedTitle.string`
    /// and `image?.name()`.
    fileprivate func renderTitle(_ harness: EndToEndHarness) throws -> NSStatusBarButton {
        harness.controller.updateTitle()
        return try XCTUnwrap(harness.controller.statusItem.button)
    }

    /// Waits until CalendarSync's 200ms trigger-throttle window has cleared —
    /// no fetch has started for >250ms — so the next trigger opens a fresh
    /// window instead of being coalesced into the previous load. Keyed on the
    /// fake store's observable fetch counter rather than a blind fixed sleep,
    /// so it tolerates a slow CI agent where the initial fetch runs long.
    fileprivate func settleRefreshWindow(_ harness: EndToEndHarness) async throws {
        var last = harness.store.fetchCallCount
        var quietSince = Date()
        while Date().timeIntervalSince(quietSince) < 0.25 {
            try await Task.sleep(nanoseconds: 40_000_000)
            let current = harness.store.fetchCallCount
            if current != last {
                last = current
                quietSince = Date()
            }
        }
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

    func testStatusBarTitleShowsNextEventEndToEnd() async throws {
        configureDisplayDefaults()
        let now = Date()
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 300, now: now)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "event reaches AppModel") {
            $0.events.count == 1
        }

        let button = try renderTitle(harness)

        // nextEvent mode with "No icon": the title carries the event name plus
        // a time suffix, no icon, and the tooltip is the full title.
        XCTAssertNil(button.image)
        XCTAssertTrue(button.attributedTitle.string.hasPrefix("Event E1"))
        XCTAssertGreaterThan(button.attributedTitle.string.count, "Event E1".count)
        XCTAssertEqual(button.toolTip, "Event E1")
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
        XCTAssertTrue(try renderTitle(harness).attributedTitle.string.hasPrefix("Event E1"))

        let dismissItem = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.dismissNextMeetingAction)
        })
        performClick(dismissItem)

        XCTAssertEqual(Defaults[.dismissedEvents].map(\.id), ["E1"])
        XCTAssertTrue(try renderTitle(harness).attributedTitle.string.hasPrefix("Event E2"))

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
        XCTAssertTrue(try renderTitle(harness).attributedTitle.string.hasPrefix("Event E1"))

        let toggleItem = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.toggleMeetingTitleVisibility)
        })
        performClick(toggleItem)

        XCTAssertEqual(Defaults[.eventTitleFormat], .generic)
        XCTAssertTrue(
            try renderTitle(harness).attributedTitle.string
                .hasPrefix("general_meeting".loco())
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
        try await settleRefreshWindow(harness)

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

        // Idle mode (no calendars): empty title, app-icon glyph.
        let button = try renderTitle(harness)
        XCTAssertEqual(button.attributedTitle.string, "")
        XCTAssertEqual(
            button.image?.name(),
            MenuStyleConstants.iconNamed(MenuStyleConstants.appIconName).name()
        )
    }

    // MARK: Right-click entry point

    func testRightClickJoinsNextMeetingThroughAppModel() async {
        configureDisplayDefaults()
        let harness = makeHarness(events: [
            makeEvent(id: "E1", startingIn: 300),
            makeEvent(id: "E2", startingIn: 3600)
        ])
        defer { harness.stop() }

        await waitForState(of: harness, description: "events reach AppModel") {
            $0.events.count == 2
        }

        // Right-clicking the status item routes to `joinNextMeeting()`.
        harness.controller.joinNextMeeting()

        XCTAssertEqual(harness.openedMeetingIDs, ["E1"])
    }

    // MARK: Changelog

    func testWhatsNewItemSurfacesAndRoutesToChangelog() async throws {
        configureDisplayDefaults()
        Defaults[.appVersion] = "5.0.0"
        Defaults[.lastRevisedVersionInChangelog] = "4.2.0"
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 300)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "event reaches AppModel") {
            $0.events.count == 1
        }

        let whatsNew = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.openChangelogAction)
        })
        XCTAssertEqual(whatsNew.title, "status_bar_whats_new".loco())

        performClick(whatsNew)
        XCTAssertEqual(harness.openChangelogCallCount, 1)
    }

    // MARK: Lifecycle refresh triggers

    func testWakeAndDayChangeTriggerRefetch() async throws {
        configureDisplayDefaults()
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 300)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "initial event reaches AppModel") {
            $0.events.count == 1
        }

        try await settleRefreshWindow(harness)
        let afterInitial = harness.store.fetchCallCount
        harness.model.handleWake()
        try await waitUntil("wake triggers a refetch") {
            harness.store.fetchCallCount > afterInitial
        }

        try await settleRefreshWindow(harness)
        let afterWake = harness.store.fetchCallCount
        harness.model.handleDayChange()
        try await waitUntil("day change triggers a refetch") {
            harness.store.fetchCallCount > afterWake
        }
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
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy {
            $0.identifier.hasPrefix(NotificationScheduler.identifierPrefix)
        })
        XCTAssertTrue(requests.allSatisfy {
            ($0.content.userInfo["eventID"] as? String) == "E1"
        })
        // Start and end are distinguished by category (which drives the action
        // buttons the user sees), not by the internal identifier encoding: the
        // start notification carries the event category, the end carries none.
        XCTAssertEqual(
            Set(requests.map(\.content.categoryIdentifier)),
            [EventNotificationIdentifiers.eventCategory, ""]
        )
        XCTAssertTrue(requests.allSatisfy { $0.trigger is UNTimeIntervalNotificationTrigger })
    }

    func testDismissFromMenuRemovesOnlyTheDismissedEventsNotifications() async throws {
        configureDisplayDefaults()
        Defaults[.joinEventNotification] = true
        Defaults[.endOfEventNotification] = true
        let harness = makeHarness(events: [
            makeEvent(id: "E1", startingIn: 1800),
            makeEvent(id: "E2", startingIn: 3600)
        ])
        defer { harness.stop() }

        await waitForState(of: harness, description: "events reach AppModel") {
            $0.events.count == 2
        }
        try await waitUntil("notifications scheduled for both events") {
            self.scheduledEventIDs(harness) == ["E1", "E2"]
        }

        // Dismisses the next meeting (E1); E2's notifications must survive.
        let dismissItem = try XCTUnwrap(flatten(rebuildMenu(harness)).first {
            $0.action == #selector(StatusBarItemController.dismissNextMeetingAction)
        })
        performClick(dismissItem)

        try await waitUntil("only the dismissed event's notifications are removed") {
            self.scheduledEventIDs(harness) == ["E2"]
        }
        XCTAssertEqual(Defaults[.dismissedEvents].map(\.id), ["E1"])
    }

    // MARK: In-app actions (auto-join / fullscreen) + screen-lock gating

    func testAutoJoinFiresWhenEventBecomesDue() async throws {
        configureDisplayDefaults()
        Defaults[.automaticEventJoin] = true
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 3)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "due event reaches AppModel") {
            $0.events.count == 1
        }

        // Wire the real action sink only now: the initial reconcile ran with no
        // sink, so the auto-join cannot have fired before we start watching.
        harness.installActionSink()
        harness.model.reconcileNotifications()

        try await waitUntil("auto-join opened the meeting") {
            harness.openedMeetingIDs == ["E1"]
        }
    }

    func testFullscreenNotificationFiresForDueEvent() async throws {
        configureDisplayDefaults()
        Defaults[.fullscreenNotification] = true
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 3)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "due event reaches AppModel") {
            $0.events.count == 1
        }

        var fullscreenEventIDs: [String] = []
        harness.installActionSink(showFullscreen: { fullscreenEventIDs.append($0.id) })
        harness.model.reconcileNotifications()

        try await waitUntil("fullscreen presented for due event") {
            fullscreenEventIDs == ["E1"]
        }
    }

    func testInAppActionSuppressedWhileScreenLockedThenFiresAfterUnlock() async throws {
        configureDisplayDefaults()
        Defaults[.automaticEventJoin] = true
        let harness = makeHarness(events: [makeEvent(id: "E1", startingIn: 3)])
        defer { harness.stop() }

        await waitForState(of: harness, description: "due event reaches AppModel") {
            $0.events.count == 1
        }
        harness.installActionSink()

        harness.model.handleScreenLock()
        harness.model.reconcileNotifications()
        // Negative check: let the reconcile Task run, then confirm the locked
        // screen suppressed the auto-join side effect.
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(harness.openedMeetingIDs.isEmpty)

        harness.model.handleScreenUnlock()
        harness.model.reconcileNotifications()
        try await waitUntil("auto-join fires once the screen is unlocked") {
            harness.openedMeetingIDs == ["E1"]
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
        try await settleRefreshWindow(harness)
        harness.model.send(.changeProvider(.googleCalendar, signOut: false))

        await waitForState(of: harness, description: "Google events reach AppModel") {
            $0.activeProvider == .googleCalendar && $0.events.map(\.id) == ["G"]
        }

        let titles = menuTitles(harness)
        XCTAssertTrue(titles.contains { $0.contains("Event G") })
        XCTAssertFalse(titles.contains { $0.contains("Event EK") })
        XCTAssertTrue(try renderTitle(harness).attributedTitle.string.hasPrefix("Event G"))
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

    func testDeclinedEventsHiddenBySettingEndToEnd() async throws {
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
        XCTAssertTrue(try renderTitle(harness).attributedTitle.string.hasPrefix("Event KEPT"))
    }

    func testAllDayEventAppearsInMenuButNotInTitle() async throws {
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
        XCTAssertTrue(try renderTitle(harness).attributedTitle.string.hasPrefix("Event TIMED"))
    }

    func testInactivePersonalEventStaysInMenuButNotInTitle() async throws {
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

        // The event is listed as a normal day row…
        let items = flatten(rebuildMenu(harness))
        XCTAssertTrue(MenuBuilder.plainTitles(of: items).contains {
            $0.contains("Event PERSONAL")
        })
        // …but is not promoted to the "next meeting" summary card…
        XCTAssertFalse(items.contains {
            $0.identifier == MenuBuilder.meetingSummaryItemIdentifier
        })
        // …and the status bar shows the "done for today" state, not the event:
        // empty title with the calendar-checkmark glyph.
        let button = try renderTitle(harness)
        XCTAssertEqual(button.attributedTitle.string, "")
        XCTAssertEqual(
            button.image?.name(),
            MenuStyleConstants.iconNamed(MenuStyleConstants.calendarCheckmarkIconName).name()
        )
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
        try await settleRefreshWindow(harness)

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
        XCTAssertTrue(try renderTitle(harness).attributedTitle.string.hasPrefix("Event E1"))
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
        try await settleRefreshWindow(harness)
        harness.model.toggleCalendarSelection(id: calendarB.id, selected: true)

        await waitForState(of: harness, description: "newly selected calendar's events load") {
            $0.events.map(\.id).sorted() == ["A", "B"]
        }
        let titles = menuTitles(harness)
        XCTAssertTrue(titles.contains { $0.contains("Event A") })
        XCTAssertTrue(titles.contains { $0.contains("Event B") })
    }
}
