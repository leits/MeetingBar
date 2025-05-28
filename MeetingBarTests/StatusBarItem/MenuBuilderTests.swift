//
//  MenuBuilderTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import XCTest
import Defaults
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

    func testDateSectionBuildsExpectedItems() {
        let builder = MenuBuilder(target: Dummy())

        let day = Calendar.current.startOfDay(for: Date())
        let e1  = makeFakeEvent(id: "1", start: day.addingTimeInterval(3600),
                                end: day.addingTimeInterval(5400))
        let e2  = makeFakeEvent(id: "2", start: day.addingTimeInterval(7200),
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
        XCTAssertEqual(MenuBuilder.plainTitles(of: items)[0], "Today (\(dateFormatter.string(from: day))):")
    }

    func test_joinSectionHasCreateAndJoin() {
        let next = makeFakeEvent(id: "J",
                                 start: Date(), end: Date().addingTimeInterval(60))
        let items = MenuBuilder(target: Dummy())
            .buildJoinSection(nextEvent: next)

        XCTAssertEqual(MenuBuilder.plainTitles(of: items)[0],
                       "status_bar_section_join_current_meeting".loco())
        XCTAssertTrue(items.contains { $0.action == #selector(StatusBarItemController.createMeetingAction) })
    }

    func test_joinSectionWithoutEvent() {
        let items = MenuBuilder(target: Dummy())
            .buildJoinSection(nextEvent: nil)
        XCTAssertEqual(items.count, 2) // Create meeting and quick actions
        XCTAssertEqual(items[0].action,
                       #selector(StatusBarItemController.createMeetingAction))
    }

    func test_preferencesSectionContainsExpectedItems() {
        // --- Arrange -----------------------------------------------------------------
        // Force "What's New" to appear
        Defaults[.appVersion] = "5.0.0"
        Defaults[.lastRevisedVersionInChangelog] = "4.2.0"

        // Force "Rate App" to appear (installation > 14 days ago)
        let distantPast = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let builder     = MenuBuilder(target: Dummy(), installationDate: distantPast)

        // --- Act ---------------------------------------------------------------------
        let items   = builder.buildPreferencesSection()
        let titles  = MenuBuilder.plainTitles(of: items)

        // --- Assert ------------------------------------------------------------------
        XCTAssertTrue(titles.contains(where: { $0.contains("status_bar_whats_new".loco()) }),
                      "Should show “What's New” when appVersion > changelogVersion")

        XCTAssertTrue(titles.contains(where: { $0.contains("status_bar_rate_app".loco()) }),
                      "Should show “Rate App” button after two weeks")

        XCTAssertEqual(items.last?.action,
                       #selector(AppDelegate.quit),
                       "Last item must be Quit")
    }

    func test_bookmarksInlineWhenCountIsThreeOrLess() {
        // --- Arrange -----------------------------------------------------------------
        Defaults[.bookmarks] = [
            Bookmark(name: "Zoom", service: .zoom, url: URL(string: "https://zoom.us")!),
            Bookmark(name: "Meet", service: .meet, url: URL(string: "https://meet.google.com")!)
        ]

        let builder = MenuBuilder(target: Dummy())

        // --- Act ---------------------------------------------------------------------
        let items   = builder.buildBookmarksSection()
        let titles  = MenuBuilder.plainTitles(of: items)

        // --- Assert ------------------------------------------------------------------
        XCTAssertEqual(titles.filter { $0 == "Zoom" }.count, 1)
        XCTAssertEqual(titles.filter { $0 == "Meet" }.count, 1)
        // Header must be disabled (inline mode)
        XCTAssertFalse(items[0].isEnabled)
    }

    func test_bookmarksGoToSubmenuWhenCountGreaterThanThree() {
        // --- Arrange -----------------------------------------------------------------
        Defaults[.bookmarks] = (1...4).map {
            Bookmark(name: "BM\($0)", service: .url, url: URL(string: "https://example.com/\($0)")!)
        }

        let builder = MenuBuilder(target: Dummy())

        // --- Act ---------------------------------------------------------------------
        let items = builder.buildBookmarksSection()

        // --- Assert ------------------------------------------------------------------
        let header = items[0]
        XCTAssertNotNil(header.submenu, "Header should have submenu when > 3 bookmarks")
        XCTAssertEqual(header.submenu!.items.count, 4)
        XCTAssertEqual(header.submenu!.items[2].action,
                       #selector(StatusBarItemController.joinBookmark))
    }

    func test_plainSnapshot() {
        let today = Calendar.current.startOfDay(for: .init())
        let e1 = makeFakeEvent(id: "S1",
                               start: today.addingTimeInterval(1800),
                               end: today.addingTimeInterval(3600))
        let e2 = makeFakeEvent(id: "S2",
                               start: today.addingTimeInterval(7200),
                               end: today.addingTimeInterval(8100))

        var allItems: [NSMenuItem] = []
        let builder = MenuBuilder(target: Dummy())
        allItems += builder.buildDateSection(date: today,
                                             title: "Today", events: [e1, e2])
        allItems += builder.buildJoinSection(nextEvent: e1)

        // “Snapshot”: порівнюємо plain-titles з еталоном
        let snapshot = MenuBuilder.plainTitles(of: allItems)
        XCTAssertEqual(snapshot, [
            "Today (\(dateFormatter.string(from: today))):",
            "00:30 \t 01:00 \t Event S1",
            "02:00 \t 02:15 \t Event S2",
            "status_bar_section_join_current_meeting".loco(),
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
    private func buildItem(event: MBEvent) -> NSMenuItem? {
        let items = MenuBuilder(target: Dummy())
            .buildDateSection(date: Date(),
                              title: "T",
                              events: [event])
        return items.count > 1 ? items[1] : nil              // 0 = header
    }

    // MARK: – Tests -----------------------------------------------------------

    /// Placeholder text when no events
    func test_NoEvents() {
        let dateSection = MenuBuilder(target: Dummy())
            .buildDateSection(date: Date(), title: "T", events: [])
        XCTAssertTrue(dateSection[1].title.contains("status_bar_section_date_nothing".loco("t")))

    }
    /// declined + `.hide` ⇒ item should be skipped completely
    func test_declinedEventHiddenWhenAppearanceIsHide() {
        Defaults[.declinedEventsAppereance] = .hide

        var event = makeFakeEvent(id: "D",
                              start: Date().addingTimeInterval(600),
                              end: Date().addingTimeInterval(1200))
        event.participationStatus = .declined

        let item = buildItem(event: event)
        XCTAssertNil(item)
    }

    /// pending + `.show_underlined` ⇒ underline attribute present
    func test_pendingEventUnderlined() {
        Defaults[.showPendingEvents] = .show_underlined

        var event = makeFakeEvent(id: "P",
                              start: Date().addingTimeInterval(600),
                              end: Date().addingTimeInterval(1200))
        event.participationStatus = .pending

        let item = buildItem(event: event)

        let underline = item!.attributedTitle?
            .attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertNotNil(underline,
                        "pending event should be underlined when setting is .show_underlined")
    }

    /// showEventDetails == true ⇒ submenu with title/status exists
    func test_submenuCreatedWhenShowEventDetailsTrue() {
        Defaults[.showEventDetails] = true

        var event = makeFakeEvent(id: "DET",
                              start: Date().addingTimeInterval(600),
                              end: Date().addingTimeInterval(1200))
        // add an attendee so Status section appears
        event.attendees = [MBEventAttendee(email: nil, name: "Alice",
                                       status: .accepted,
                                       optional: false,
                                       isCurrentUser: false)]

        let item = buildItem(event: event)

        let subItems = item?.submenu?.items ?? []
        XCTAssertNotNil(item?.submenu)
        XCTAssertEqual(subItems.first?.title, "Event DET")
        XCTAssertTrue(subItems.contains { $0.title.lowercased().contains("status") })
    }

    /// running event (state == .mixed) ⇒ bold font applied
    func test_runningEventGetsBoldFont() {
        let now = Date()
        let runEvent = makeFakeEvent(
            id: "RUN",
            start: now.addingTimeInterval(-300),     // started 5 min ago
            end: now.addingTimeInterval( 900)      // ends in 15 min
        )

        let item = buildItem(event: runEvent)
        XCTAssertEqual(item?.state, .mixed)

        let font = item!.attributedTitle?
            .attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
                      "running event title should be bold")
    }
}

@MainActor
final class MenuBuilderQuickActionsTests: BaseTestCase {

    private class Dummy: NSObject {}

    func test_quickActionsIncludesDismissRemove() {
        let next = makeFakeEvent(id: "Q",
                                 start: Date().addingTimeInterval(30),
                                 end: Date().addingTimeInterval(900))
        // there is at least one dismissed event -> menu should add “Remove all”
        Defaults[.dismissedEvents] = [ProcessedEvent(id: "123", eventEndDate: Date())]

        let root = MenuBuilder(target: Dummy())
            .buildJoinSection(nextEvent: next)

        // last element is quick actions header
        let qa = root.last!
        let titles = MenuBuilder.plainTitles(of: qa.submenu!.items)
        XCTAssertTrue(titles.contains { $0.contains("dismiss") })
        XCTAssertTrue(titles.contains { $0.contains("status_bar_menu_remove_all_dismissals".loco()) })
    }

}
