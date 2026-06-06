//
//  PreferencesPresentationTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class PreferencesPresentationTests: XCTestCase {
    func testPreferencesTabsExposeCoreProductConceptsInOrder() {
        XCTAssertEqual(
            PreferencesTab.allCases,
            [
                .general,
                .calendars,
                .meetingOpening,
                .menuBar,
                .notifications,
                .advanced,
                .status
            ]
        )
        XCTAssertEqual(
            PreferencesTab.allCases.map(\.titleKey),
            [
                "preferences_tab_general",
                "preferences_tab_calendars",
                "preferences_tab_meeting_opening",
                "preferences_tab_menu_bar",
                "preferences_tab_notifications",
                "preferences_tab_advanced",
                "preferences_tab_status"
            ]
        )
    }

    func testStatusBarTimeOptionsIncludeHide() {
        XCTAssertEqual(
            PreferencesStatusBarTimeOption.allCases.map(\.format),
            [.show, .show_under_title, .hide]
        )
        XCTAssertEqual(
            PreferencesStatusBarTimeOption.allCases.map(\.titleKey),
            [
                "preferences_appearance_status_bar_time_show_value",
                "preferences_appearance_status_bar_time_show_under_title_value",
                "preferences_appearance_status_bar_time_hide_value"
            ]
        )
    }

    func testConnectedProviderPresentationUsesAppStateCounts() {
        let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = AppState()
        state.activeProvider = .googleCalendar
        state.calendars = [
            makeFakeCalendar(id: "work"),
            makeFakeCalendar(id: "personal")
        ]
        state.selectedCalendarIDs = ["work"]
        state.providerHealth = ProviderHealth.success(attempted: refreshedAt)

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertEqual(presentation.connectionState, .connected)
        XCTAssertEqual(presentation.statusTone, .success)
        XCTAssertEqual(presentation.statusTextKey, "preferences_status_state_ok")
        XCTAssertEqual(presentation.providerTitleKey, "onboarding_google_calendar_title")
        XCTAssertEqual(presentation.selectedCalendarCount, 1)
        XCTAssertEqual(presentation.availableCalendarCount, 2)
        XCTAssertFalse(presentation.canReconnect)
    }

    func testGoogleAuthRequiredPresentationOffersReconnect() {
        var state = AppState()
        state.activeProvider = .googleCalendar
        state.calendars = [makeFakeCalendar(id: "cached")]
        state.providerHealth = ProviderHealth(
            lastErrorDescription: "Sign in again",
            isStale: true,
            authRequired: true
        )

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertEqual(presentation.connectionState, .authRequired)
        XCTAssertEqual(presentation.statusTone, .error)
        XCTAssertTrue(presentation.canReconnect)
        XCTAssertFalse(presentation.canOpenCalendarSettings)
        XCTAssertEqual(
            presentation.emptyStateTextKey,
            "onboarding_calendar_selection_reconnect"
        )
    }

    func testInitialEventKitFailureIsPresentedAsPermissionRequired() {
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = [makeFakeCalendar(id: "cached")]
        state.providerHealth = ProviderHealth(
            lastAttemptedRefresh: Date(timeIntervalSince1970: 1_700_000_000),
            lastErrorDescription: "Access denied",
            isStale: true
        )

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertEqual(presentation.connectionState, .permissionRequired)
        XCTAssertEqual(
            presentation.statusTextKey,
            "preferences_status_state_permission_required"
        )
        XCTAssertTrue(presentation.canOpenCalendarSettings)
        XCTAssertFalse(presentation.canReconnect)
    }

    func testFailedRefreshWithCachedDataIsPresentedAsStale() {
        let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = AppState()
        state.activeProvider = .googleCalendar
        state.providerHealth = ProviderHealth(
            lastSuccessfulRefresh: refreshedAt,
            lastAttemptedRefresh: refreshedAt.addingTimeInterval(60),
            lastErrorDescription: "Network unavailable",
            isStale: true
        )

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertEqual(presentation.connectionState, .stale)
        XCTAssertEqual(presentation.statusTone, .warning)
        XCTAssertEqual(presentation.statusTextKey, "preferences_status_state_stale")
    }

    func testProviderPickerRequestsOnlyTransactionalProviderChanges() {
        XCTAssertFalse(
            ProviderPickerSelectionPolicy.shouldRequestChange(
                selectedProvider: .macOSEventKit,
                activeProvider: .macOSEventKit,
                providerChangeInProgress: false
            )
        )
        XCTAssertFalse(
            ProviderPickerSelectionPolicy.shouldRequestChange(
                selectedProvider: .googleCalendar,
                activeProvider: .macOSEventKit,
                providerChangeInProgress: true
            )
        )
        XCTAssertTrue(
            ProviderPickerSelectionPolicy.shouldRequestChange(
                selectedProvider: .googleCalendar,
                activeProvider: .macOSEventKit,
                providerChangeInProgress: false
            )
        )
    }

    func testProviderPickerRollsBackToActiveProviderAfterFailedChange() {
        XCTAssertEqual(
            ProviderPickerSelectionPolicy.synchronizedSelection(
                currentSelection: .googleCalendar,
                activeProvider: .macOSEventKit,
                providerChangeInProgress: true
            ),
            .googleCalendar
        )
        XCTAssertEqual(
            ProviderPickerSelectionPolicy.synchronizedSelection(
                currentSelection: .googleCalendar,
                activeProvider: .macOSEventKit,
                providerChangeInProgress: false
            ),
            .macOSEventKit
        )
    }

    func testCalendarBulkSelectionOnlyAddsMissingCalendars() {
        let changes = CalendarSelectionBulkPolicy.changes(
            calendars: [
                makeFakeCalendar(id: "work"),
                makeFakeCalendar(id: "personal")
            ],
            selectedCalendarIDs: ["work"],
            selectingAll: true
        )

        XCTAssertEqual(
            changes,
            [CalendarSelectionChange(id: "personal", selected: true)]
        )
    }

    func testCalendarBulkDeselectionClearsActiveProviderSelection() {
        let changes = CalendarSelectionBulkPolicy.changes(
            calendars: [makeFakeCalendar(id: "work")],
            selectedCalendarIDs: ["work", "shared"],
            selectingAll: false
        )

        XCTAssertEqual(
            changes,
            [
                CalendarSelectionChange(id: "work", selected: false),
                CalendarSelectionChange(id: "shared", selected: false)
            ]
        )
    }

    func testMeetingProviderBrowserSelectionPersistsAndClearsOverrides() {
        let chrome = Browser(
            name: "Google Chrome",
            path: "/Applications/Google Chrome.app"
        )
        let providerID = "Google Meet"

        XCTAssertEqual(
            MeetingProviderBrowserSelection.selectedBrowser(
                providerID: providerID,
                providerBrowsers: [:]
            ),
            systemDefaultBrowser
        )

        let configured = MeetingProviderBrowserSelection.updating(
            providerID: providerID,
            browser: chrome,
            providerBrowsers: [:]
        )
        XCTAssertEqual(configured[providerID], chrome)

        let reset = MeetingProviderBrowserSelection.updating(
            providerID: providerID,
            browser: systemDefaultBrowser,
            providerBrowsers: configured
        )
        XCTAssertNil(reset[providerID])
    }
}
