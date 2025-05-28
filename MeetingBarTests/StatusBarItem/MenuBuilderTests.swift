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
        print(titles)

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
