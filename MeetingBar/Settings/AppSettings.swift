//
//  AppSettings.swift
//  MeetingBar
//
//  Pure value-type snapshot of all user-configurable settings.
//  No imports from Defaults — constructed by SettingsStore.
//

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
    var meetBrowser: Browser
    var zoomBrowser: Browser
    var teamsBrowser: Browser
    var jitsiBrowser: Browser
    var slackBrowser: Browser
    var riversideBrowser: Browser
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
