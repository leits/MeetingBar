//
//  DefaultsKeys.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import Defaults
import Foundation

extension Defaults.Keys {
    // General
    static let appVersion = Key<String>("appVersion", default: "2.0.5")
    static let lastRevisedVersionInChangelog = Key<String>("lastRevisedVersionInChangelog", default: "4.2.0")

    static let isInstalledFromAppStore = Key<Bool>("isInstalledFromAppStore", default: false)
    static let patronageDuration = Key<Int>("patronageDuration", default: 0)

    static let selectedCalendarIDs = Key<[String]>("selectedCalendarIDs", default: [])
    static let eventStoreProvider = Key<EventStoreProvider>("eventStoreProvider", default: .macOSEventKit)

    static let onboardingCompleted = Key<Bool>("onboardingCompleted", default: false)

    static let showEventsForPeriod = Key<ShowEventsForPeriod>("showEventsForPeriod", default: .today)
    static let joinEventNotification = Key<Bool>("joinEventNotification", default: true)
    static let joinEventNotificationTime = Key<JoinEventNotificationTime>("joinEventNotificationTime", default: .atStart)

    static let automaticEventJoin = Key<Bool>("automaticEventJoin", default: false)
    static let automaticEventJoinTime = Key<AutomaticEventJoinTime>("automaticEventJoinTime", default: .atStart)
    static let processedEventsForAutoJoin = Key<[ProcessedEvent]>("processedEventsForAutoJoin", default: [])

    static let preferredLanguage = Key<AppLanguage>("preferredLanguage", default: .system)

    // Status Bar Appearance
    static let eventTitleFormat = Key<EventTitleFormat>("eventTitleFormat", default: .show)
    static let eventTimeFormat = Key<EventTimeFormat>("eventTimeFormat", default: .show)

    static let eventTitleIconFormat = Key<EventTitleIconFormat>("eventTitleIconFormat", default: .none)
    static let statusbarEventTitleLength = Key<Int>("statusbarEventTitleLength", default: statusbarEventTitleLengthLimits.max)

    static let hideMeetingTitle = Key<Bool>("hideMeetingTitle", default: false)
    static let dismissedEvents = Key<[ProcessedEvent]>("dismissedEvents", default: [])

    // Menu Appearance
    // if the event title in the menu should be shortened or not -> the length will be stored in field menuEventTitleLength
    static let shortenEventTitle = Key<Bool>("shortenEventTitle", default: true)
    static let menuEventTitleLength = Key<Int>("menuEventTitleLength", default: 50)

    static let showEventDetails = Key<Bool>("showEventDetails", default: false)
    static let showMeetingServiceIcon = Key<Bool>("showMeetingServiceIcon", default: true)

    static let declinedEventsAppereance = Key<DeclinedEventsAppereance>("declinedEventsAppereance", default: .strikethrough)
    static let pastEventsAppereance = Key<PastEventsAppereance>("pastEventsAppereance", default: .show_inactive)
    static let personalEventsAppereance = Key<PastEventsAppereance>("personalEventsAppereance", default: .show_active)

    static let showEventMaxTimeUntilEventThreshold = Key<Int>("showEventMaxTimeUntilEventThreshold", default: 60)
    static let showEventMaxTimeUntilEventEnabled = Key<Bool>("showEventMaxTimeUntilEventEnabled", default: false)

    // appearance of pending events should be shown in the statusbar and menu
    static let showPendingEvents = Key<PendingEventsAppereance>("showPendingEvents", default: PendingEventsAppereance.show)

    // appearance of tentative events
    static let showTentativeEvents = Key<TentativeEventsAppereance>("showTentativeEvents", default: TentativeEventsAppereance.show)

    static let timeFormat = Key<TimeFormat>("timeFormat", default: .military)

    // Bookmarks
    static let bookmarks = Key<[Bookmark]>("bookmarks", default: [])

    // all browser configurations
    static let browsers = Key<[Browser]>("browsers", default: [])

    // default browser for meeting links
    static let defaultBrowser = Key<Browser>("defaultBrowser", default: Browser(name: "Default Browser", path: "", arguments: "", deletable: false))

    // show all day events - by default true
    static let allDayEvents = Key<AlldayEventsAppereance>("allDayEvents", default: AlldayEventsAppereance.show)

    // show all day events - by default show all, also events without any link
    static let nonAllDayEvents = Key<NonAlldayEventsAppereance>("nonAllDayEvents", default: NonAlldayEventsAppereance.show)

    // show the end time of a meeting in the meetingbar for each event entry
    static let showEventEndTime = Key<Bool>("showEventEndTime", default: true)

    // Integrations
    static let createMeetingService = Key<CreateMeetingServices>("createMeetingService", default: .zoom)

    // custom url to create meetings
    static let createMeetingServiceUrl = Key<String>("createMeetingServiceUrl", default: "")

    static let meetBrowser = Key<Browser>("meetBrowser", default: systemDefaultBrowser)
    static let zoomBrowser = Key<Browser>("zoomBrowser", default: systemDefaultBrowser)
    static let teamsBrowser = Key<Browser>("teamsBrowser", default: systemDefaultBrowser)
    static let jitsiBrowser = Key<Browser>("jitsiBrowser", default: systemDefaultBrowser)
    static let slackBrowser = Key<Browser>("slackBrowser", default: systemDefaultBrowser)

    /**
     * browser used for creating a new meeting
     */
    static let browserForCreateMeeting = Key<Browser>("browserForCreateMeeting", default: systemDefaultBrowser)

    // Advanced
    static let joinEventScriptLocation = Key<URL?>("joinEventScriptLocation", default: nil)
    static let runJoinEventScript = Key<Bool>("runAppleScriptWhenJoiningEvent", default: false)
    static let joinEventScript = Key<String>("joinEventScript", default: "preferences_advanced_apple_script_placeholder".loco())

    static let eventStartScriptLocation = Key<URL?>("eventStartScriptLocation", default: nil)
    static let runEventStartScript = Key<Bool>("runEventStartScript", default: false)
    static let eventStartScriptTime = Key<EventScriptExecutionTime>("eventStartScriptTime", default: .atStart)
    static let eventStartScript = Key<String>("eventStartScript", default: eventStartScriptPlaceholder)
    static let processedEventsForRunScriptOnEventStart = Key<[ProcessedEvent]>("processedEventsForRunScriptOnEventStart", default: [])

    static let customRegexes = Key<[String]>("customRegexes", default: [])
    static let filterEventRegexes = Key<[String]>("filterEventRegexes", default: [])
}
