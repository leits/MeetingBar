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
    static let calendarTitle = Key<String>("calendarTitle", default: "") // Backward compatibility
    static let selectedCalendars = Key<[String]>("selectedCalendars", default: []) // Backward compatibility
    static let selectedCalendarIDs = Key<[String]>("selectedCalendarIDs", default: [])

    static let onboardingCompleted = Key<Bool>("onboardingCompleted", default: false)

    static let showEventsForPeriod = Key<ShowEventsForPeriod>("showEventsForPeriod", default: .today)
    static let joinEventNotification = Key<Bool>("joinEventNotification", default: true)
    static let joinEventNotificationTime = Key<JoinEventNotificationTime>("joinEventNotificationTime", default: .atStart)
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)

    // Status Bar Appearance
    static let showEventTitleInStatusBar = Key<Bool?>("showEventTitleInStatusBar") // Backward compatibility
    static let eventTitleFormat = Key<EventTitleFormat>("eventTitleFormat", default: .show)
    static let titleLength = Key<Double>("titleLength", default: TitleLengthLimits.max)

    // Menu Appearance
    static let shortenEventTitle = Key<Bool>("shortenEventTitle", default: true)
    static let menuEventTitleLength = Key<Double>("menuEventTitleLength", default: MenuTitleLengthLimits.max)

    static let showEventDetails = Key<Bool>("showEventDetails", default: false)
    static let showMeetingServiceIcon = Key<Bool>("showMeetingServiceIcon", default: true)

    static let declinedEventsAppereance = Key<DeclinedEventsAppereance>("declinedEventsAppereance", default: .strikethrough)
    static let pastEventsAppereance = Key<PastEventsAppereance>("pastEventsAppereance", default: .show_inactive)
    static let personalEventsAppereance = Key<PastEventsAppereance>("personalEventsAppereance", default: .show_active)
    static let disablePastEvents = Key<Bool?>("disablePastEvents")
    static let hidePastEvents = Key<Bool>("hidePastEvents", default: false)
    static let timeFormat = Key<TimeFormat>("timeFormat", default: .military)

    // Bookmark 1
    static let bookmarkMeetingName = Key<String>("bookmarkMeetingName", default: "")
    static let bookmarkMeetingService = Key<MeetingServices>("bookmarkMeetingService", default: .other)
    static let bookmarkMeetingURL = Key<String>("bookmarkMeetingURL", default: "")

    // Bookmark 2
    static let bookmarkMeetingName2 = Key<String>("bookmarkMeetingName2", default: "")
    static let bookmarkMeetingService2 = Key<MeetingServices>("bookmarkMeetingService2", default: .other)
    static let bookmarkMeetingURL2 = Key<String>("bookmarkMeetingURL2", default: "")

    // Bookmark 3
    static let bookmarkMeetingName3 = Key<String>("bookmarkMeetingName3", default: "")
    static let bookmarkMeetingService3 = Key<MeetingServices>("bookmarkMeetingService3", default: .other)
    static let bookmarkMeetingURL3 = Key<String>("bookmarkMeetingURL3", default: "")

    // Bookmark 4
    static let bookmarkMeetingName4 = Key<String>("bookmarkMeetingName4", default: "")
    static let bookmarkMeetingService4 = Key<MeetingServices>("bookmarkMeetingService4", default: .other)
    static let bookmarkMeetingURL4 = Key<String>("bookmarkMeetingURL4", default: "")

    // Bookmark 5
    static let bookmarkMeetingName5 = Key<String>("bookmarkMeetingName5", default: "")
    static let bookmarkMeetingService5 = Key<MeetingServices>("bookmarkMeetingService5", default: .other)
    static let bookmarkMeetingURL5 = Key<String>("bookmarkMeetingURL5", default: "")

    // show all day events - by default true
    static let allDayEvents = Key<Bool>("allDayEvents", default: true)
    // show all day events only when they have a meeting link
    static let allDayEventsWithLinkOnly = Key<Bool>("allDayEventsWithLinkOnly", default: false)

    // show the end date of a meeting in the meetingbar for each event entry
    static let showEventEndDate = Key<Bool>("showEventEndDate", default: true)

    // Integrations
    static let createMeetingService = Key<CreateMeetingServices>("createMeetingService", default: .zoom)
    static let useChromeForMeetLinks = Key<ChromeExecutable>("useChromeForMeetLinks", default: .defaultBrowser)
    static let useChromeForHangoutsLinks = Key<ChromeExecutable>("useChromeForHangoutsLinks", default: .defaultBrowser)
    static let useAppForZoomLinks = Key<Bool>("useAppForZoomLinks", default: false)
    static let useAppForTeamsLinks = Key<Bool>("useAppForTeamsLinks", default: false)

    // Advanced
    static let joinEventScriptLocation = Key<URL?>("joinEventScriptLocation", default: nil)
    static let runJoinEventScript = Key<Bool>("runAppleScriptWhenJoiningEvent", default: false)
    static let joinEventScript = Key<String>("joinEventScript", default: "# write your script here\ntell application \"Music\" to pause")
    static let customRegexes = Key<[String]>("customRegexes", default: [])
}
