//
//  MenuBuilderTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults
import SwiftUI
import XCTest

@testable import MeetingBar

@MainActor
final class MenuBuilderTests: BaseTestCase {
    private class Dummy: NSObject {}

    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, d MMM"
        formatter.locale = I18N.instance.locale
        return formatter
    }

    func testMenuStateMapsHealthyConnectedProvider() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "next",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: true
        )
        var appState = AppState()
        appState.events = [event]
        appState.selectedCalendarIDs = ["calendar"]
        appState.activeProvider = .googleCalendar
        appState.providerHealth = .success(attempted: now)

        let state = StatusBarMenuState.make(
            from: appState,
            settings: .empty,
            now: now
        )

        XCTAssertEqual(state.nextEvent, event)
        XCTAssertEqual(state.activeProvider, .googleCalendar)
        XCTAssertEqual(state.providerStatus, .connected(lastRefresh: now))
        XCTAssertNil(state.emptyStateReason)
    }

    func testMenuStateMapsGoogleAuthRequired() {
        var appState = AppState()
        appState.activeProvider = .googleCalendar
        appState.providerHealth = ProviderHealth(
            lastErrorDescription: "Reconnect Google Calendar",
            isStale: true,
            authRequired: true
        )

        let state = StatusBarMenuState.make(from: appState, settings: .empty)

        XCTAssertEqual(
            state.providerStatus,
            .authRequired(message: "Reconnect Google Calendar")
        )
        XCTAssertEqual(state.providerWarning, .authRequired)
        XCTAssertEqual(state.emptyStateReason, .authRequired)
    }

    func testMenuStateMapsApplePermissionRequired() {
        var appState = AppState()
        appState.activeProvider = .macOSEventKit
        appState.providerHealth = ProviderHealth(
            lastErrorDescription: "Calendar access denied"
        )

        let state = StatusBarMenuState.make(from: appState, settings: .empty)

        XCTAssertEqual(
            state.providerStatus,
            .permissionRequired(message: "Calendar access denied")
        )
        XCTAssertEqual(state.emptyStateReason, .permissionRequired)
    }

    func testMenuStateMapsNoCalendarsSelected() {
        var appState = AppState()
        appState.providerHealth = .success(attempted: Date())

        let state = StatusBarMenuState.make(from: appState, settings: .empty)

        XCTAssertEqual(state.emptyStateReason, .noCalendarsSelected)
    }

    func testMenuStateMapsNoUpcomingMeetings() {
        var appState = AppState()
        appState.selectedCalendarIDs = ["calendar"]
        appState.providerHealth = .success(attempted: Date())

        let state = StatusBarMenuState.make(from: appState, settings: .empty)

        XCTAssertEqual(state.emptyStateReason, .noUpcomingMeetings)
    }

    func testMenuStateMapsStaleRefreshWithoutHidingKnownEvent() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "cached",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800)
        )
        var appState = AppState()
        appState.events = [event]
        appState.selectedCalendarIDs = ["calendar"]
        appState.providerHealth = ProviderHealth(
            lastSuccessfulRefresh: now.addingTimeInterval(-300),
            lastAttemptedRefresh: now,
            lastErrorDescription: "Network unavailable",
            isStale: true
        )

        let state = StatusBarMenuState.make(
            from: appState,
            settings: .empty,
            now: now
        )

        XCTAssertEqual(
            state.providerStatus,
            .stale(
                lastRefresh: now.addingTimeInterval(-300),
                message: "Network unavailable"
            )
        )
        XCTAssertNil(state.emptyStateReason)
        XCTAssertEqual(state.nextEvent, event)
    }

    func testTimelinePresentationRequiresPreferenceAndTodayEvents() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let todayEvent = makeFakeEvent(
            id: "today",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800)
        )
        let tomorrowEvent = makeFakeEvent(
            id: "tomorrow",
            start: Calendar.current.date(byAdding: .day, value: 1, to: now)!,
            end: Calendar.current.date(byAdding: .day, value: 1, to: now)!
                .addingTimeInterval(1800)
        )
        var settings = AppSettings.empty
        settings.menu.showTimelineInMenu = true
        var appState = AppState()
        appState.events = [todayEvent]

        let enabledWithTodayEvents = StatusBarMenuState.make(
            from: appState,
            settings: settings,
            now: now
        )
        XCTAssertTrue(enabledWithTodayEvents.shouldShowTimeline)

        appState.events = [tomorrowEvent]
        let enabledWithoutTodayEvents = StatusBarMenuState.make(
            from: appState,
            settings: settings,
            now: now
        )
        XCTAssertFalse(enabledWithoutTodayEvents.shouldShowTimeline)

        settings.menu.showTimelineInMenu = false
        appState.events = [todayEvent]
        let disabledWithTodayEvents = StatusBarMenuState.make(
            from: appState,
            settings: settings,
            now: now
        )
        XCTAssertFalse(disabledWithTodayEvents.shouldShowTimeline)
    }

    func testTopSectionPlacesTimelineBeforeMeetingSummary() throws {
        let now = Date()
        let event = makeFakeEvent(
            id: "timeline-next",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: true
        )
        var state = StatusBarMenuState()
        state.todayEvents = [event]
        state.nextEvent = event
        state.showTimeline = true
        state.settings = .empty
        state.settings.statusBar.eventTitleFormat = .generic

        let items = MenuBuilder(target: Dummy(), state: state, now: now)
            .buildTopSection()

        let timelineIndex = try XCTUnwrap(items.firstIndex {
            $0.identifier == MenuBuilder.timelineItemIdentifier
        })
        let summaryIndex = try XCTUnwrap(items.firstIndex {
            $0.identifier == MenuBuilder.meetingSummaryItemIdentifier
        })
        XCTAssertLessThan(timelineIndex, summaryIndex)

        let hosting = try XCTUnwrap(
            items[timelineIndex].view as? NSHostingView<DayRelativeTimelineView>
        )
        XCTAssertTrue(
            hosting.rootView.segments.first { $0.id == event.id }?.isHighlighted ?? false
        )
        XCTAssertEqual(
            hosting.rootView.segments.first { $0.id == event.id }?.title,
            event.title
        )
    }

    func testTopSectionOmitsTimelineWhenDisabled() {
        let now = Date()
        let event = makeFakeEvent(
            id: "timeline-disabled",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: true
        )
        var state = StatusBarMenuState()
        state.todayEvents = [event]
        state.nextEvent = event
        state.showTimeline = false
        state.settings = .empty

        let items = MenuBuilder(target: Dummy(), state: state, now: now)
            .buildTopSection()

        XCTAssertFalse(items.contains {
            $0.identifier == MenuBuilder.timelineItemIdentifier
        })
        XCTAssertEqual(
            items.first?.identifier,
            MenuBuilder.meetingSummaryItemIdentifier
        )
    }

    func testMeetingControlMakesJoinPrimaryForEventWithLink() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let calendarOpenURL = URL(string: "https://calendar.google.com/event?eid=abc")!
        let event = makeFakeEvent(
            id: "joinable",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: true,
            calendarOpenURL: calendarOpenURL
        )
        var state = StatusBarMenuState()
        state.nextEvent = event
        state.settings = .empty

        let items = MenuBuilder(target: Dummy(), state: state, now: now)
            .buildMeetingControlSection()

        let actions = try XCTUnwrap(items.first {
            $0.title == "status_bar_control_actions".loco()
        }?.submenu?.items)

        // Summary card is the primary (first) item and carries the event
        XCTAssertEqual(items.first?.identifier, MenuBuilder.meetingSummaryItemIdentifier)
        XCTAssertEqual((items.first?.representedObject as? MBEvent)?.id, event.id)
        XCTAssertNotNil(items.first?.view)

        // No separate join button — join is triggered by clicking the summary card
        XCTAssertNil(items.first { $0.action == #selector(StatusBarItemController.joinEvent) })

        // Actions submenu still contains link-related and event actions
        XCTAssertNotNil(actions.first {
            $0.action == #selector(StatusBarItemController.copyEventMeetingLink)
        })
        XCTAssertEqual(
            actions.first {
                $0.action == #selector(StatusBarItemController.openEventInCalendar)
            }?.representedObject as? URL,
            calendarOpenURL
        )
        XCTAssertNotNil(actions.first {
            $0.action == #selector(StatusBarItemController.dismissEvent)
        })
    }

    func testJoinActionRoutesTheEventShownInMeetingSummary() throws {
        let now = Date()
        let event = makeFakeEvent(
            id: "summary-join",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: true
        )
        var state = StatusBarMenuState()
        state.nextEvent = event
        state.settings = .empty
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        var joinedEventIDs: [String] = []
        controller.configure(dependencies: StatusBarDependencies(
            send: { action in
                guard case .joinMeeting(let eventID) = action else { return }
                joinedEventIDs.append(eventID)
            }
        ))

        let items = MenuBuilder(target: controller, state: state, now: now)
            .buildMeetingControlSection()
        let summaryItem = try XCTUnwrap(items.first {
            $0.identifier == MenuBuilder.meetingSummaryItemIdentifier
        })

        // Simulate the tap: summary item carries the event, joinEvent reads representedObject
        controller.joinEvent(sender: summaryItem)

        XCTAssertEqual((summaryItem.representedObject as? MBEvent)?.id, event.id)
        XCTAssertEqual(joinedEventIDs, [event.id])
    }

    func testMeetingSummaryDeduplicatesAccountCalendarAndOrganizerValues() {
        let now = Date()
        let duplicateValue = "same@example.com"
        let calendar = MBCalendar(
            title: duplicateValue,
            id: "duplicate-metadata",
            source: duplicateValue,
            email: duplicateValue,
            color: .black
        )
        let event = MBEvent(
            id: "metadata",
            lastModifiedDate: now,
            title: "Metadata sync",
            status: .confirmed,
            notes: nil,
            location: nil,
            url: URL(string: "https://zoom.us/j/5551112222"),
            organizer: MBEventOrganizer(email: duplicateValue, name: duplicateValue),
            startDate: now.addingTimeInterval(300),
            endDate: now.addingTimeInterval(1800),
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )
        var state = StatusBarMenuState()
        state.nextEvent = event
        state.settings = .empty

        let presentation = MenuBuilder(target: Dummy(), state: state, now: now)
            .meetingSummaryPresentation(for: event)

        XCTAssertEqual(
            presentation.metadata.filter { $0 == duplicateValue }.count,
            1
        )
        XCTAssertTrue(presentation.metadata.contains("Zoom"))
        XCTAssertEqual(
            presentation.sectionTitle,
            "status_bar_control_next_meeting".loco()
        )
    }

    func testMeetingSummaryKeepsEventTitleWhenStatusBarUsesGenericTitle() {
        let now = Date()
        let event = makeFakeEvent(
            id: "privacy-title",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: true
        )
        var state = StatusBarMenuState()
        state.settings = .empty
        state.settings.statusBar.eventTitleFormat = .generic

        let presentation = MenuBuilder(target: Dummy(), state: state, now: now)
            .meetingSummaryPresentation(for: event)

        XCTAssertEqual(presentation.eventTitle, event.title)
    }

    func testMeetingControlShowsAuthWarningAlongsideCachedNextEvent() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "cached",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: true
        )
        var appState = AppState()
        appState.events = [event]
        appState.selectedCalendarIDs = ["calendar"]
        appState.activeProvider = .googleCalendar
        appState.providerHealth = ProviderHealth(
            lastSuccessfulRefresh: now.addingTimeInterval(-300),
            lastAttemptedRefresh: now,
            lastErrorDescription: "Reconnect Google Calendar",
            isStale: true,
            authRequired: true
        )
        let state = StatusBarMenuState.make(
            from: appState,
            settings: .empty,
            now: now
        )

        let items = MenuBuilder(target: Dummy(), state: state, now: now)
            .buildMeetingControlSection()

        XCTAssertTrue(items.contains {
            $0.title == "status_bar_control_auth_required".loco()
        })
        XCTAssertTrue(items.contains {
            $0.action == #selector(StatusBarItemController.reconnectProviderAction)
        })
        // Summary card (not a separate join button) shows the cached event
        XCTAssertNotNil(items.first {
            $0.identifier == MenuBuilder.meetingSummaryItemIdentifier
        })
    }

    func testMeetingControlHidesBrokenJoinActionsWithoutLink() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "no-link",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: false,
            calendarOpenURL: nil
        )
        var state = StatusBarMenuState()
        state.nextEvent = event
        state.settings = .empty

        let items = MenuBuilder(target: Dummy(), state: state, now: now)
            .buildMeetingControlSection()
        let actions = try XCTUnwrap(items.first {
            $0.title == "status_bar_control_actions".loco()
        }?.submenu?.items)

        // Summary card is shown but carries no join action
        XCTAssertEqual(items.first?.identifier, MenuBuilder.meetingSummaryItemIdentifier)
        XCTAssertNil(items.first { $0.action == #selector(StatusBarItemController.joinEvent) })

        // Actions submenu omits link-specific items when there is no link
        XCTAssertNil(actions.first {
            $0.action == #selector(StatusBarItemController.copyEventMeetingLink)
        })
        XCTAssertNil(actions.first {
            $0.action == #selector(StatusBarItemController.openEventInCalendar)
        })
    }

    func testMeetingControlAuthRequiredOffersReconnect() {
        var state = StatusBarMenuState()
        state.emptyStateReason = .authRequired

        let items = MenuBuilder(target: Dummy(), state: state)
            .buildMeetingControlSection()

        XCTAssertTrue(items.contains {
            $0.action == #selector(StatusBarItemController.reconnectProviderAction)
        })
    }

    func testMeetingControlNoCalendarsOffersPreferences() {
        var state = StatusBarMenuState()
        state.emptyStateReason = .noCalendarsSelected

        let items = MenuBuilder(target: Dummy(), state: state)
            .buildMeetingControlSection()

        XCTAssertTrue(items.contains {
            $0.action == #selector(StatusBarItemController.openPreferencesAction)
        })
    }

    func testMeetingControlNoUpcomingOffersRefresh() {
        var state = StatusBarMenuState()
        state.emptyStateReason = .noUpcomingMeetings

        let items = MenuBuilder(target: Dummy(), state: state)
            .buildMeetingControlSection()

        XCTAssertTrue(items.contains {
            $0.action == #selector(StatusBarItemController.handleManualRefresh)
        })
    }

    func testDateSectionBuildsExpectedItems() {
        let builder = MenuBuilder(target: Dummy())

        let day = Calendar.current.startOfDay(for: Date())
        let e1 = makeFakeEvent(
            id: "1", start: day.addingTimeInterval(3600),
            end: day.addingTimeInterval(5400))
        let e2 = makeFakeEvent(
            id: "2", start: day.addingTimeInterval(7200),
            end: day.addingTimeInterval(9000))
        let items = builder.buildDateSection(
            date: day,
            title: "Today",
            events: [e1, e2]
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E, d MMM"
        dateFormatter.locale = I18N.instance.locale

        // header + 2 events
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(
            MenuBuilder.plainTitles(of: items)[0], "Today (\(dateFormatter.string(from: day)))")
    }

    func testTodayEmptyStateCanBeVisuallySubduedWhenTomorrowHasEvents() throws {
        let items = MenuBuilder(target: Dummy()).buildDateSection(
            date: Date(),
            title: "Today",
            events: [],
            subdueEmptyState: true
        )
        let emptyItem = try XCTUnwrap(items.last)

        XCTAssertEqual(
            emptyItem.attributedTitle?.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor,
            NSColor.disabledControlTextColor
        )
    }

    func test_joinSectionHasCreateAndJoin() {
        let next = makeFakeEvent(
            id: "J",
            start: Date(), end: Date().addingTimeInterval(60))
        let items = MenuBuilder(target: Dummy())
            .buildJoinSection(nextEvent: next)

        XCTAssertEqual(
            MenuBuilder.plainTitles(of: items)[0],
            "status_bar_section_join_current_meeting".loco())
        XCTAssertTrue(
            items.contains { $0.action == #selector(StatusBarItemController.createMeetingAction) })
    }

    func test_joinSectionOffersAlternateMeetingLinks() {
        let calendar = MBCalendar(
            title: "Test Calendar",
            id: "cal_alt",
            source: nil,
            email: nil,
            color: .black
        )
        let next = MBEvent(
            id: "ALT",
            lastModifiedDate: Date(),
            title: "Event ALT",
            status: .confirmed,
            notes: "Stale: https://us02web.zoom.us/j/99999",
            location: "https://teams.microsoft.com/l/meetup-join/location-link",
            url: URL(string: "https://us02web.zoom.us/j/12345?pwd=abcdef"),
            conferenceURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            organizer: nil,
            startDate: Date().addingTimeInterval(60),
            endDate: Date().addingTimeInterval(600),
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )

        let items = MenuBuilder(target: Dummy())
            .buildJoinSection(nextEvent: next)
        let alternateItem = items.first { $0.title == "status_bar_join_with_other_link".loco() }
        let alternateTitles = alternateItem?.submenu?.items.map(\.title)

        XCTAssertEqual(next.meetingLinkCandidate?.source, .providerConferenceData)
        XCTAssertEqual(
            next.alternateMeetingLinkCandidates.map(\.source), [.eventURL, .location, .notes])
        XCTAssertEqual(
            alternateTitles,
            [
                "Zoom - us02web.zoom.us",
                "Microsoft Teams - teams.microsoft.com",
                "Zoom - us02web.zoom.us"
            ])
        XCTAssertEqual(
            (alternateItem?.submenu?.items.first?.representedObject as? MeetingLinkCandidate)?
                .source,
            .eventURL
        )
    }

    func test_joinSectionWithoutEvent() {
        let items = MenuBuilder(target: Dummy())
            .buildJoinSection(nextEvent: nil)
        XCTAssertEqual(items.count, 2)  // Create meeting and quick actions
        XCTAssertEqual(
            items[0].action,
            #selector(StatusBarItemController.createMeetingAction))
    }

    func test_preferencesSectionContainsExpectedItems() {
        // --- Arrange -----------------------------------------------------------------
        // Force "What's New" to appear
        Defaults[.appVersion] = "5.0.0"
        Defaults[.lastRevisedVersionInChangelog] = "4.2.0"
        Defaults[.isInstalledFromAppStore] = true

        // Force "Rate App" to appear (installation > 14 days ago)
        let distantPast = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        // State must reflect the Defaults overrides above — MenuBuilder no
        // longer reads Defaults directly.
        let state = StatusBarMenuState.make(from: [])
        let builder = MenuBuilder(
            target: Dummy(), state: state, installationDate: distantPast)

        // --- Act ---------------------------------------------------------------------
        let items = builder.buildPreferencesSection()
        let titles = MenuBuilder.plainTitles(of: items)

        // --- Assert ------------------------------------------------------------------
        XCTAssertTrue(
            titles.contains(where: { $0.contains("status_bar_whats_new".loco()) }),
            "Should show “What's New” when appVersion > changelogVersion")

        XCTAssertTrue(
            titles.contains(where: { $0.contains("status_bar_rate_app".loco()) }),
            "Should show “Rate App” button after two weeks")

        XCTAssertEqual(
            items.last?.action,
            #selector(StatusBarItemController.quitAction),
            "Last item must be Quit")
    }

    func testPreferencesSectionShowsRateAppAfterDelayOutsideAppStore() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let distantPast = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        var state = StatusBarMenuState.make(from: [])
        state.isInstalledFromAppStore = false
        let builder = MenuBuilder(
            target: Dummy(),
            state: state,
            installationDate: distantPast,
            now: now
        )

        let titles = MenuBuilder.plainTitles(of: builder.buildPreferencesSection())

        XCTAssertTrue(
            titles.contains(where: { $0.contains("status_bar_rate_app".loco()) }),
            "Rate App should remain visible after the delay outside App Store builds"
        )
    }

    func testPreferencesSectionHidesRateAppBeforeInstallationDelay() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let recentInstallation = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        var state = StatusBarMenuState.make(from: [])
        state.isInstalledFromAppStore = true
        let builder = MenuBuilder(
            target: Dummy(),
            state: state,
            installationDate: recentInstallation,
            now: now
        )

        let titles = MenuBuilder.plainTitles(of: builder.buildPreferencesSection())

        XCTAssertFalse(titles.contains {
            $0.contains("status_bar_rate_app".loco())
        })
    }

    func test_bookmarksInlineWhenCountIsThreeOrLess() {
        // --- Arrange -----------------------------------------------------------------
        Defaults[.bookmarks] = [
            Bookmark(
                name: "Zoom", service: MeetingServices.zoom.rawValue,
                url: URL(string: "https://zoom.us")!),
            Bookmark(
                name: "Meet", service: MeetingServices.meet.rawValue,
                url: URL(string: "https://meet.google.com")!)
        ]

        let builder = MenuBuilder(target: Dummy())

        // --- Act ---------------------------------------------------------------------
        let items = builder.buildBookmarksSection(bookmarks: Defaults[.bookmarks])
        let titles = MenuBuilder.plainTitles(of: items)

        // --- Assert ------------------------------------------------------------------
        XCTAssertEqual(titles.filter { $0 == "Zoom" }.count, 1)
        XCTAssertEqual(titles.filter { $0 == "Meet" }.count, 1)
        // Header must be disabled (inline mode)
        XCTAssertFalse(items[0].isEnabled)
    }

    func test_bookmarksGoToSubmenuWhenCountGreaterThanThree() {
        // --- Arrange -----------------------------------------------------------------
        Defaults[.bookmarks] = (1...4).map {
            Bookmark(
                name: "BM\($0)", service: MeetingServices.url.rawValue,
                url: URL(string: "https://example.com/\($0)")!)
        }

        let builder = MenuBuilder(target: Dummy())

        // --- Act ---------------------------------------------------------------------
        let items = builder.buildBookmarksSection(bookmarks: Defaults[.bookmarks])

        // --- Assert ------------------------------------------------------------------
        let header = items[0]
        XCTAssertNotNil(header.submenu, "Header should have submenu when > 3 bookmarks")
        XCTAssertEqual(header.submenu!.items.count, 4)
        XCTAssertEqual(
            header.submenu!.items[2].action,
            #selector(StatusBarItemController.joinBookmark))
    }

    func test_plainSnapshot() {
        // Anchor on tomorrow's midnight so the constructed events are always
        // strictly in the future relative to wall-clock `now`. Anchoring on
        // today's midnight made the test flaky after 00:30 local time when
        // S1 looked "ongoing" and the menu added a running-icon attachment.
        let today = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        let e1 = makeFakeEvent(
            id: "S1",
            start: today.addingTimeInterval(1800),
            end: today.addingTimeInterval(3600))
        let e2 = makeFakeEvent(
            id: "S2",
            start: today.addingTimeInterval(7200),
            end: today.addingTimeInterval(8100))

        var allItems: [NSMenuItem] = []
        let builder = MenuBuilder(target: Dummy())
        allItems += builder.buildDateSection(
            date: today,
            title: "Today", events: [e1, e2])
        allItems += builder.buildJoinSection(nextEvent: e1)

        // “Snapshot”: порівнюємо plain-titles з еталоном
        let snapshot = MenuBuilder.plainTitles(of: allItems)
        XCTAssertEqual(
            snapshot,
            [
                "Today (\(dateFormatter.string(from: today)))",
                "00:30–01:00\tEvent S1",
                "02:00–02:15\tEvent S2",
                "status_bar_section_join_next_meeting".loco(),
                "status_bar_section_join_create_meeting".loco(),
                "status_bar_quick_actions".loco()
            ])
    }
}

@MainActor
final class MenuBuilderEventItemTests: BaseTestCase {

    // Dummy target that owns selector stubs
    private class Dummy: NSObject {
        @objc func stub() {}
    }

    // MARK: – Helper ----------------------------------------------------------

    /// Build a single `NSMenuItem` for the given event (index 1 of Date-section)
    private func buildItem(event: MBEvent, now: Date = Date()) -> NSMenuItem? {
        // Build state via factory so `Defaults` overrides set by tests are
        // reflected in the menu output (MenuBuilder no longer reads Defaults).
        let state = StatusBarMenuState.make(from: [event])
        let items = MenuBuilder(target: Dummy(), state: state, now: now)
            .buildDateSection(
                date: Date(),
                title: "T",
                events: [event])
        return items.count > 1 ? items[1] : nil  // 0 = header
    }

    // MARK: – Tests -----------------------------------------------------------

    /// Placeholder text when no events
    func test_NoEvents() {
        let dateSection = MenuBuilder(target: Dummy())
            .buildDateSection(date: Date(), title: "T", events: [])
        XCTAssertTrue(dateSection[1].title.contains("status_bar_section_date_nothing".loco("t")))

    }
    /// "Open in Calendar" appears with the event's calendarOpenURL attached.
    func test_openInCalendarUsesCalendarOpenURLWhenPresent() {
        Defaults[.showEventDetails] = true
        let calURL = URL(string: "https://www.google.com/calendar/event?eid=abc")!
        let event = makeFakeEvent(
            id: "G",
            start: Date().addingTimeInterval(600),
            end: Date().addingTimeInterval(1200),
            calendarOpenURL: calURL)

        let subItems = buildItem(event: event)?.submenu?.items ?? []
        let openItem = subItems.first {
            $0.title == "status_bar_submenu_open_in_calendar".loco()
        }
        XCTAssertNotNil(openItem, "Open in Calendar should be present when a URL exists")
        XCTAssertEqual(openItem?.representedObject as? URL, calURL)
    }

    /// No calendarOpenURL (e.g. a Google event without htmlLink) ⇒ no action.
    func test_openInCalendarHiddenWhenNoURL() {
        Defaults[.showEventDetails] = true
        let event = makeFakeEvent(
            id: "NoURL",
            start: Date().addingTimeInterval(600),
            end: Date().addingTimeInterval(1200),
            calendarOpenURL: nil)

        let subItems = buildItem(event: event)?.submenu?.items ?? []
        XCTAssertFalse(
            subItems.contains { $0.title == "status_bar_submenu_open_in_calendar".loco() },
            "Open in Calendar must be hidden when there is no usable URL")
    }

    /// declined + `.hide` ⇒ item should be skipped completely
    func test_declinedEventHiddenWhenAppearanceIsHide() {
        Defaults[.declinedEventsAppereance] = .hide

        var event = makeFakeEvent(
            id: "D",
            start: Date().addingTimeInterval(600),
            end: Date().addingTimeInterval(1200))
        event.participationStatus = .declined

        let item = buildItem(event: event)
        XCTAssertNil(item)
    }

    /// pending + `.show_underlined` ⇒ underline attribute present
    func test_pendingEventUnderlined() {
        Defaults[.showPendingEvents] = .show_underlined

        var event = makeFakeEvent(
            id: "P",
            start: Date().addingTimeInterval(600),
            end: Date().addingTimeInterval(1200))
        event.participationStatus = .pending

        let item = buildItem(event: event)

        let underline =
            item!.attributedTitle?
            .attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertNotNil(
            underline,
            "pending event should be underlined when setting is .show_underlined")
    }

    /// showEventDetails == true ⇒ submenu with title/status exists
    func test_submenuCreatedWhenShowEventDetailsTrue() {
        Defaults[.showEventDetails] = true

        var event = makeFakeEvent(
            id: "DET",
            start: Date().addingTimeInterval(600),
            end: Date().addingTimeInterval(1200))
        // add an attendee so Status section appears
        event.attendees = [
            MBEventAttendee(
                email: nil, name: "Alice",
                status: .accepted,
                optional: false,
                isCurrentUser: false)
        ]

        let item = buildItem(event: event)

        let subItems = item?.submenu?.items ?? []
        XCTAssertNotNil(item?.submenu)
        XCTAssertNotNil(subItems.first?.view)
        XCTAssertTrue(subItems.contains { $0.title.lowercased().contains("status") })
    }

    func test_submenuIsNotCreatedWhenShowEventDetailsFalse() throws {
        let event = makeFakeEvent(
            id: "NO-DETAILS",
            start: Date().addingTimeInterval(600),
            end: Date().addingTimeInterval(1200)
        )

        let item = try XCTUnwrap(buildItem(event: event))

        XCTAssertNil(item.submenu)
        XCTAssertEqual(item.toolTip, event.title)
    }

    func test_eventDetailsPreserveEstablishedFieldsAndActions() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let calendar = MBCalendar(
            title: "Work Calendar",
            id: "work",
            source: "Google",
            email: "person@example.com",
            color: .blue
        )
        let calendarOpenURL = URL(string: "ical://ekevent/FULL-DETAILS")!
        var event = MBEvent(
            id: "FULL-DETAILS",
            lastModifiedDate: now,
            title: "Architecture review",
            status: .confirmed,
            notes: "Agenda and decisions",
            location: "Conference Room 5",
            url: URL(string: "https://zoom.us/j/5551112222"),
            calendarOpenURL: calendarOpenURL,
            organizer: MBEventOrganizer(
                email: "host@example.com",
                name: "Meeting Host"
            ),
            attendees: [
                MBEventAttendee(
                    email: "guest@example.com",
                    name: "Guest",
                    status: .accepted
                )
            ],
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(2400),
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )
        event.participationStatus = .accepted

        var state = StatusBarMenuState()
        state.settings = .empty
        state.settings.menu.showEventDetails = true
        state.hasMultipleSelectedCalendars = true

        let items = MenuBuilder(
            target: Dummy(),
            state: state,
            isFantasticalInstalled: false,
            now: now
        ).buildDateSection(
            date: now,
            title: "Today",
            events: [event]
        )
        let submenuItems = try XCTUnwrap(items.last?.submenu?.items)

        XCTAssertNotNil(submenuItems.first?.view)
        XCTAssertTrue(submenuItems.contains {
            $0.title == "status_bar_submenu_status_title".loco(
                "status_bar_submenu_status_accepted".loco()
            )
        })
        XCTAssertTrue(submenuItems.contains { $0.title.contains("30") })
        XCTAssertTrue(submenuItems.contains {
            $0.title == "status_bar_submenu_calendar_title".loco(calendar.title)
        })
        XCTAssertTrue(submenuItems.contains {
            $0.title == "status_bar_submenu_location_title".loco()
        })
        XCTAssertTrue(submenuItems.contains {
            $0.title == "status_bar_submenu_organizer_title".loco("Meeting Host")
        })
        XCTAssertTrue(submenuItems.contains {
            $0.title == "status_bar_submenu_notes_title".loco()
        })
        XCTAssertTrue(submenuItems.contains {
            $0.title == "status_bar_submenu_attendees_title".loco(1)
        })
        XCTAssertTrue(submenuItems.contains {
            $0.action == #selector(StatusBarItemController.copyEventMeetingLink)
        })
        XCTAssertTrue(submenuItems.contains {
            $0.action == #selector(StatusBarItemController.dismissEvent)
        })
        XCTAssertTrue(submenuItems.contains {
            $0.action == #selector(StatusBarItemController.emailAttendees)
        })
        XCTAssertEqual(
            submenuItems.first {
                $0.action == #selector(StatusBarItemController.openEventInCalendar)
            }?.representedObject as? URL,
            calendarOpenURL
        )
    }

    func test_eventDetailsOfferUndismissForDismissedEvent() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "DISMISSED",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(1200),
            withLink: true
        )
        var state = StatusBarMenuState()
        state.settings = .empty
        state.settings.menu.showEventDetails = true
        state.settings.events.dismissedEvents = [
            ProcessedEvent(id: event.id, eventEndDate: event.endDate)
        ]

        let items = MenuBuilder(target: Dummy(), state: state, now: now)
            .buildDateSection(date: now, title: "Today", events: [event])
        let submenuItems = try XCTUnwrap(items.last?.submenu?.items)

        XCTAssertTrue(submenuItems.contains {
            $0.action == #selector(StatusBarItemController.undismissEvent)
        })
        XCTAssertFalse(submenuItems.contains {
            $0.action == #selector(StatusBarItemController.dismissEvent)
        })
    }

    func test_eventDetailsOfferFantasticalWhenInstalled() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "FANTASTICAL",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(1200)
        )
        var state = StatusBarMenuState()
        state.settings = .empty
        state.settings.menu.showEventDetails = true

        let items = MenuBuilder(
            target: Dummy(),
            state: state,
            isFantasticalInstalled: true,
            now: now
        ).buildDateSection(
            date: now,
            title: "Today",
            events: [event]
        )
        let fantasticalItem = try XCTUnwrap(items.last?.submenu?.items.first {
            $0.action == #selector(StatusBarItemController.openEventInFantastical)
        })

        XCTAssertEqual((fantasticalItem.representedObject as? MBEvent)?.id, event.id)
    }

    func test_eventDetailsUseTextViewsForLongFields() {
        Defaults[.showEventDetails] = true
        let calendar = MBCalendar(
            title: "Test Calendar",
            id: "cal_details",
            source: nil,
            email: nil,
            color: .black
        )
        let event = MBEvent(
            id: "LONG",
            lastModifiedDate: Date(),
            title: String(repeating: "Long event title ", count: 8),
            status: .confirmed,
            notes: String(repeating: "Detailed note with https://example.com/path ", count: 5),
            location: String(repeating: "Very long location ", count: 7),
            url: nil,
            organizer: nil,
            startDate: Date().addingTimeInterval(600),
            endDate: Date().addingTimeInterval(1200),
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )

        let item = buildItem(event: event)
        let subItems = item?.submenu?.items ?? []
        let locationIndex = subItems.firstIndex {
            $0.title == "status_bar_submenu_location_title".loco()
        }
        let notesIndex = subItems.firstIndex { $0.title == "status_bar_submenu_notes_title".loco() }

        XCTAssertNotNil(subItems.first?.view)
        XCTAssertNotNil(locationIndex.flatMap { subItems[$0 + 1].view })
        XCTAssertNotNil(notesIndex.flatMap { subItems[$0 + 1].view })
    }

    func test_eventDetailsActionsKeepSelectorsAndRepresentedObjects() throws {
        Defaults[.showEventDetails] = true
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let calendarOpenURL = URL(string: "ical://ekevent/ACTIONS")!
        let event = makeFakeEvent(
            id: "ACTIONS",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(1200),
            withLink: true,
            calendarOpenURL: calendarOpenURL
        )

        let item = try XCTUnwrap(buildItem(event: event, now: now))
        let subItems = try XCTUnwrap(item.submenu?.items)
        let copyItem = try XCTUnwrap(subItems.first {
            $0.action == #selector(StatusBarItemController.copyEventMeetingLink)
        })
        let dismissItem = try XCTUnwrap(subItems.first {
            $0.action == #selector(StatusBarItemController.dismissEvent)
        })
        let emailItem = try XCTUnwrap(subItems.first {
            $0.action == #selector(StatusBarItemController.emailAttendees)
        })
        let openItem = try XCTUnwrap(subItems.first {
            $0.action == #selector(StatusBarItemController.openEventInCalendar)
        })

        XCTAssertEqual((copyItem.representedObject as? MBEvent)?.id, event.id)
        XCTAssertEqual((dismissItem.representedObject as? MBEvent)?.id, event.id)
        XCTAssertEqual((emailItem.representedObject as? MBEvent)?.id, event.id)
        XCTAssertEqual(openItem.representedObject as? URL, calendarOpenURL)
    }

    func test_eventDetailsRenderAttendeeRoleAndDeclinedStyle() throws {
        Defaults[.showEventDetails] = true
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var event = makeFakeEvent(
            id: "ATTENDEES",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(1200)
        )
        event.attendees = [
            MBEventAttendee(
                email: nil,
                name: "Declined",
                status: .declined,
                optional: true,
                isCurrentUser: false
            )
        ]

        let item = try XCTUnwrap(buildItem(event: event, now: now))
        let attendeeItem = try XCTUnwrap(item.submenu?.items.first {
            $0.title.contains("Declined*")
        })

        XCTAssertNotNil(attendeeItem.attributedTitle?.attribute(
            .strikethroughStyle,
            at: 0,
            effectiveRange: nil
        ))
    }

    /// running event (state == .mixed) ⇒ bold font applied
    func test_runningEventGetsBoldFont() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let runEvent = makeFakeEvent(
            id: "RUN",
            start: now.addingTimeInterval(-300),  // started 5 min ago
            end: now.addingTimeInterval(900)  // ends in 15 min
        )

        let item = buildItem(event: runEvent, now: now)
        XCTAssertEqual(item?.state, .mixed)

        // The time column keeps a regular monospaced-digit font; bold is
        // applied to the event-title range only.
        let attributedTitle = item!.attributedTitle!
        var containsBoldRun = false
        attributedTitle.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: attributedTitle.length)
        ) { value, _, _ in
            if let font = value as? NSFont,
               font.fontDescriptor.symbolicTraits.contains(.bold) {
                containsBoldRun = true
            }
        }
        XCTAssertTrue(containsBoldRun, "running event title should be bold")
    }

    func test_upcomingEventUsesOffStateWithoutRunningIcon() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "UPCOMING",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(1200)
        )

        let item = try XCTUnwrap(buildItem(event: event, now: now))

        XCTAssertEqual(item.state, .off)
        XCTAssertNil(item.offStateImage)
        XCTAssertFalse(item.attributedTitle?.string.contains("\u{fffc}") ?? true)
    }

    /// Calendar color enabled (default): no-link events show a drawn color
    /// dot (unnamed image), linked events get a badged composite. Disabled:
    /// the original named asset images are used.
    func test_eventRowReflectsCalendarColorSetting() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let noLinkEvent = makeFakeEvent(
            id: "NO-LINK-COLOR",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(1200)
        )
        let linkedEvent = makeFakeEvent(
            id: "LINKED-COLOR",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(1200),
            withLink: true
        )

        let dotImage = try XCTUnwrap(buildItem(event: noLinkEvent, now: now)?.image)
        XCTAssertNil(dotImage.name(), "color dot should be a drawn, unnamed image")
        let badgedImage = try XCTUnwrap(buildItem(event: linkedEvent, now: now)?.image)
        XCTAssertNil(badgedImage.name(), "badged service icon should be a drawn, unnamed image")

        Defaults[.showEventCalendarColor] = false
        let placeholder = try XCTUnwrap(buildItem(event: noLinkEvent, now: now)?.image)
        XCTAssertEqual(placeholder.name(), "no_online_session")
        let serviceIcon = try XCTUnwrap(buildItem(event: linkedEvent, now: now)?.image)
        XCTAssertNotNil(serviceIcon.name(), "plain service icon should be the named asset")
    }

    func test_pastEventUsesOnState() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "PAST",
            start: now.addingTimeInterval(-1200),
            end: now.addingTimeInterval(-600)
        )

        let item = try XCTUnwrap(buildItem(event: event, now: now))

        XCTAssertEqual(item.state, .on)
        XCTAssertNil(item.onStateImage)
    }
}

