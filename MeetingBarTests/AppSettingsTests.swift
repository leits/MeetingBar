//
//  AppSettingsTests.swift
//  MeetingBarTests
//
//  Verifies that AppSettings.current correctly maps Defaults keys to
//  AppSettings fields. Each test writes a non-default value to a key and
//  asserts the snapshot reflects it.
//

import Defaults
import XCTest

@testable import MeetingBar

@MainActor
final class AppSettingsTests: BaseTestCase {
    // MARK: - CalendarSettings

    func testCalendarSettings_selectedCalendarIDs() {
        Defaults[.selectedCalendarIDs] = ["cal-1", "cal-2"]
        XCTAssertEqual(
            AppSettings.current.calendar.selectedCalendarIDs, ["cal-1", "cal-2"])
    }

    func testCalendarSettings_eventStoreProvider() {
        Defaults[.eventStoreProvider] = .googleCalendar
        XCTAssertEqual(AppSettings.current.calendar.eventStoreProvider, .googleCalendar)
    }

    // MARK: - StatusBarSettings

    func testStatusBarSettings_hideMeetingTitle() {
        Defaults[.hideMeetingTitle] = true
        XCTAssertTrue(AppSettings.current.statusBar.hideMeetingTitle)
    }

    func testStatusBarSettings_hideMeetingTitle_default() {
        XCTAssertFalse(AppSettings.current.statusBar.hideMeetingTitle)
    }

    func testStatusBarSettings_eventTitleFormat() {
        Defaults[.eventTitleFormat] = .dot
        XCTAssertEqual(AppSettings.current.statusBar.eventTitleFormat, .dot)
    }

    // MARK: - NotificationSettings

    func testNotificationSettings_joinEventNotification() {
        Defaults[.joinEventNotification] = false
        XCTAssertFalse(AppSettings.current.notifications.joinEventNotification)
    }

    func testNotificationSettings_joinEventNotificationTime() {
        Defaults[.joinEventNotificationTime] = .fiveMinuteBefore
        XCTAssertEqual(
            AppSettings.current.notifications.joinEventNotificationTime, .fiveMinuteBefore
        )
    }

    func testNotificationSettings_endOfEventNotificationTime() {
        Defaults[.endOfEventNotificationTime] = .threeMinuteBefore
        XCTAssertEqual(
            AppSettings.current.notifications.endOfEventNotificationTime,
            .threeMinuteBefore)
    }

    // MARK: - EventDisplaySettings

    func testEventDisplaySettings_filterEventRegexes() {
        Defaults[.filterEventRegexes] = ["standup", "lunch"]
        XCTAssertEqual(
            AppSettings.current.events.filterEventRegexes, ["standup", "lunch"])
    }

    func testEventDisplaySettings_showEventsForPeriod() {
        Defaults[.showEventsForPeriod] = .today
        XCTAssertEqual(AppSettings.current.events.showEventsForPeriod, .today)
    }

    // MARK: - AdvancedSettings

    func testAdvancedSettings_automaticEventJoin() {
        Defaults[.automaticEventJoin] = true
        XCTAssertTrue(AppSettings.current.advanced.automaticEventJoin)
    }

    func testAdvancedSettings_runJoinEventScript() {
        Defaults[.runJoinEventScript] = true
        XCTAssertTrue(AppSettings.current.advanced.runJoinEventScript)
    }

    // MARK: - currentForScheduler integration

    func testCurrentForScheduler_hideMeetingTitle_propagates() {
        Defaults[.hideMeetingTitle] = true
        let settings = NotificationPlanningSettings.currentForScheduler
        XCTAssertTrue(settings.hideMeetingTitle)
    }

    func testCurrentForScheduler_hideMeetingTitle_default_isFalse() {
        let settings = NotificationPlanningSettings.currentForScheduler
        XCTAssertFalse(settings.hideMeetingTitle)
    }

    func testCurrentForScheduler_eventStartBody_atStart() {
        Defaults[.joinEventNotificationTime] = .atStart
        let settings = NotificationPlanningSettings.currentForScheduler
        XCTAssertFalse(settings.eventStartBody.isEmpty)
    }

    func testCurrentForScheduler_eventEndBody_minuteBefore() {
        Defaults[.endOfEventNotificationTime] = .minuteBefore
        let settings = NotificationPlanningSettings.currentForScheduler
        XCTAssertFalse(settings.eventEndBody.isEmpty)
    }
}
