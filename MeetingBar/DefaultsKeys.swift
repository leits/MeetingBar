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
    static let showEventDetails = Key<Bool>("showEventDetails", default: false)
    static let declinedEventsAppereance = Key<DeclinedEventsAppereance>("declinedEventsAppereance", default: .strikethrough)
    static let pastEventsAppereance = Key<PastEventsAppereance>("pastEventsAppereance", default: .show_inactive)
    static let personalEventsAppereance = Key<PastEventsAppereance>("personalEventsAppereance", default: .show_active)
    static let disablePastEvents = Key<Bool?>("disablePastEvents")
    static let timeFormat = Key<TimeFormat>("timeFormat", default: .military)

    // Bookmark
    static let bookmarkMeetingName = Key<String>("bookmarkMeetingName", default: "")
    static let bookmarkMeetingService = Key<MeetingServices>("bookmarkMeetingService", default: .zoom)
    static let bookmarkMeetingURL = Key<String>("bookmarkMeetingURL", default: "")
  
    // show all day events - by default true
    static let allDayEvents = Key<Bool>("allDayEvents", default: true)
    // show all day events only when they have a meeting link
    static let allDayEventsWithLinkOnly = Key<Bool>("allDayEventsWithLinkOnly", default: false)

    // Integrations
    static let createMeetingService = Key<CreateMeetingServices>("createMeetingService", default: .zoom)
    static let useChromeForMeetLinks = Key<Bool>("useChromeForMeetLinks", default: false)
    static let useChromeForHangoutsLinks = Key<Bool>("useChromeForHangoutsLinks", default: false)
    static let useAppForZoomLinks = Key<Bool>("useAppForZoomLinks", default: false)
    static let useAppForTeamsLinks = Key<Bool>("useAppForTeamsLinks", default: false)

    // Advanced
    static let joinEventScriptLocation = Key<URL?>("joinEventScriptLocation", default: nil)
    static let runJoinEventScript = Key<Bool>("runAppleScriptWhenJoiningEvent", default: false)
    static let joinEventScript = Key<String>("joinEventScript", default: "# write your script here\ntell application \"Music\" to pause")
    static let customRegexes = Key<[String]>("customRegexes", default: [])
}