@MainActor
final class MenuBuilderQuickActionsTests: BaseTestCase {

    private class Dummy: NSObject {}

    func test_quickActionsIncludesDismissRemove() {
        let next = makeFakeEvent(
            id: "Q",
            start: Date().addingTimeInterval(30),
            end: Date().addingTimeInterval(900))
        // there is at least one dismissed event -> menu should add “Remove all”
        Defaults[.dismissedEvents] = [ProcessedEvent(id: "123", eventEndDate: Date())]

        // Build state via factory so the dismissedEvents override above is
        // reflected — MenuBuilder no longer reads Defaults directly.
        let state = StatusBarMenuState.make(from: [next])
        let root = MenuBuilder(target: Dummy(), state: state)
            .buildJoinSection(nextEvent: next)

        // last element is quick actions header
        let qa = root.last!
        let titles = MenuBuilder.plainTitles(of: qa.submenu!.items)
        XCTAssertTrue(titles.contains { $0.contains("dismiss") })
        XCTAssertTrue(
            titles.contains { $0.contains("status_bar_menu_remove_all_dismissals".loco()) })
    }

    func testQuickActionsPreserveClipboardRefreshAndTitleVisibility() throws {
        var state = StatusBarMenuState()
        state.settings = .empty
        state.settings.statusBar.eventTitleFormat = .show

        let items = MenuBuilder(target: Dummy(), state: state)
            .buildJoinSection(nextEvent: nil)
        let quickActions = try XCTUnwrap(items.first {
            $0.title == "status_bar_quick_actions".loco()
        }?.submenu?.items)

        XCTAssertTrue(quickActions.contains {
            $0.action == #selector(StatusBarItemController.openLinkFromClipboardAction)
        })
        XCTAssertTrue(quickActions.contains {
            $0.action == #selector(StatusBarItemController.handleManualRefresh)
        })
        XCTAssertTrue(quickActions.contains {
            $0.action == #selector(StatusBarItemController.toggleMeetingTitleVisibility)
        })
    }

