//
//  AppSettings.swift
//  MeetingBar
//
//  Value-type snapshot of all user-configurable settings.
//  `AppSettings.current` is the single boundary that reads `Defaults`.
//  Feature logic should consume an `AppSettings` (or sub-struct) by value.
//

import Defaults
import Foundation

// MARK: - Sub-structs

struct CalendarSettings: Equatable {
    var selectedCalendarIDs: [String]
    var eventStoreProvider: EventStoreProvider
}

struct EventDisplaySettings: Equatable {
    var showEventsForPeriod: ShowEventsForPeriod
    var allDayEvents: AlldayEventsAppereance
    var nonAllDayEvents: NonAlldayEventsAppereance
    var declinedEventsAppearance: DeclinedEventsAppereance
    var pastEventsAppearance: PastEventsAppereance
    var personalEventsAppearance: PastEventsAppereance
    var showPendingEvents: PendingEventsAppereance
    var showTentativeEvents: TentativeEventsAppereance
    var filterEventRegexes: [String]
    var dismissedEvents: [ProcessedEvent]
    var ongoingEventVisibility: OngoingEventVisibility
    var showEventMaxTimeUntilEventEnabled: Bool
    var showEventMaxTimeUntilEventThreshold: Int
}

struct StatusBarSettings: Equatable {
    var eventTitleFormat: EventTitleFormat
    var eventTimeFormat: EventTimeFormat
    var eventTitleIconFormat: EventTitleIconFormat
    var statusbarEventTitleLength: Int
    var hideMeetingTitle: Bool
    var showEventEndTime: Bool
}

struct MenuSettings: Equatable {
    var showTimelineInMenu: Bool
    var shortenEventTitle: Bool
    var menuEventTitleLength: Int
    var showEventDetails: Bool
    var showMeetingServiceIcon: Bool
}

struct NotificationSettings: Equatable {
    var joinEventNotification: Bool
    var joinEventNotificationTime: TimeBeforeEvent
    var endOfEventNotification: Bool
    var endOfEventNotificationTime: TimeBeforeEventEnd
    var fullscreenNotification: Bool
    var fullscreenNotificationTime: TimeBeforeEvent
}

struct MeetingSettings: Equatable {
    var createMeetingService: CreateMeetingServices
    var createMeetingServiceUrl: String
    var bookmarks: [Bookmark]
    var browsers: [Browser]
    var defaultBrowser: Browser
    var browserForCreateMeeting: Browser
    /// Unified per-provider browser preferences (keyed by provider ID).
    /// Replaces the individual meetBrowser/zoomBrowser/… fields.
    var providerBrowsers: [String: Browser]
}

struct AdvancedSettings: Equatable {
    var automaticEventJoin: Bool
    var automaticEventJoinTime: TimeBeforeEvent
    var runJoinEventScript: Bool
    var joinEventScriptLocation: URL?
    var joinEventScript: String
    var runEventStartScript: Bool
    var eventStartScriptLocation: URL?
    var eventStartScriptTime: TimeBeforeEvent
    var eventStartScript: String
    var customRegexes: [String]
}

// MARK: - Root

struct AppSettings: Equatable {
    var calendar: CalendarSettings
    var events: EventDisplaySettings
    var statusBar: StatusBarSettings
    var menu: MenuSettings
    var notifications: NotificationSettings
    var meetings: MeetingSettings
    var advanced: AdvancedSettings
}

// MARK: - Defaults factory

extension AppSettings {
    /// The single boundary that reads `Defaults` for app-level feature logic.
    /// Other code should receive `AppSettings` (or sub-structs) by value.
    @MainActor
    static var current: AppSettings {
        AppSettings(
            calendar: CalendarSettings(
                selectedCalendarIDs: Defaults[.selectedCalendarIDs],
                eventStoreProvider: Defaults[.eventStoreProvider]
            ),
            events: EventDisplaySettings(
                showEventsForPeriod: Defaults[.showEventsForPeriod],
                allDayEvents: Defaults[.allDayEvents],
                nonAllDayEvents: Defaults[.nonAllDayEvents],
                declinedEventsAppearance: Defaults[.declinedEventsAppereance],
                pastEventsAppearance: Defaults[.pastEventsAppereance],
                personalEventsAppearance: Defaults[.personalEventsAppereance],
                showPendingEvents: Defaults[.showPendingEvents],
                showTentativeEvents: Defaults[.showTentativeEvents],
                filterEventRegexes: Defaults[.filterEventRegexes],
                dismissedEvents: Defaults[.dismissedEvents],
                ongoingEventVisibility: Defaults[.ongoingEventVisibility],
                showEventMaxTimeUntilEventEnabled: Defaults[.showEventMaxTimeUntilEventEnabled],
                showEventMaxTimeUntilEventThreshold: Defaults[.showEventMaxTimeUntilEventThreshold]
            ),
            statusBar: StatusBarSettings(
                eventTitleFormat: Defaults[.eventTitleFormat],
                eventTimeFormat: Defaults[.eventTimeFormat],
                eventTitleIconFormat: Defaults[.eventTitleIconFormat],
                statusbarEventTitleLength: Defaults[.statusbarEventTitleLength],
                hideMeetingTitle: Defaults[.hideMeetingTitle],
                showEventEndTime: Defaults[.showEventEndTime]
            ),
            menu: MenuSettings(
                showTimelineInMenu: Defaults[.showTimelineInMenu],
                shortenEventTitle: Defaults[.shortenEventTitle],
                menuEventTitleLength: Defaults[.menuEventTitleLength],
                showEventDetails: Defaults[.showEventDetails],
                showMeetingServiceIcon: Defaults[.showMeetingServiceIcon]
            ),
            notifications: NotificationSettings(
                joinEventNotification: Defaults[.joinEventNotification],
                joinEventNotificationTime: Defaults[.joinEventNotificationTime],
                endOfEventNotification: Defaults[.endOfEventNotification],
                endOfEventNotificationTime: Defaults[.endOfEventNotificationTime],
                fullscreenNotification: Defaults[.fullscreenNotification],
                fullscreenNotificationTime: Defaults[.fullscreenNotificationTime]
            ),
            meetings: MeetingSettings(
                createMeetingService: Defaults[.createMeetingService],
                createMeetingServiceUrl: Defaults[.createMeetingServiceUrl],
                bookmarks: Defaults[.bookmarks],
                browsers: Defaults[.browsers],
                defaultBrowser: Defaults[.defaultBrowser],
                browserForCreateMeeting: Defaults[.browserForCreateMeeting],
                providerBrowsers: Defaults[.providerBrowsers]
            ),
            advanced: AdvancedSettings(
                automaticEventJoin: Defaults[.automaticEventJoin],
                automaticEventJoinTime: Defaults[.automaticEventJoinTime],
                runJoinEventScript: Defaults[.runJoinEventScript],
                joinEventScriptLocation: Defaults[.joinEventScriptLocation],
                joinEventScript: Defaults[.joinEventScript],
                runEventStartScript: Defaults[.runEventStartScript],
                eventStartScriptLocation: Defaults[.eventStartScriptLocation],
                eventStartScriptTime: Defaults[.eventStartScriptTime],
                eventStartScript: Defaults[.eventStartScript],
                customRegexes: Defaults[.customRegexes]
            )
        )
    }
}
