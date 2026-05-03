//
//  AppSettingsTests.swift
//  MeetingBarTests
//
//  Verifies that SettingsStore.settings correctly maps Defaults keys to
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
            SettingsStore.shared.settings.calendar.selectedCalendarIDs, ["cal-1", "cal-2"])
    }

    func testCalendarSettings_eventStoreProvider() {
        Defaults[.eventStoreProvider] = .googleCalendar
        XCTAssertEqual(SettingsStore.shared.settings.calendar.eventStoreProvider, .googleCalendar)
    }

    // MARK: - StatusBarSettings

    func testStatusBarSettings_hideMeetingTitle() {
        Defaults[.hideMeetingTitle] = true
        XCTAssertTrue(SettingsStore.shared.settings.statusBar.hideMeetingTitle)
    }

    func testStatusBarSettings_hideMeetingTitle_default() {
        XCTAssertFalse(SettingsStore.shared.settings.statusBar.hideMeetingTitle)
    }

    func testStatusBarSettings_eventTitleFormat() {
        Defaults[.eventTitleFormat] = .dot
        XCTAssertEqual(SettingsStore.shared.settings.statusBar.eventTitleFormat, .dot)
    }

    // MARK: - NotificationSettings

    func testNotificationSettings_joinEventNotification() {
        Defaults[.joinEventNotification] = false
        XCTAssertFalse(SettingsStore.shared.settings.notifications.joinEventNotification)
    }

    func testNotificationSettings_joinEventNotificationTime() {
        Defaults[.joinEventNotificationTime] = .fiveMinuteBefore
        XCTAssertEqual(
            SettingsStore.shared.settings.notifications.joinEventNotificationTime, .fiveMinuteBefore
        )
    }

    func testNotificationSettings_endOfEventNotificationTime() {
        Defaults[.endOfEventNotificationTime] = .threeMinuteBefore
        XCTAssertEqual(
            SettingsStore.shared.settings.notifications.endOfEventNotificationTime,
            .threeMinuteBefore)
    }

    // MARK: - EventDisplaySettings

    func testEventDisplaySettings_filterEventRegexes() {
        Defaults[.filterEventRegexes] = ["standup", "lunch"]
        XCTAssertEqual(
            SettingsStore.shared.settings.events.filterEventRegexes, ["standup", "lunch"])
    }

    func testEventDisplaySettings_showEventsForPeriod() {
        Defaults[.showEventsForPeriod] = .today
        XCTAssertEqual(SettingsStore.shared.settings.events.showEventsForPeriod, .today)
    }

    // MARK: - AdvancedSettings

    func testAdvancedSettings_automaticEventJoin() {
        Defaults[.automaticEventJoin] = true
        XCTAssertTrue(SettingsStore.shared.settings.advanced.automaticEventJoin)
    }

    func testAdvancedSettings_runJoinEventScript() {
        Defaults[.runJoinEventScript] = true
        XCTAssertTrue(SettingsStore.shared.settings.advanced.runJoinEventScript)
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