    func testQuickActionsOfferShowTitleWhenStatusBarUsesGenericTitle() throws {
        var state = StatusBarMenuState()
        state.settings = .empty
        state.settings.statusBar.eventTitleFormat = .generic

        let items = MenuBuilder(target: Dummy(), state: state)
            .buildJoinSection(nextEvent: nil)
        let quickActions = try XCTUnwrap(items.first {
            $0.title == "status_bar_quick_actions".loco()
        }?.submenu?.items)

        XCTAssertTrue(quickActions.contains {
            $0.title == "status_bar_show_meeting_names".loco()
                && $0.action == #selector(StatusBarItemController.toggleMeetingTitleVisibility)
        })
    }

    func testUtilitySectionKeepsDismissForTopCardEventWithoutDuplicateJoin() throws {
        let event = makeFakeEvent(
            id: "top-card",
            start: Date().addingTimeInterval(300),
            end: Date().addingTimeInterval(1800),
            withLink: true
        )
        let items = MenuBuilder(target: Dummy())
            .buildJoinSection(nextEvent: event, includeJoinAction: false)
        let quickActions = try XCTUnwrap(items.last?.submenu?.items)

        XCTAssertFalse(items.contains {
            $0.action == #selector(StatusBarItemController.joinNextMeeting)
        })
        XCTAssertTrue(quickActions.contains {
            $0.action == #selector(StatusBarItemController.dismissNextMeetingAction)
        })
        XCTAssertTrue(items.contains {
            $0.action == #selector(StatusBarItemController.createMeetingAction)
        })
    }

}

