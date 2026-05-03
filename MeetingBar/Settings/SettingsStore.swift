//
//  SettingsStore.swift
//  MeetingBar
//
//  The single owner of all Defaults reads for app-level feature logic.
//  All other feature code should receive AppSettings (or sub-structs)
//  via injection rather than reading Defaults directly.
//

@preconcurrency import Defaults
import Foundation

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    var settings: AppSettings {
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
