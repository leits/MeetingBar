//
//  PreferencesPresentationTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class PreferencesPresentationTests: XCTestCase {
    func testCalendarSourcesExplainDistinctDataSourcesAndAccountScopes() {
        XCTAssertEqual(
            CalendarSourcePresentation.all.map(\.provider),
            [.macOSEventKit, .googleCalendar]
        )

        let macOSSource = CalendarSourcePresentation.make(for: .macOSEventKit)
        XCTAssertEqual(macOSSource.titleKey, "onboarding_apple_calendar_title")
        XCTAssertEqual(
            macOSSource.dataSourceKey,
            "access_screen_provider_macos_data_source"
        )
        XCTAssertEqual(
            macOSSource.accountScopeKey,
            "access_screen_provider_macos_number_of_accounts"
        )

        let googleSource = CalendarSourcePresentation.make(for: .googleCalendar)
        XCTAssertEqual(googleSource.titleKey, "onboarding_google_calendar_title")
        XCTAssertEqual(
            googleSource.dataSourceKey,
            "access_screen_provider_gcalendar_data_source"
        )
        XCTAssertEqual(
            googleSource.accountScopeKey,
            "access_screen_provider_gcalendar_number_of_accounts"
        )
    }

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
        XCTAssertEqual(
            PreferencesTab.allCases.map(\.systemImage),
            [
                "gearshape",
                "calendar",
                "arrow.up.right.square",
                "menubar.rectangle",
                "bell",
                "slider.horizontal.3",
                "waveform.path.ecg"
            ]
        )
    }

    func testPreferencesDefaultSelectionIsGeneral() {
        XCTAssertEqual(PreferencesTab.defaultSelection, .general)
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
        XCTAssertEqual(
            presentation.providerDataSourceKey,
            "access_screen_provider_gcalendar_data_source"
        )
        XCTAssertEqual(
            presentation.providerAccountScopeKey,
            "access_screen_provider_gcalendar_number_of_accounts"
        )
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

    func testRegexDraftDoesNotMutateOriginalListBeforeSave() {
        let regexes = ["meet\\.google\\.com", "zoom\\.us"]

        let draft = RegexEditDraft.editing(regexes[0])

        XCTAssertEqual(draft.originalValue, regexes[0])
        XCTAssertEqual(draft.value, regexes[0])
        XCTAssertEqual(regexes, ["meet\\.google\\.com", "zoom\\.us"])
    }

    func testSavingRegexDraftReplacesOriginalInPlace() {
        var draft = RegexEditDraft.editing("meet\\.google\\.com")
        draft.value = "teams\\.microsoft\\.com"

        XCTAssertEqual(
            RegexListEditingPolicy.saving(
                draft,
                in: ["meet\\.google\\.com", "zoom\\.us"]
            ),
            .saved(["teams\\.microsoft\\.com", "zoom\\.us"])
        )
    }

    func testSavingRegexDraftPreventsDuplicates() {
        var draft = RegexEditDraft.editing("meet\\.google\\.com")
        draft.value = "zoom\\.us"

        XCTAssertEqual(
            RegexListEditingPolicy.saving(
                draft,
                in: ["meet\\.google\\.com", "zoom\\.us"]
            ),
            .duplicate
        )
    }

    func testSavingNewRegexAppendsWithoutChangingExistingValues() {
        var draft = RegexEditDraft.adding()
        draft.value = "teams\\.microsoft\\.com"

        XCTAssertEqual(
            RegexListEditingPolicy.saving(draft, in: ["zoom\\.us"]),
            .saved(["zoom\\.us", "teams\\.microsoft\\.com"])
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

    func testMeetingProviderOpeningSelectionRestoresLegacySentinel() {
        let provider = MeetingProvider.provider(for: .zoom)!

        XCTAssertEqual(
            MeetingProviderOpeningSelectionPolicy.selected(
                provider: provider,
                providerBrowsers: [provider.id: zoomAppBrowser],
                providerOpeningModes: [:]
            ),
            .mode(.zoomApp)
        )
    }

    func testMeetingProviderOpeningSelectionPersistsModeAndBrowserFallback() {
        let provider = MeetingProvider.provider(for: .zoom)!
        let chrome = Browser(
            name: "Google Chrome",
            path: "/Applications/Google Chrome.app"
        )

        let updated = MeetingProviderOpeningSelectionPolicy.updating(
            provider: provider,
            selection: .mode(.zoomWebApp),
            providerBrowsers: [provider.id: chrome],
            providerOpeningModes: [:]
        )

        XCTAssertEqual(updated.providerBrowsers[provider.id], chrome)
        XCTAssertEqual(
            updated.providerOpeningModes[provider.id],
            MeetingOpeningMode.zoomWebApp.rawValue
        )
        XCTAssertEqual(
            MeetingProviderOpeningSelectionPolicy.selected(
                provider: provider,
                providerBrowsers: updated.providerBrowsers,
                providerOpeningModes: updated.providerOpeningModes
            ),
            .mode(.zoomWebApp)
        )
    }

    func testMeetingProviderOpeningSelectionReplacesLegacySentinelWithMode() {
        let provider = MeetingProvider.provider(for: .meet)!

        let updated = MeetingProviderOpeningSelectionPolicy.updating(
            provider: provider,
            selection: .mode(.googleMeetPWA),
            providerBrowsers: [provider.id: meetInOneBrowser],
            providerOpeningModes: [:]
        )

        XCTAssertNil(updated.providerBrowsers[provider.id])
        XCTAssertEqual(
            updated.providerOpeningModes[provider.id],
            MeetingOpeningMode.googleMeetPWA.rawValue
        )
    }

    func testMeetingProviderOpeningSelectionBrowserClearsMode() {
        let provider = MeetingProvider.provider(for: .facebook_workspace)!
        let safari = Browser(
            name: "Safari",
            path: "/Applications/Safari.app"
        )

        let updated = MeetingProviderOpeningSelectionPolicy.updating(
            provider: provider,
            selection: .browser(safari),
            providerBrowsers: [:],
            providerOpeningModes: [
                provider.id: MeetingOpeningMode.workplaceApp.rawValue
            ]
        )

        XCTAssertEqual(updated.providerBrowsers[provider.id], safari)
        XCTAssertNil(updated.providerOpeningModes[provider.id])
    }

    func testMeetingProviderOpeningSelectionDefaultClearsOverrides() {
        let provider = MeetingProvider.provider(for: .zoom)!

        let updated = MeetingProviderOpeningSelectionPolicy.updating(
            provider: provider,
            selection: .browser(systemDefaultBrowser),
            providerBrowsers: [provider.id: zoomAppBrowser],
            providerOpeningModes: [
                provider.id: MeetingOpeningMode.zoomWebApp.rawValue
            ]
        )

        XCTAssertNil(updated.providerBrowsers[provider.id])
        XCTAssertNil(updated.providerOpeningModes[provider.id])
    }

    func testMeetingProviderOpeningSelectionIgnoresUnknownStoredMode() {
        let provider = MeetingProvider.provider(for: .zoom)!
        let chrome = Browser(
            name: "Google Chrome",
            path: "/Applications/Google Chrome.app"
        )

        XCTAssertEqual(
            MeetingProviderOpeningSelectionPolicy.selected(
                provider: provider,
                providerBrowsers: [provider.id: chrome],
                providerOpeningModes: [provider.id: "removed-mode"]
            ),
            .browser(chrome)
        )
    }
}