@MainActor
final class StatusBarTitleRendererTests: BaseTestCase {

    func test_stackedLayoutProducesNoAttributedTitle() {
        // The stacked layout is rendered as a self-centered image in
        // renderStatusBar, so attributedTitle(for:) must not emit any text for it.
        let title = StatusBarTitleRenderer.attributedTitle(
            for: makePresentation(layout: .stacked)
        )

        XCTAssertEqual(title.string, "")
    }

    func test_stackedImageIsNonTemplateSizedToMenuBarAndWidensWithIcon() {
        let withoutIcon = StatusBarTitleRenderer.stackedImage(
            title: "Weekly sync", time: "in 5 min", icon: nil, style: .normal
        )

        // Non-template so colored meeting-service icons are preserved.
        XCTAssertFalse(withoutIcon.isTemplate)
        // Centered within the menu-bar height (clamped up for tall glyphs).
        XCTAssertGreaterThanOrEqual(withoutIcon.size.height, NSStatusBar.system.thickness - 0.5)
        XCTAssertGreaterThanOrEqual(withoutIcon.size.width, 1)

        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let withIcon = StatusBarTitleRenderer.stackedImage(
            title: "Weekly sync", time: "in 5 min", icon: icon, style: .normal
        )
        XCTAssertGreaterThan(withIcon.size.width, withoutIcon.size.width)

        // Participation styles (inactive/underlined) still produce a valid,
        // non-template image (they exercise the reused titleAttributes styling).
        for style in [StatusBarTitleStyle.inactive, .underlined] {
            let styled = StatusBarTitleRenderer.stackedImage(
                title: "Weekly sync", time: "in 5 min", icon: nil, style: style
            )
            XCTAssertFalse(styled.isTemplate)
            XCTAssertGreaterThanOrEqual(styled.size.width, 1)
        }
    }

