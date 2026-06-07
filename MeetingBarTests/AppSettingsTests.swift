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
    func testEmptyMatchesCleanInstallDefaults() {
        XCTAssertEqual(AppSettings.empty, AppSettings.current)
    }

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

    func testCalendarWriteHelpersUpdateProviderAndSelection() {
        AppSettings.setEventStoreProvider(.googleCalendar)
        AppSettings.setCalendarSelection(id: "cal-1", selected: true)
        AppSettings.setCalendarSelection(id: "cal-1", selected: true)
        AppSettings.setCalendarSelection(id: "cal-2", selected: true)
        AppSettings.setCalendarSelection(id: "cal-1", selected: false)

        XCTAssertEqual(Defaults[.eventStoreProvider], .googleCalendar)
        XCTAssertEqual(Defaults[.selectedCalendarIDs], ["cal-2"])

        AppSettings.clearSelectedCalendars()

        XCTAssertTrue(Defaults[.selectedCalendarIDs].isEmpty)
    }

    func testSelectingSharedGoogleCalendarPreservesProviderScopedSelections() {
        Defaults[.eventStoreProvider] = .googleCalendar
        Defaults[.selectedCalendarIDs] = ["primary"]
        Defaults[.selectedCalendarIDsByProvider] = [
            EventStoreProvider.googleCalendar.rawValue: ["primary"],
            EventStoreProvider.macOSEventKit.rawValue: ["eventkit-calendar"]
        ]
        Defaults[.selectedCalendarIDsByProviderMigrated] = true

        AppSettings.setCalendarSelection(id: "shared-public", selected: true)

        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .googleCalendar),
            ["primary", "shared-public"]
        )
        XCTAssertEqual(Defaults[.selectedCalendarIDs], ["primary", "shared-public"])
        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .macOSEventKit),
            ["eventkit-calendar"]
        )
    }

    func testLegacyCalendarSelectionMigratesToActiveProvider() {
        Defaults[.eventStoreProvider] = .macOSEventKit
        Defaults[.selectedCalendarIDs] = ["legacy-calendar"]

        AppSettings.migrateSelectedCalendarsByProviderIfNeeded()

        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .macOSEventKit),
            ["legacy-calendar"]
        )
        XCTAssertTrue(Defaults[.selectedCalendarIDsByProviderMigrated])
    }

    func testCompleteOnboardingWriteHelper() {
        AppSettings.completeOnboarding()

        XCTAssertTrue(Defaults[.onboardingCompleted])
    }

    func testAcknowledgeCurrentChangelogWriteHelper() {
        Defaults[.appVersion] = "5.1.0"

        AppSettings.acknowledgeCurrentChangelog()

        XCTAssertEqual(Defaults[.lastRevisedVersionInChangelog], "5.1.0")
    }

    // MARK: - StatusBarSettings

    func testStatusBarSettings_hideMeetingTitle() {
        Defaults[.hideMeetingTitle] = true
        XCTAssertTrue(AppSettings.current.statusBar.hideMeetingTitle)
    }

    func testStatusBarSettings_hideMeetingTitle_default() {
        XCTAssertFalse(AppSettings.current.statusBar.hideMeetingTitle)
    }

    func testNoLinkFullscreenNotificationsDefaultOffAndMapFromDefaults() {
        XCTAssertFalse(
            AppSettings.current.notifications
                .fullscreenNotificationsForEventsWithoutMeetingLink
        )

        Defaults[.fullscreenNotificationsForEventsWithoutMeetingLink] = true

        XCTAssertTrue(
            AppSettings.current.notifications
                .fullscreenNotificationsForEventsWithoutMeetingLink
        )
    }

    func testToggleMeetingTitleVisibilityWriteHelper() {
        AppSettings.toggleMeetingTitleVisibility()
        XCTAssertTrue(Defaults[.hideMeetingTitle])

        AppSettings.toggleMeetingTitleVisibility()
        XCTAssertFalse(Defaults[.hideMeetingTitle])
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

    func testDismissalWriteHelpers() {
        let now = Date()
        let event = makeFakeEvent(
            id: "event",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(1800),
            lastModifiedDate: now
        )

        AppSettings.dismissEvent(event)

        XCTAssertEqual(Defaults[.dismissedEvents].map(\.id), ["event"])
        XCTAssertEqual(Defaults[.dismissedEvents].first?.lastModifiedDate, now)

        AppSettings.undismissEvent(id: "event")
        XCTAssertTrue(Defaults[.dismissedEvents].isEmpty)

        AppSettings.dismissEvent(event)
        AppSettings.clearDismissedEvents()
        XCTAssertTrue(Defaults[.dismissedEvents].isEmpty)
    }

    func testRefreshDismissedEventsDropsMissingOrExpiredDismissals() {
        let now = Date()
        let futureEvent = makeFakeEvent(
            id: "future",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(1800)
        )
        let expiredEvent = makeFakeEvent(
            id: "expired",
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(-60)
        )
        AppSettings.replaceDismissedEvents([
            ProcessedEvent(id: "future", eventEndDate: now.addingTimeInterval(60)),
            ProcessedEvent(id: "missing", eventEndDate: now.addingTimeInterval(60)),
            ProcessedEvent(id: "expired", eventEndDate: now.addingTimeInterval(60))
        ])

        AppSettings.refreshDismissedEvents(using: [futureEvent, expiredEvent])

        XCTAssertEqual(Defaults[.dismissedEvents].map(\.id), ["future"])
        XCTAssertEqual(Defaults[.dismissedEvents].first?.eventEndDate, futureEvent.endDate)
    }

    func testRefreshDismissedEventsPreservesOriginalLastModifiedDate() {
        let now = Date()
        let dismissedAt = now.addingTimeInterval(-1000) // modified date captured at dismissal
        let changedAt = now.addingTimeInterval(-10) // the event was changed afterwards

        // Current event carries a newer lastModifiedDate than the stored dismissal.
        let currentEvent = makeFakeEvent(
            id: "evt",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(1800),
            lastModifiedDate: changedAt
        )
        AppSettings.replaceDismissedEvents([
            ProcessedEvent(
                id: "evt", lastModifiedDate: dismissedAt, eventEndDate: now.addingTimeInterval(600))
        ])

        AppSettings.refreshDismissedEvents(using: [currentEvent])

        let refreshed = Defaults[.dismissedEvents].first
        XCTAssertEqual(refreshed?.id, "evt")
        // Original dismissal modified-date is preserved, not overwritten by the
        // current (changed) event's modified-date.
        XCTAssertEqual(refreshed?.lastModifiedDate, dismissedAt)
        // End date is refreshed from the current event.
        XCTAssertEqual(refreshed?.eventEndDate, currentEvent.endDate)
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

    // MARK: - App source / Patronage writes

    func testAppSourceWriteHelper() {
        AppSettings.setInstalledFromAppStore(true)
        XCTAssertTrue(Defaults[.isInstalledFromAppStore])

        AppSettings.setInstalledFromAppStore(false)
        XCTAssertFalse(Defaults[.isInstalledFromAppStore])
    }

    func testPatronageWriteHelpers() {
        AppSettings.addPatronageDuration(months: 3)
        AppSettings.addPatronageDuration(months: 6, quantity: 2)

        XCTAssertEqual(Defaults[.patronageDuration], 15)

        AppSettings.resetPatronageDuration()

        XCTAssertEqual(Defaults[.patronageDuration], 0)
    }

    func testPatronageTransactionsAreRecordedOnlyOnce() {
        XCTAssertTrue(AppSettings.recordPatronageTransaction(
            id: 42,
            months: 3,
            quantity: 2
        ))
        XCTAssertFalse(AppSettings.recordPatronageTransaction(
            id: 42,
            months: 3,
            quantity: 2
        ))

        XCTAssertEqual(AppSettings.patronageDuration, 6)
        XCTAssertEqual(AppSettings.processedPatronageTransactionIDs, ["42"])
    }

    func testResetPatronageClearsProcessedTransactions() {
        AppSettings.recordPatronageTransaction(id: 42, months: 3, quantity: 1)

        AppSettings.resetPatronageDuration()

        XCTAssertEqual(AppSettings.patronageDuration, 0)
        XCTAssertTrue(AppSettings.processedPatronageTransactionIDs.isEmpty)
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
