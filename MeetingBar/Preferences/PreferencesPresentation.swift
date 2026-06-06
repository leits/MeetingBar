//
//  PreferencesPresentation.swift
//  MeetingBar
//

import Foundation

enum PreferencesTab: CaseIterable, Equatable {
    case general
    case calendars
    case meetingOpening
    case menuBar
    case notifications
    case advanced
    case status

    // This metadata is the single source of truth for the current TabView and
    // can also drive a future sidebar without duplicating labels or ordering.
    var titleKey: String {
        switch self {
        case .general:
            "preferences_tab_general"
        case .calendars:
            "preferences_tab_calendars"
        case .meetingOpening:
            "preferences_tab_meeting_opening"
        case .menuBar:
            "preferences_tab_menu_bar"
        case .notifications:
            "preferences_tab_notifications"
        case .advanced:
            "preferences_tab_advanced"
        case .status:
            "preferences_tab_status"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .calendars:
            "calendar"
        case .meetingOpening:
            "arrow.up.right.square"
        case .menuBar:
            "menubar.rectangle"
        case .notifications:
            "bell"
        case .advanced:
            "slider.horizontal.3"
        case .status:
            "waveform.path.ecg"
        }
    }
}

enum PreferencesStatusBarTimeOption: CaseIterable, Equatable {
    case show
    case showUnderTitle
    case hide

    var format: EventTimeFormat {
        switch self {
        case .show:
            .show
        case .showUnderTitle:
            .show_under_title
        case .hide:
            .hide
        }
    }

    var titleKey: String {
        switch self {
        case .show:
            "preferences_appearance_status_bar_time_show_value"
        case .showUnderTitle:
            "preferences_appearance_status_bar_time_show_under_title_value"
        case .hide:
            "preferences_appearance_status_bar_time_hide_value"
        }
    }
}

enum PreferencesStatusTone: Equatable {
    case neutral
    case success
    case warning
    case error
}

enum PreferencesProviderConnectionState: Equatable {
    case initializing
    case connected
    case authRequired
    case permissionRequired
    case stale
    case error
}

struct PreferencesCalendarPresentation: Equatable {
    let activeProvider: EventStoreProvider
    let connectionState: PreferencesProviderConnectionState
    let statusTone: PreferencesStatusTone
    let selectedCalendarCount: Int
    let availableCalendarCount: Int
    let canReconnect: Bool
    let canOpenCalendarSettings: Bool
    let providerTitleKey: String
    let statusTextKey: String
    let emptyStateTextKey: String

    static func make(from state: AppState) -> PreferencesCalendarPresentation {
        let connectionState: PreferencesProviderConnectionState
        let statusTone: PreferencesStatusTone
        let statusTextKey: String

        if state.providerHealth.authRequired {
            connectionState = .authRequired
            statusTone = .error
            statusTextKey = "preferences_status_state_auth_required"
        } else if state.activeProvider == .macOSEventKit,
                  state.providerHealth.lastErrorDescription != nil,
                  state.providerHealth.lastSuccessfulRefresh == nil {
            connectionState = .permissionRequired
            statusTone = .error
            statusTextKey = "preferences_status_state_permission_required"
        } else if state.providerHealth.isStale {
            connectionState = .stale
            statusTone = .warning
            statusTextKey = "preferences_status_state_stale"
        } else if state.providerHealth.lastErrorDescription != nil {
            connectionState = .error
            statusTone = .error
            statusTextKey = "preferences_status_state_error"
        } else if state.providerHealth.lastSuccessfulRefresh != nil {
            connectionState = .connected
            statusTone = .success
            statusTextKey = "preferences_status_state_ok"
        } else {
            connectionState = .initializing
            statusTone = .neutral
            statusTextKey = "preferences_status_state_initializing"
        }

        let providerTitleKey = switch state.activeProvider {
        case .macOSEventKit:
            "onboarding_apple_calendar_title"
        case .googleCalendar:
            "onboarding_google_calendar_title"
        }

        let emptyStateTextKey = switch connectionState {
        case .authRequired:
            "onboarding_calendar_selection_reconnect"
        case .permissionRequired:
            "onboarding_calendar_selection_permission"
        case .initializing, .connected, .stale, .error:
            "onboarding_calendar_selection_empty"
        }

        return PreferencesCalendarPresentation(
            activeProvider: state.activeProvider,
            connectionState: connectionState,
            statusTone: statusTone,
            selectedCalendarCount: state.selectedCalendarIDs.count,
            availableCalendarCount: state.calendars.count,
            canReconnect: state.activeProvider == .googleCalendar
                && connectionState == .authRequired,
            canOpenCalendarSettings: state.activeProvider == .macOSEventKit
                && connectionState == .permissionRequired,
            providerTitleKey: providerTitleKey,
            statusTextKey: statusTextKey,
            emptyStateTextKey: emptyStateTextKey
        )
    }
}

enum ProviderPickerSelectionPolicy {
    static func synchronizedSelection(
        currentSelection: EventStoreProvider,
        activeProvider: EventStoreProvider,
        providerChangeInProgress: Bool
    ) -> EventStoreProvider {
        providerChangeInProgress ? currentSelection : activeProvider
    }

    static func shouldRequestChange(
        selectedProvider: EventStoreProvider,
        activeProvider: EventStoreProvider,
        providerChangeInProgress: Bool
    ) -> Bool {
        selectedProvider != activeProvider && !providerChangeInProgress
    }
}

struct CalendarSelectionChange: Equatable {
    let id: String
    let selected: Bool
}

enum CalendarSelectionBulkPolicy {
    static func changes(
        calendars: [MBCalendar],
        selectedCalendarIDs: [String],
        selectingAll: Bool
    ) -> [CalendarSelectionChange] {
        if selectingAll {
            let selectedIDs = Set(selectedCalendarIDs)
            return calendars.compactMap { calendar in
                guard !selectedIDs.contains(calendar.id) else { return nil }
                return CalendarSelectionChange(id: calendar.id, selected: true)
            }
        }

        return selectedCalendarIDs.map {
            CalendarSelectionChange(id: $0, selected: false)
        }
    }
}

enum MeetingProviderBrowserSelection {
    static func selectedBrowser(
        providerID: String,
        providerBrowsers: [String: Browser]
    ) -> Browser {
        providerBrowsers[providerID] ?? systemDefaultBrowser
    }

    static func updating(
        providerID: String,
        browser: Browser,
        providerBrowsers: [String: Browser]
    ) -> [String: Browser] {
        var updated = providerBrowsers
        if browser == systemDefaultBrowser {
            updated.removeValue(forKey: providerID)
        } else {
            updated[providerID] = browser
        }
        return updated
    }
}