    /// Rasterizes the image and returns the transparent margin above the first
    /// inked row and below the last inked row, so tests can assert the drawn block
    /// is vertically centered rather than merely present.
    private func inkVerticalMargins(of image: NSImage) -> (top: Int, bottom: Int)? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        var firstInk = -1
        var lastInk = -1
        for y in 0 ..< rep.pixelsHigh {
            var rowHasInk = false
            for x in 0 ..< rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                rowHasInk = true
                break
            }
            if rowHasInk {
                if firstInk < 0 { firstInk = y }
                lastInk = y
            }
        }
        guard firstInk >= 0 else { return nil }
        return (top: firstInk, bottom: rep.pixelsHigh - 1 - lastInk)
    }

    func test_stackedImageVerticallyCentersBothLines() {
        let image = StatusBarTitleRenderer.stackedImage(
            title: "Weekly sync", time: "in 5 min", icon: nil, style: .normal
        )
        guard let margins = inkVerticalMargins(of: image) else {
            return XCTFail("stacked image had no visible ink")
        }
        XCTAssertLessThanOrEqual(
            abs(margins.top - margins.bottom), 4,
            "stacked title block should be vertically centered (top \(margins.top) vs bottom \(margins.bottom))"
        )
    }

    func test_stackedImageEmptyTitleStaysCentered() {
        // A blank title must not reserve a phantom line that pushes the lone
        // countdown off center (regression guard for the centering fix).
        let image = StatusBarTitleRenderer.stackedImage(
            title: "", time: "in 5 min", icon: nil, style: .normal
        )
        guard let margins = inkVerticalMargins(of: image) else {
            return XCTFail("stacked image had no visible ink")
        }
        XCTAssertLessThanOrEqual(
            abs(margins.top - margins.bottom), 4,
            "lone countdown line should be vertically centered (top \(margins.top) vs bottom \(margins.bottom))"
        )
    }

    func test_inlineTitleIncludesTimeAndUnderlineStyle() {
        let title = StatusBarTitleRenderer.attributedTitle(
            for: makePresentation(
                layout: .inline(showTime: true),
                titleStyle: .underlined
            )
        )

        XCTAssertEqual(title.string, "Weekly sync now")
        XCTAssertNotNil(title.attribute(.underlineStyle, at: 0, effectiveRange: nil))
    }

    func test_noneLayoutRendersEmptyTitle() {
        let title = StatusBarTitleRenderer.attributedTitle(
            for: makePresentation(layout: .none)
        )

        XCTAssertEqual(title.string, "")
    }

    private func makePresentation(
        layout: StatusBarTitleLayout,
        titleStyle: StatusBarTitleStyle = .normal
    ) -> StatusBarPresentation {
        StatusBarPresentation(
            mode: .nextEvent,
            title: "Weekly sync",
            time: "now",
            tooltip: "Weekly sync",
            icon: .none,
            layout: layout,
            titleStyle: titleStyle,
            removeDeliveredNotifications: false
        )
    }
}

