//
//  MenuBuilderTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults
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

        let joinItem = try XCTUnwrap(items.first {
            $0.action == #selector(StatusBarItemController.joinNextMeeting)
        })
        let actions = try XCTUnwrap(items.first {
            $0.title == "status_bar_control_actions".loco()
        }?.submenu?.items)

        XCTAssertEqual(joinItem.title, "status_bar_control_join_next".loco())
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
        XCTAssertTrue(items.contains {
            $0.action == #selector(StatusBarItemController.joinNextMeeting)
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

        XCTAssertNil(items.first {
            $0.action == #selector(StatusBarItemController.joinNextMeeting)
        })
        XCTAssertTrue(items.contains {
            $0.title == "status_bar_control_no_meeting_link".loco()
        })
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
            MenuBuilder.plainTitles(of: items)[0], "Today (\(dateFormatter.string(from: day))):")
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
                "Today (\(dateFormatter.string(from: today))):",
                "00:30 \t 01:00 \t Event S1",
                "02:00 \t 02:15 \t Event S2",
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

        let font =
            item!.attributedTitle?
            .attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(
            font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
            "running event title should be bold")
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

}

@MainActor
final class StatusBarTitleRendererTests: BaseTestCase {

    func test_stackedTitleCentersBothLinesAndUsesCompactFonts() {
        let title = StatusBarTitleRenderer.attributedTitle(
            for: makePresentation(layout: .stacked)
        )

        XCTAssertEqual(title.string, "Weekly sync\nnow")

        let paragraphStyle =
            title.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.alignment, .center)
        XCTAssertEqual(paragraphStyle?.lineHeightMultiple ?? 0, 0.7, accuracy: 0.001)

        let titleFont = title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let timeFont =
            title.attribute(
                .font,
                at: title.length - 1,
                effectiveRange: nil
            ) as? NSFont
        XCTAssertEqual(titleFont?.pointSize ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(timeFont?.pointSize ?? 0, 9, accuracy: 0.001)
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
            compactFallback: false,
            removeDeliveredNotifications: false
        )
    }
}

@MainActor
final class StatusBarItemControllerPresentationTests: BaseTestCase {
    private static let calendarID = "status_bar_test_calendar"

    func test_updateTitleCompactsLongTitleAndShowsFallbackMeetingIcon() throws {
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
        XCTAssertNotNil(button.image)
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
        XCTAssertTrue(button.attributedTitle.string.contains("\n"))

        let paragraphStyle =
            button.attributedTitle.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.alignment, .center)
        XCTAssertEqual(paragraphStyle?.lineHeightMultiple ?? 0, 0.7, accuracy: 0.001)
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
        controller.dismissNextMeetingAction()
        controller.dismiss(event: event)
        let item = NSMenuItem()
        item.representedObject = event
        controller.undismissEvent(sender: item)
        controller.undismissMeetingsActions()
        controller.handleManualRefresh()
        controller.toggleMeetingTitleVisibility()

        XCTAssertEqual(joinedEventIDs, [event.id])
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