@MainActor
final class StatusBarItemControllerPresentationTests: BaseTestCase {
    private static let calendarID = "status_bar_test_calendar"

    func test_renderStatusBarUsesFallbackImageWhenPresentationIsEmpty() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(makePresentation(mode: .noUpcoming))

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.title, "")
        XCTAssertEqual(button.attributedTitle.string, "")
    }

    func test_renderStatusBarDoesNotAddFallbackWhenTitleIsVisible() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(makePresentation(
            title: "Visible meeting",
            layout: .inline(showTime: false)
        ))

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertNil(button.image)
        XCTAssertEqual(button.attributedTitle.string, "Visible meeting")
    }

    func test_renderStatusBarDoesNotOverrideExistingIcon() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(makePresentation(
            mode: .noUpcoming,
            icon: .asset(MenuStyleConstants.calendarCheckmarkIconName)
        ))

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertEqual(
            button.image?.name(),
            MenuStyleConstants.iconNamed(
                MenuStyleConstants.calendarCheckmarkIconName
            ).name()
        )
    }

    func test_renderStatusBarUsesFallbackForHiddenEventTitleWithoutIcon() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(makePresentation())

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.attributedTitle.string, "")
    }

    func test_updateTitleCompactsLongVisibleTitleWithoutForcingFallbackIcon() throws {
        configureStatusBarDefaults()
        Defaults[.eventTitleIconFormat] = .none
        Defaults[.statusbarEventTitleLength] = statusbarEventTitleLengthLimits.max

        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let longTitle = String(repeating: "Very long meeting title ", count: 5)

        controller.events = [
            makeStatusEvent(
                title: longTitle,
                url: URL(string: "https://zoom.us/j/5551112222")!
            )
        ]
        controller.updateTitle()

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertNil(button.image)
        XCTAssertEqual(button.imagePosition, .imageLeft)
        XCTAssertTrue(button.attributedTitle.string.contains("..."))
        XCTAssertLessThan(button.attributedTitle.string.count, longTitle.count)
        XCTAssertEqual(button.alignment, .center)
        XCTAssertEqual(button.cell?.lineBreakMode, .byTruncatingTail)
    }

    func test_updateTitleClearsStaleAttributedTitleWhenNoUpcomingEventRemains() throws {
        configureStatusBarDefaults()

        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.events = [makeStatusEvent()]
        controller.updateTitle()

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertFalse(button.attributedTitle.string.isEmpty)

        controller.events = []
        controller.updateTitle()

        XCTAssertEqual(button.title, "")
        XCTAssertEqual(button.attributedTitle.string, "")
        XCTAssertNotNil(button.image)
    }

    func test_updateTitleUsesCenteredStackedTimeUnderTitle() throws {
        configureStatusBarDefaults()
        Defaults[.eventTimeFormat] = .show_under_title

        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.events = [makeStatusEvent()]
        controller.updateTitle()

        let button = try XCTUnwrap(controller.statusItem.button)
        // Stacked "time under title" is drawn as a single self-centered image
        // (NSStatusBarButton cannot vertically center a multi-line title), so the
        // button carries no attributedTitle and shows an image-only item. The image
        // is non-template so colored meeting-service icons are preserved; the title
        // + time stay available to VoiceOver via the accessibility label.
        XCTAssertTrue(button.attributedTitle.string.isEmpty)
        XCTAssertEqual(button.title, "")
        let image = try XCTUnwrap(button.image)
        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.toolTip, "Weekly sync")
        let accessibilityLabel = try XCTUnwrap(button.accessibilityLabel())
        XCTAssertTrue(accessibilityLabel.contains("Weekly sync"))
        // Label is "<title>, <time>" — the countdown must be exposed too, not just the title.
        XCTAssertTrue(accessibilityLabel.contains(", "))
    }

    func test_actionsUseInjectedAppActionSender() {
        configureStatusBarDefaults()
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let event = makeStatusEvent()
        var joinedEventIDs: [String] = []
        var dismissedEventIDs: [String] = []
        var undismissedEventIDs: [String] = []
        var didClearDismissals = false
        var didRefresh = false
        var didToggleTitle = false

        controller.configure(dependencies: StatusBarDependencies(
            send: { action in
                switch action {
                case .joinMeeting(let eventID):
                    joinedEventIDs.append(eventID)
                case .dismissMeeting(let eventID):
                    dismissedEventIDs.append(eventID)
                case .undismissMeeting(let eventID):
                    undismissedEventIDs.append(eventID)
                case .clearDismissedMeetings:
                    didClearDismissals = true
                case .refreshCalendars:
                    didRefresh = true
                case .toggleMeetingTitleVisibility:
                    didToggleTitle = true
                default:
                    break
                }
            }
        ))
        controller.events = [event]

        controller.joinNextMeeting()
        let joinItem = NSMenuItem()
        joinItem.representedObject = event
        controller.joinEvent(sender: joinItem)
        controller.dismissNextMeetingAction()
        controller.dismiss(event: event)
        let item = NSMenuItem()
        item.representedObject = event
        controller.undismissEvent(sender: item)
        controller.undismissMeetingsActions()
        controller.handleManualRefresh()
        controller.toggleMeetingTitleVisibility()

        XCTAssertEqual(joinedEventIDs, [event.id, event.id])
        XCTAssertEqual(dismissedEventIDs, [event.id, event.id])
        XCTAssertEqual(undismissedEventIDs, [event.id])
        XCTAssertTrue(didClearDismissals)
        XCTAssertTrue(didRefresh)
        XCTAssertTrue(didToggleTitle)
    }

    func test_windowActionsUseInjectedClosures() {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        var didOpenPreferences = false
        var didOpenChangelog = false
        var didQuit = false

        controller.configure(dependencies: StatusBarDependencies(
            openPreferences: { didOpenPreferences = true },
            openChangelog: { didOpenChangelog = true },
            quit: { didQuit = true }
        ))

        controller.openPreferencesAction()
        controller.openChangelogAction()
        controller.quitAction()

        XCTAssertTrue(didOpenPreferences)
        XCTAssertTrue(didOpenChangelog)
        XCTAssertTrue(didQuit)
    }

    private func configureStatusBarDefaults() {
        Defaults[.selectedCalendarIDs] = [Self.calendarID]
        Defaults[.showEventsForPeriod] = .today_n_tomorrow
        Defaults[.eventTitleFormat] = .show
        Defaults[.eventTimeFormat] = .show
        Defaults[.eventTitleIconFormat] = .none
        Defaults[.statusbarEventTitleLength] = statusbarEventTitleLengthLimits.max
        Defaults[.personalEventsAppereance] = .show_active
        Defaults[.nonAllDayEvents] = .show
    }

    func test_renderStatusBarPreservesProviderIconSize() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        for provider in MeetingProvider.all {
            guard let service = MeetingServices(rawValue: provider.id) else { continue }

            controller.renderStatusBar(makePresentation(icon: .meetingService(service)))

            let button = try XCTUnwrap(controller.statusItem.button)
            let expected = NSSize(width: provider.iconWidth, height: provider.iconHeight)
            XCTAssertEqual(button.image?.size, expected)
            XCTAssertEqual(getIconForMeetingService(service).size, expected)
        }
    }

    private func makePresentation(
        mode: StatusBarTitleMode = .nextEvent,
        title: String = "",
        icon: StatusBarIcon = .none,
        layout: StatusBarTitleLayout = .none
    ) -> StatusBarPresentation {
        StatusBarPresentation(
            mode: mode,
            title: title,
            time: "",
            tooltip: nil,
            icon: icon,
            layout: layout,
            titleStyle: .normal,
            removeDeliveredNotifications: false
        )
    }

    private func makeStatusEvent(
        title: String = "Weekly sync",
        url: URL? = URL(string: "https://zoom.us/j/5551112222")!,
        participationStatus: MBEventAttendeeStatus = .accepted
    ) -> MBEvent {
        let now = Date()
        let calendar = MBCalendar(
            title: "Status Bar Test Calendar",
            id: Self.calendarID,
            source: nil,
            email: nil,
            color: .black
        )
        var event = MBEvent(
            id: UUID().uuidString,
            lastModifiedDate: now,
            title: title,
            status: .confirmed,
            notes: nil,
            location: nil,
            url: url,
            organizer: nil,
            startDate: now.addingTimeInterval(-60),
            endDate: now.addingTimeInterval(3600),
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )
        event.participationStatus = participationStatus
        return event
    }
}
